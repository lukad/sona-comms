defmodule SonaCommsWeb.OrgAuthTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.AccountsFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts.Scope
  alias SonaComms.Org

  setup do
    demo_org_fixture()
  end

  test "a member reaches /", %{conn: conn, bob: bob, conversations: c} do
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/")

    assert has_element?(lv, "#conversations")
    assert has_element?(lv, "#conversations-#{c.kitchen.id}")
    refute has_element?(lv, "#conversations-#{c.foh.id}")
  end

  test "a user without memberships is redirected to /no-access", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/no-access"}}} = live(conn, ~p"/")
    assert {:error, {:redirect, %{to: "/no-access"}}} = live(conn, ~p"/org")

    {:ok, lv, _html} = live(conn, ~p"/no-access")
    assert has_element?(lv, "#no-access")
  end

  test "non-admins are redirected from /org", %{conn: conn, bob: bob, charlie: charlie} do
    for user <- [bob, charlie], path <- [~p"/org", ~p"/org/members"] do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn |> log_in_user(user) |> live(path)

      assert flash["error"] =~ "Only admins"
    end
  end

  test "admins reach /org", %{conn: conn, alice: alice} do
    conn = log_in_user(conn, alice)
    assert {:ok, _lv, _html} = live(conn, ~p"/org")
    assert {:ok, _lv, _html} = live(conn, ~p"/org/members")
  end

  test "#nav-org shows for Alice and not for Bob or Charlie", %{
    conn: conn,
    alice: alice,
    bob: bob,
    charlie: charlie
  } do
    {:ok, lv, _html} = conn |> log_in_user(alice) |> live(~p"/")
    assert has_element?(lv, "#nav-org", "Venues & teams")
    assert has_element?(lv, "#nav-staff", "Staff")
    assert has_element?(lv, "#nav-dev-switch-user")

    for user <- [bob, charlie] do
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/")
      refute has_element?(lv, "#nav-org")
      refute has_element?(lv, "#nav-staff")
    end
  end

  test "broadcasting {:access_revoked, _} pushes a connected / LiveView to /no-access", %{
    conn: conn,
    org: org,
    charlie: charlie
  } do
    {:ok, lv, _html} = conn |> log_in_user(charlie) |> live(~p"/")

    Phoenix.PubSub.broadcast(
      SonaComms.PubSub,
      "user:#{charlie.id}:access",
      {:access_revoked, org.id}
    )

    assert {"/no-access", flash} = assert_redirect(lv)
    assert flash["error"] =~ "no longer have access"
  end

  test "ending the last membership pushes an open conversation to /no-access", %{
    conn: conn,
    org: org,
    charlie: charlie,
    conversations: c
  } do
    {:ok, lv, _html} = conn |> log_in_user(charlie) |> live(~p"/c/#{c.foh.id}")
    assert has_element?(lv, "#conversation-header")

    membership =
      Scope.for_system(org.id)
      |> Org.list_memberships()
      |> Enum.find(&(&1.user_id == charlie.id))

    assert {:ok, _} = Org.end_membership(Scope.for_system(org.id), membership.id)
    assert_redirect(lv, ~p"/no-access")

    assert {:error, {:redirect, %{to: "/no-access"}}} =
             conn |> log_in_user(charlie) |> live(~p"/c/#{c.foh.id}")
  end
end
