defmodule SonaCommsWeb.OrgComponents do
  @moduledoc """
  Components for the "Venues & teams" and "Staff" screens (WP2c).

  Copy follows PLAN.md §6.4: a membership is shown as a person's place on a
  venue or team, and its role as "Role".
  """
  use SonaCommsWeb, :html

  alias SonaComms.Accounts
  alias SonaComms.Org.Membership

  @role_help %{
    admin:
      "Posts announcements to the whole group and its venues. Manages venues, teams and staff.",
    manager: "Posts announcements to their team, or their venue if they have no team.",
    staff: "Chats only."
  }

  @doc "The roles in the order the membership form shows them, most junior first."
  def roles, do: Membership.roles()

  @doc "The UI label for a role: Staff, Manager, Admin."
  def role_label(role), do: role |> to_string() |> String.capitalize()

  @doc "The help text for a role."
  def role_help(role), do: Map.fetch!(@role_help, role)

  @doc ~S|"0 people", "1 person", "12 people".|
  def people(1), do: "1 person"
  def people(count), do: "#{count} people"

  @doc ~S|Where a membership places someone: "Bristol · FOH", or "Bristol".|
  def placement(%Membership{venue: venue, team: nil}), do: venue.name
  def placement(%Membership{venue: venue, team: team}), do: "#{venue.name} · #{team.name}"

  @doc "The confirm copy for removing someone from a venue or team."
  def removal_confirm(%Membership{user: user} = membership) do
    "#{Accounts.display_name(user)} will lose access to #{placement(membership)} chats. " <>
      "If this is their only venue or team, they lose access to all chats."
  end

  @doc "A small count of people, e.g. on a team row."
  attr :count, :integer, required: true
  attr :class, :any, default: nil

  def people_count(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 text-xs tabular-nums",
      if(@count == 0, do: "text-base-content/40", else: "text-base-content/60"),
      @class
    ]}>
      <.icon name="hero-user-group-micro" class="size-3.5" />
      {people(@count)}
    </span>
    """
  end

  @doc "A pill for a role."
  attr :role, :atom, required: true

  def role_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium",
      @role == :admin && "bg-primary/10 text-primary",
      @role == :manager && "bg-secondary/10 text-secondary",
      @role == :staff && "bg-base-200 text-base-content/70"
    ]}>
      <.icon :if={@role == :admin} name="hero-shield-check-micro" class="size-3.5" />
      <.icon :if={@role == :manager} name="hero-star-micro" class="size-3.5" />
      {role_label(@role)}
    </span>
    """
  end

  @doc "A round avatar with a person's initial."
  attr :user, :map, required: true

  def avatar(assigns) do
    ~H"""
    <span class="grid size-9 shrink-0 place-items-center rounded-full bg-base-200 text-sm font-semibold text-base-content/70 ring-1 ring-base-300">
      {@user |> Accounts.display_name() |> String.first() |> String.upcase()}
    </span>
    """
  end

  @doc """
  The role picker for the membership form: one radio card per role, with
  its help text.
  """
  attr :field, Phoenix.HTML.FormField, required: true

  def role_picker(assigns) do
    assigns = assign(assigns, :selected, to_string(assigns.field.value))

    ~H"""
    <fieldset class="fieldset mb-2">
      <legend class="label mb-1">Role</legend>
      <div class="grid gap-2">
        <label
          :for={role <- roles()}
          for={"#{@field.id}-#{role}"}
          class={[
            "flex cursor-pointer items-start gap-3 rounded-box border p-3 transition",
            if(@selected == to_string(role),
              do: "border-primary bg-primary/5 ring-1 ring-primary/30",
              else: "border-base-300 hover:border-base-content/30 hover:bg-base-200/50"
            )
          ]}
        >
          <input
            type="radio"
            id={"#{@field.id}-#{role}"}
            name={@field.name}
            value={role}
            checked={@selected == to_string(role)}
            class="radio radio-sm radio-primary mt-0.5"
          />
          <span class="grid gap-0.5">
            <span class="text-sm font-medium text-base-content">{role_label(role)}</span>
            <span class="text-xs text-base-content/60">{role_help(role)}</span>
          </span>
        </label>
      </div>
    </fieldset>
    """
  end
end
