defmodule SonaCommsWeb.DevSessionControllerTest do
  use SonaCommsWeb.ConnCase, async: true

  import SonaComms.OrgFixtures

  alias SonaComms.Accounts

  setup do
    demo_org_fixture()
  end

  describe "GET /dev/switch-user" do
    test "lists the personas", %{conn: conn, alice: alice, bob: bob, charlie: charlie} do
      conn = get(conn, ~p"/dev/switch-user")
      document = conn |> html_response(200) |> LazyHTML.from_document()

      assert document |> LazyHTML.query("#dev-users") |> Enum.count() == 1

      for user <- [alice, bob, charlie] do
        button = LazyHTML.query(document, "#switch-to-#{user.id}")
        assert Enum.count(button) == 1
        assert LazyHTML.text(button) =~ user.name
      end
    end
  end

  describe "POST /dev/switch-user/:user_id" do
    test "logs in and redirects to /", %{conn: conn, bob: bob} do
      conn = post(conn, ~p"/dev/switch-user/#{bob.id}")

      assert redirected_to(conn) == ~p"/"

      assert {%{id: user_id}, _} =
               Accounts.get_user_by_session_token(get_session(conn, :user_token))

      assert user_id == bob.id

      conn = get(recycle(conn), ~p"/")
      assert html_response(conn, 200) =~ "London · Kitchen"
    end

    test "while logged in as someone else, redirects to / and disconnects them", %{
      conn: conn,
      alice: alice,
      bob: bob
    } do
      conn = log_in_user(conn, alice)
      alice_token = get_session(conn, :user_token)
      live_socket_id = "users_sessions:#{Base.url_encode64(alice_token)}"
      SonaCommsWeb.Endpoint.subscribe(live_socket_id)

      conn =
        conn
        |> put_session(:live_socket_id, live_socket_id)
        |> post(~p"/dev/switch-user/#{bob.id}")

      assert redirected_to(conn) == ~p"/"
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
      refute Accounts.get_user_by_session_token(alice_token)

      assert {%{id: user_id}, _} =
               Accounts.get_user_by_session_token(get_session(conn, :user_token))

      assert user_id == bob.id
    end
  end
end
