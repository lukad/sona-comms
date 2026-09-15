defmodule SonaCommsWeb.NoAccessLive do
  @moduledoc """
  Where signed-in users without an active membership land (ADR 0004).
  """
  use SonaCommsWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="no-access"
        class="mx-auto mt-10 max-w-md rounded-box border border-base-300 bg-base-100 p-8 text-center shadow-sm"
      >
        <div class="mx-auto mb-4 grid size-12 place-items-center rounded-full bg-base-200">
          <.icon name="hero-lock-closed" class="size-6 text-base-content/60" />
        </div>
        <h1 class="text-lg font-semibold">No access yet</h1>
        <p class="mt-2 text-sm text-base-content/70">
          You're not on any venue or team yet. Ask your manager to add you.
        </p>
        <.link
          id="no-access-log-out"
          href={~p"/users/log-out"}
          method="delete"
          class="btn btn-ghost btn-sm mt-6"
        >
          Log out
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "No access")}
  end
end
