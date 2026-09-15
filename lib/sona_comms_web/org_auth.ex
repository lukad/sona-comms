defmodule SonaCommsWeb.OrgAuth do
  @moduledoc """
  Membership and admin gates for LiveViews (ADR 0004).

  Declare one of these in every member or admin LiveView:

      on_mount {SonaCommsWeb.OrgAuth, :require_member}
      on_mount {SonaCommsWeb.OrgAuth, :require_admin}

  `:require_member` enriches `@current_scope` with `organisation_id` and
  `admin?`, and redirects users without an active membership to `/no-access`.
  When connected, it subscribes to `"user:<id>:access"` and sends the
  LiveView to `/no-access` on `{:access_revoked, _}`.

  `:require_admin` also checks `SonaComms.Org.admin?/1` against the database.
  """
  use SonaCommsWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias SonaComms.Org

  def on_mount(:require_member, _params, _session, socket) do
    case Org.put_member_scope(socket.assigns.current_scope) do
      {:ok, scope} ->
        {:cont, socket |> assign(:current_scope, scope) |> watch_access()}

      {:error, :no_access} ->
        {:halt, redirect(socket, to: ~p"/no-access")}
    end
  end

  def on_mount(:require_admin, params, session, socket) do
    with {:cont, socket} <- on_mount(:require_member, params, session, socket) do
      if Org.admin?(socket.assigns.current_scope) do
        {:cont, socket}
      else
        socket =
          socket
          |> put_flash(:error, "Only admins can manage venues, teams and staff.")
          |> redirect(to: ~p"/")

        {:halt, socket}
      end
    end
  end

  defp watch_access(socket) do
    if connected?(socket) do
      :ok = Org.subscribe_access(socket.assigns.current_scope)
      attach_hook(socket, :org_access, :handle_info, &handle_access/2)
    else
      socket
    end
  end

  defp handle_access({:access_revoked, _organisation_id}, socket) do
    socket =
      socket
      |> put_flash(:error, "You no longer have access to your organisation's chats.")
      |> push_navigate(to: ~p"/no-access")

    {:halt, socket}
  end

  defp handle_access(_message, socket), do: {:cont, socket}
end
