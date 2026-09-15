defmodule SonaCommsWeb.OrgLive.Index do
  @moduledoc """
  "Venues & teams": the organisation's venues, their teams and how many
  people are on each. Admins create venues and teams here, and each one
  gets its own chat (PLAN.md §7, WP2c).

  Re-streams on `{:org_changed, _}` so other admins' changes show live.
  """
  use SonaCommsWeb, :live_view

  import SonaCommsWeb.OrgComponents

  alias SonaComms.Org
  alias SonaComms.Org.{Team, Venue}

  on_mount {SonaCommsWeb.OrgAuth, :require_admin}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Venues & teams
        <:subtitle>
          Every venue and team has its own chat. People join those chats when you add them in <.link
            navigate={~p"/org/members"}
            class="font-medium text-primary hover:underline"
          >
            Staff
          </.link>.
        </:subtitle>
        <:actions>
          <.button id="new-venue-button" variant="primary" patch={~p"/org/venues/new"}>
            <.icon name="hero-plus-mini" class="size-4" /> New venue
          </.button>
        </:actions>
      </.header>

      <div id="venues" phx-update="stream" class="grid gap-4">
        <div
          id="venues-empty"
          class="hidden rounded-box border border-dashed border-base-300 px-6 py-12 text-center text-sm text-base-content/60 only:block"
        >
          <.icon name="hero-building-storefront" class="mx-auto mb-2 size-8 text-base-content/30" />
          No venues yet. Add your first one to start its chat.
        </div>

        <section
          :for={{dom_id, venue} <- @streams.venues}
          id={dom_id}
          class="overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-sm transition hover:shadow-md"
        >
          <header class="flex flex-wrap items-center gap-3 px-5 py-4">
            <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
              <.icon name="hero-building-storefront" class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <h2 class="truncate font-semibold leading-tight">{venue.name}</h2>
              <.people_count count={venue.member_count} />
            </div>
            <.link
              navigate={~p"/org/members?venue_id=#{venue.id}"}
              class="btn btn-ghost btn-sm text-base-content/70"
            >
              <.icon name="hero-users-micro" class="size-4" /> Staff
            </.link>
            <.button
              id={"new-team-#{venue.id}"}
              patch={~p"/org/venues/#{venue.id}/teams/new"}
              class="btn btn-soft btn-primary btn-sm"
            >
              <.icon name="hero-plus-micro" class="size-4" /> Team
            </.button>
          </header>

          <ul class="divide-y divide-base-200 border-t border-base-200 bg-base-200/30">
            <li
              :for={team <- venue.teams}
              id={"teams-#{team.id}"}
              class="flex items-center gap-3 px-5 py-2.5 text-sm transition hover:bg-base-200/60"
            >
              <.icon name="hero-user-group" class="size-4 shrink-0 text-base-content/40" />
              <span class="min-w-0 flex-1 truncate">{team.name}</span>
              <.people_count count={team.member_count} />
            </li>
            <li :if={venue.teams == []} class="px-5 py-3 text-sm text-base-content/50">
              No teams yet. Everyone here is on the whole-venue chat.
            </li>
          </ul>
        </section>
      </div>

      <.modal
        :if={@live_action == :new_venue}
        id="venue-modal"
        show
        on_cancel={JS.patch(~p"/org")}
      >
        <h2 id="venue-modal-title" class="text-lg font-semibold">New venue</h2>
        <p id="venue-modal-description" class="mt-1 text-sm text-base-content/60">
          It gets its own chat straight away, and you're added to it as an admin.
        </p>
        <.form
          for={@form}
          id="venue-form"
          phx-change="validate_venue"
          phx-submit="save_venue"
          class="mt-5"
        >
          <.input
            field={@form[:name]}
            label="Name"
            placeholder="e.g. Leeds"
            autocomplete="off"
            phx-mounted={JS.focus()}
          />
          <.form_actions modal_id="venue-modal" submit="Create venue" />
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :new_team && @venue}
        id="team-modal"
        show
        on_cancel={JS.patch(~p"/org")}
      >
        <h2 id="team-modal-title" class="text-lg font-semibold">New team at {@venue.name}</h2>
        <p id="team-modal-description" class="mt-1 text-sm text-base-content/60">
          It gets a chat called “{@venue.name} · {team_name_preview(@form)}”. Nobody is on it until you add them in Staff.
        </p>
        <.form
          for={@form}
          id="team-form"
          phx-change="validate_team"
          phx-submit="save_team"
          class="mt-5"
        >
          <.input
            field={@form[:name]}
            label="Name"
            placeholder="e.g. Bar"
            autocomplete="off"
            phx-mounted={JS.focus()}
          />
          <.form_actions modal_id="team-modal" submit="Create team" />
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  attr :modal_id, :string, required: true
  attr :submit, :string, required: true

  defp form_actions(assigns) do
    ~H"""
    <div class="mt-6 flex justify-end gap-2">
      <button
        type="button"
        class="btn btn-ghost"
        phx-click={JS.exec("data-cancel", to: "##{@modal_id}")}
      >
        Cancel
      </button>
      <.button variant="primary" phx-disable-with="Saving…">{@submit}</.button>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Org.subscribe_org(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(page_title: "Venues & teams", form: nil, venue: nil)
     |> load_venues()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, venue: nil)
  end

  defp apply_action(socket, :new_venue, _params) do
    assign(socket, form: to_form(Org.change_venue(%Venue{})), venue: nil)
  end

  defp apply_action(socket, :new_team, %{"venue_id" => venue_id}) do
    case Map.fetch(socket.assigns.venues_by_id, venue_id) do
      {:ok, venue} ->
        assign(socket, form: to_form(Org.change_team(%Team{})), venue: venue)

      :error ->
        socket
        |> put_flash(:error, "That venue isn't available.")
        |> push_patch(to: ~p"/org")
    end
  end

  @impl true
  def handle_event("validate_venue", %{"venue" => params}, socket) do
    form = %Venue{} |> Org.change_venue(params) |> to_form(action: :validate)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save_venue", %{"venue" => params}, socket) do
    case Org.create_venue(socket.assigns.current_scope, params) do
      {:ok, venue} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{venue.name} is set up. Its chat is in your sidebar.")
         |> load_venues()
         |> push_patch(to: ~p"/org")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, unauthorized(socket)}
    end
  end

  def handle_event("validate_team", %{"team" => params}, socket) do
    form = %Team{} |> Org.change_team(params) |> to_form(action: :validate)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save_team", %{"team" => params}, socket) do
    %Venue{} = venue = socket.assigns.venue

    case Org.create_team(socket.assigns.current_scope, venue.id, params) do
      {:ok, team} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{team.name} added to #{venue.name}. Add people to it in Staff.")
         |> load_venues()
         |> push_patch(to: ~p"/org")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That venue isn't available.")
         |> load_venues()
         |> push_patch(to: ~p"/org")}

      {:error, :unauthorized} ->
        {:noreply, unauthorized(socket)}
    end
  end

  @impl true
  def handle_info({:org_changed, _what}, socket) do
    {:noreply, load_venues(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_venues(socket) do
    case Org.list_venues(socket.assigns.current_scope) do
      venues when is_list(venues) ->
        socket
        |> assign(:venues_by_id, Map.new(venues, &{to_string(&1.id), &1}))
        |> stream(:venues, venues, reset: true)

      {:error, :unauthorized} ->
        socket
        |> assign(:venues_by_id, %{})
        |> stream(:venues, [], reset: true)
        |> unauthorized()
    end
  end

  # "Bar" in the new team modal's "Bristol · Bar" preview, "…" while blank.
  defp team_name_preview(form) do
    case form[:name].value do
      name when is_binary(name) and name != "" -> String.trim(name)
      _ -> "…"
    end
  end

  defp unauthorized(socket) do
    socket
    |> put_flash(:error, "Only admins can manage venues, teams and staff.")
    |> push_navigate(to: ~p"/")
  end
end
