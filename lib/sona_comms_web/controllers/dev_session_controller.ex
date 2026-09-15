defmodule SonaCommsWeb.DevSessionController do
  @moduledoc """
  Development user switcher (ADR 0007). Only routed when `dev_routes` is on.
  """
  use SonaCommsWeb, :controller

  alias SonaComms.Accounts
  alias SonaComms.Org
  alias SonaCommsWeb.UserAuth

  @personas ~w(alice@sona.test bob@sona.test charlie@sona.test)
  @no_membership "No active membership"

  def index(conn, _params) do
    {personas, others} = Enum.split_with(Org.directory(), &persona?/1)

    groups =
      others
      |> Enum.group_by(&group_label/1)
      |> Enum.map(fn {label, entries} -> {label, Enum.sort_by(entries, &role_rank/1)} end)
      |> Enum.sort_by(fn {label, _entries} -> {label == @no_membership, label} end)

    render(conn, :index, page_title: "Switch user", personas: personas, groups: groups)
  end

  def create(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(user_id)

    conn
    |> end_current_session()
    # otherwise signed_in_path/1 sends an already-logged-in conn to settings
    |> put_session(:user_return_to, ~p"/")
    |> put_flash(:info, "Signed in as #{Accounts.display_name(user)}.")
    |> UserAuth.log_in_user(user)
  end

  # Exactly as UserAuth.log_out_user/1: log_in_user/3 alone would leave the
  # previous user's LiveViews on this host connected.
  defp end_current_session(conn) do
    if user_token = get_session(conn, :user_token) do
      Accounts.delete_user_session_token(user_token)
    end

    if live_socket_id = get_session(conn, :live_socket_id) do
      SonaCommsWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
  end

  defp persona?(%{user: user}), do: String.downcase(user.email) in @personas

  defp group_label(%{memberships: [membership | _]}),
    do: SonaCommsWeb.DevSessionHTML.location(membership)

  defp group_label(%{memberships: []}), do: @no_membership

  defp role_rank(%{memberships: [%{role: :admin} | _]}), do: 0
  defp role_rank(%{memberships: [%{role: :manager} | _]}), do: 1
  defp role_rank(_entry), do: 2
end
