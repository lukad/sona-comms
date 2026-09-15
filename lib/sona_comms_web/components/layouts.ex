defmodule SonaCommsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SonaCommsWeb, :html

  alias SonaComms.Accounts
  alias SonaComms.Accounts.Scope

  @dev_routes? Application.compile_env(:sona_comms, :dev_routes, false)

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :full_bleed, :boolean,
    default: false,
    doc: "fill the viewport below the nav without page padding (the chat)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :dev_routes?, @dev_routes?)

    ~H"""
    <div class={["flex flex-col", if(@full_bleed, do: "h-dvh", else: "min-h-dvh")]}>
      <header class="sticky top-0 z-40 border-b border-base-300 bg-base-100/85 backdrop-blur">
        <nav class="flex h-14 items-center gap-1 px-3 sm:px-5">
          <.link
            navigate={~p"/"}
            class="group mr-3 flex items-center gap-2 font-semibold tracking-tight"
          >
            <span class="grid size-8 place-items-center rounded-lg bg-primary text-primary-content shadow-sm transition group-hover:scale-105">
              <.icon name="hero-chat-bubble-left-right-solid" class="size-4" />
            </span>
            <span class="hidden sm:inline">Sona</span>
          </.link>

          <%= if signed_in?(@current_scope) do %>
            <.nav_link navigate={~p"/"}>Chat</.nav_link>
            <.nav_link :if={Scope.admin?(@current_scope)} id="nav-org" navigate={~p"/org"}>
              Venues & teams
            </.nav_link>
            <.nav_link :if={Scope.admin?(@current_scope)} id="nav-staff" navigate={~p"/org/members"}>
              Staff
            </.nav_link>
          <% end %>

          <div class="flex-1" />

          <.link
            :if={@dev_routes?}
            id="nav-dev-switch-user"
            href={~p"/dev/switch-user"}
            class="mr-1 flex items-center gap-1 rounded-full border border-dashed border-warning/60 bg-warning/10 px-3 py-1 text-xs font-medium text-warning transition hover:bg-warning/20"
          >
            <.icon name="hero-arrows-right-left-micro" class="size-3.5" /> Switch user
          </.link>

          <%= if signed_in?(@current_scope) do %>
            <span class="hidden px-2 text-sm font-medium md:inline">
              {Accounts.display_name(@current_scope.user)}
            </span>
            <.nav_link navigate={~p"/users/settings"}>Settings</.nav_link>
            <.nav_link href={~p"/users/log-out"} method="delete">Log out</.nav_link>
          <% else %>
            <.nav_link href={~p"/users/log-in"}>Log in</.nav_link>
            <.nav_link href={~p"/users/register"}>Register</.nav_link>
          <% end %>

          <div class="ml-2 hidden sm:block">
            <.theme_toggle />
          </div>
        </nav>
      </header>

      <main :if={@full_bleed} class="min-h-0 flex-1">
        {render_slot(@inner_block)}
      </main>

      <main :if={!@full_bleed} class="px-4 py-12 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-2xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :rest, :global, include: ~w(href navigate method)
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      class="rounded-lg px-2.5 py-1.5 text-sm font-medium text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp signed_in?(%Scope{user: %Accounts.User{}}), do: true
  defp signed_in?(_scope), do: false

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
