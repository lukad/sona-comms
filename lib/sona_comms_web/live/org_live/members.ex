defmodule SonaCommsWeb.OrgLive.Members do
  @moduledoc """
  "Staff". WP1 stub, owned by WP2c.
  """
  use SonaCommsWeb, :live_view

  on_mount {SonaCommsWeb.OrgAuth, :require_admin}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Staff
        <:subtitle>Everyone on your venues and teams.</:subtitle>
      </.header>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Staff")}
  end
end
