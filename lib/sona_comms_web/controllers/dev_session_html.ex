defmodule SonaCommsWeb.DevSessionHTML do
  @moduledoc """
  Templates for the development user switcher.
  """
  use SonaCommsWeb, :html

  alias SonaComms.Accounts

  embed_templates "dev_session_html/*"

  @doc "Where a membership sits: \"Bristol\" or \"Bristol · FOH\"."
  def location(%{venue: venue, team: nil}), do: venue.name
  def location(%{venue: venue, team: team}), do: "#{venue.name} · #{team.name}"

  attr :entry, :map, required: true
  attr :current_scope, :map, default: nil
  attr :featured, :boolean, default: false

  def switch_button(assigns) do
    assigns =
      assign(assigns,
        current?:
          match?(%{user: %{id: id}} when id == assigns.entry.user.id, assigns.current_scope)
      )

    ~H"""
    <.form for={%{}} action={~p"/dev/switch-user/#{@entry.user.id}"} method="post" class="contents">
      <button
        id={"switch-to-#{@entry.user.id}"}
        type="submit"
        class={[
          "group flex w-full cursor-pointer items-center gap-3 text-left transition",
          @featured &&
            "rounded-box border border-base-300 bg-base-100 p-4 shadow-sm hover:-translate-y-0.5 hover:border-primary/50 hover:shadow-md",
          !@featured && "px-4 py-2.5 hover:bg-base-200/70"
        ]}
      >
        <span class={[
          "grid shrink-0 place-items-center rounded-full bg-primary/10 font-semibold text-primary",
          if(@featured, do: "size-10 text-base", else: "size-8 text-sm")
        ]}>
          {@entry.user |> Accounts.display_name() |> String.first() |> String.upcase()}
        </span>
        <span class="min-w-0 flex-1">
          <span class="flex items-center gap-2 font-medium">
            {Accounts.display_name(@entry.user)}
            <span :if={@current?} class="badge badge-xs badge-success">current</span>
          </span>
          <span class="block truncate text-xs text-base-content/60">
            {summary(@entry.memberships)}
          </span>
        </span>
        <.icon
          name="hero-arrow-right-end-on-rectangle"
          class="size-4 opacity-0 transition group-hover:opacity-60"
        />
      </button>
    </.form>
    """
  end

  defp summary([]), do: "No active membership"

  defp summary(memberships) do
    Enum.map_join(memberships, ", ", &"#{role_label(&1.role)} · #{location(&1)}")
  end

  defp role_label(:staff), do: "Staff"
  defp role_label(:manager), do: "Manager"
  defp role_label(:admin), do: "Admin"
end
