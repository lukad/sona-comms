defmodule SonaCommsWeb.OrgLive.Members do
  @moduledoc """
  "Staff": everyone's place on a venue or team, and their role. Admins add
  people here, which puts them in the right chats, and remove them, which
  takes those chats away (PLAN.md §7, WP2c).

  `?venue_id=` filters the list. Re-streams on `{:org_changed, _}`.
  """
  use SonaCommsWeb, :live_view

  import SonaCommsWeb.OrgComponents

  alias SonaComms.Accounts
  alias SonaComms.Org

  on_mount {SonaCommsWeb.OrgAuth, :require_admin}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Staff
        <:subtitle>
          Adding someone puts them in their venue and team chats. Removing them takes those chats away.
        </:subtitle>
        <:actions>
          <.button
            id="new-membership-button"
            variant="primary"
            patch={members_path(@venue_id, :new)}
          >
            <.icon name="hero-user-plus-mini" class="size-4" /> Add someone
          </.button>
        </:actions>
      </.header>

      <div class="flex flex-wrap items-end justify-between gap-3">
        <.form
          for={@filter_form}
          id="member-venue-filter"
          phx-change="filter"
          class="w-full sm:w-60"
        >
          <.input
            field={@filter_form[:venue_id]}
            type="select"
            label="Venue"
            prompt="All venues"
            options={venue_options(@venues)}
          />
        </.form>
        <p class="pb-3 text-sm text-base-content/60 tabular-nums">{people(@people_count)}</p>
      </div>

      <ul
        id="members"
        phx-update="stream"
        class="divide-y divide-base-200 overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-sm"
      >
        <li
          id="members-empty"
          class="hidden px-6 py-12 text-center text-sm text-base-content/60 only:block"
        >
          <.icon name="hero-users" class="mx-auto mb-2 size-8 text-base-content/30" />
          Nobody here yet.
        </li>
        <li
          :for={{dom_id, member} <- @streams.members}
          id={dom_id}
          class="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3 transition hover:bg-base-200/40"
        >
          <.avatar user={member.user} />
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium">
              {Accounts.display_name(member.user)}
              <span
                :if={member.user_id == @current_scope.user.id}
                class="font-normal text-base-content/50"
              >
                (you)
              </span>
            </p>
            <p class="truncate text-xs text-base-content/60">{member.user.email}</p>
          </div>
          <div class="min-w-0 text-sm sm:w-44">
            <p class="truncate">{member.venue.name}</p>
            <p class="truncate text-xs text-base-content/60">
              {if member.team, do: member.team.name, else: "Whole venue"}
            </p>
          </div>
          <div class="w-20">
            <.role_badge role={member.role} />
          </div>
          <button
            :if={member.user_id != @current_scope.user.id}
            id={"end-membership-#{member.id}"}
            type="button"
            phx-click="end_membership"
            phx-value-id={member.id}
            data-confirm={removal_confirm(member)}
            class="btn btn-ghost btn-sm text-error/80 hover:bg-error/10 hover:text-error"
          >
            <.icon name="hero-user-minus-micro" class="size-4" />
            <span class="hidden md:inline">Remove from {placement(member)}</span>
            <span class="md:hidden">Remove</span>
          </button>
        </li>
      </ul>

      <.modal
        :if={@live_action == :new}
        id="membership-modal"
        show
        on_cancel={JS.patch(members_path(@venue_id))}
      >
        <h2 id="membership-modal-title" class="text-lg font-semibold">Add someone</h2>
        <p id="membership-modal-description" class="mt-1 text-sm text-base-content/60">
          They join the chats for their venue and team straight away. New people get an account from their email.
        </p>
        <.form
          for={@form}
          id="membership-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-5"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="off"
            phx-debounce="blur"
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:name]}
            label="Name"
            placeholder="Only needed for someone new"
            autocomplete="off"
            phx-debounce="blur"
          />
          <div class="grid gap-x-3 sm:grid-cols-2">
            <.input
              field={@form[:venue_id]}
              type="select"
              label="Venue"
              prompt="Choose a venue"
              options={venue_options(@venues)}
            />
            <.input
              field={@form[:team_id]}
              type="select"
              label="Team"
              prompt="No team (whole venue)"
              options={team_options(@venues, @form[:venue_id].value)}
            />
          </div>
          <.role_picker field={@form[:role]} />
          <div class="mt-6 flex justify-end gap-2">
            <button
              type="button"
              class="btn btn-ghost"
              phx-click={JS.exec("data-cancel", to: "#membership-modal")}
            >
              Cancel
            </button>
            <.button variant="primary" phx-disable-with="Adding…">Add</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Org.subscribe_org(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(page_title: "Staff", venue_id: nil, form: nil)
     |> load_venues()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    venue_id = known_venue_id(socket.assigns.venues, params["venue_id"])

    {:noreply,
     socket
     |> assign(:venue_id, venue_id)
     |> assign(:filter_form, to_form(%{"venue_id" => venue_id}))
     |> load_members()
     |> apply_action(socket.assigns.live_action)}
  end

  defp apply_action(socket, :index), do: assign(socket, :form, nil)

  defp apply_action(socket, :new) do
    params = if venue_id = socket.assigns.venue_id, do: %{"venue_id" => venue_id}, else: %{}
    assign(socket, :form, to_form(Org.change_membership(params)))
  end

  @impl true
  def handle_event("filter", %{"venue_id" => venue_id}, socket) do
    {:noreply, push_patch(socket, to: members_path(venue_id))}
  end

  def handle_event("validate", %{"membership" => params}, socket) do
    params = drop_team_outside_venue(params, socket.assigns.venues)
    form = params |> Org.change_membership() |> to_form(action: :validate)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"membership" => params}, socket) do
    case Org.create_membership(socket.assigns.current_scope, params) do
      {:ok, membership} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{Accounts.display_name(membership.user)} added to #{placement(membership)}."
         )
         |> load_venues()
         |> push_patch(to: members_path(socket.assigns.venue_id))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, unauthorized(socket)}
    end
  end

  def handle_event("end_membership", %{"id" => id}, socket) do
    case Org.end_membership(socket.assigns.current_scope, id) do
      {:ok, membership} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{Accounts.display_name(membership.user)} removed from #{placement(membership)}."
         )
         |> load_members()}

      {:error, :cannot_end_own_membership} ->
        {:noreply, put_flash(socket, :error, "You can't remove yourself.")}

      {:error, reason} when reason in [:already_ended, :not_found] ->
        {:noreply,
         socket
         |> put_flash(:error, "They've already been removed.")
         |> load_members()}

      {:error, :unauthorized} ->
        {:noreply, unauthorized(socket)}
    end
  end

  @impl true
  def handle_info({:org_changed, _what}, socket) do
    {:noreply, socket |> load_venues() |> load_members()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_venues(socket) do
    case Org.list_venues(socket.assigns.current_scope) do
      venues when is_list(venues) -> assign(socket, :venues, venues)
      {:error, :unauthorized} -> socket |> assign(:venues, []) |> unauthorized()
    end
  end

  defp load_members(socket) do
    case Org.list_memberships(socket.assigns.current_scope, venue_id: socket.assigns.venue_id) do
      members when is_list(members) ->
        socket
        |> assign(:people_count, members |> Enum.uniq_by(& &1.user_id) |> length())
        |> stream(:members, members, reset: true)

      {:error, :unauthorized} ->
        socket
        |> assign(:people_count, 0)
        |> stream(:members, [], reset: true)
        |> unauthorized()
    end
  end

  defp unauthorized(socket) do
    socket
    |> put_flash(:error, "Only admins can manage venues, teams and staff.")
    |> push_navigate(to: ~p"/")
  end

  # Only venues in this organisation are accepted as a filter.
  defp known_venue_id(venues, venue_id) do
    Enum.find_value(venues, fn venue ->
      if to_string(venue.id) == venue_id, do: venue_id
    end)
  end

  # Changing the venue clears a team that belongs to another venue.
  defp drop_team_outside_venue(%{"team_id" => team_id} = params, venues)
       when team_id not in [nil, ""] do
    team_ids = venues |> team_options(params["venue_id"]) |> Enum.map(&to_string(elem(&1, 1)))
    if team_id in team_ids, do: params, else: Map.put(params, "team_id", "")
  end

  defp drop_team_outside_venue(params, _venues), do: params

  defp venue_options(venues), do: Enum.map(venues, &{&1.name, &1.id})

  defp team_options(venues, venue_id) do
    case Enum.find(venues, &(to_string(&1.id) == to_string(venue_id))) do
      nil -> []
      venue -> Enum.map(venue.teams, &{&1.name, &1.id})
    end
  end

  defp members_path(venue_id, action \\ :index)
  defp members_path(venue_id, :index) when venue_id in [nil, ""], do: ~p"/org/members"
  defp members_path(venue_id, :index), do: ~p"/org/members?#{[venue_id: venue_id]}"
  defp members_path(venue_id, :new) when venue_id in [nil, ""], do: ~p"/org/members/new"
  defp members_path(venue_id, :new), do: ~p"/org/members/new?#{[venue_id: venue_id]}"
end
