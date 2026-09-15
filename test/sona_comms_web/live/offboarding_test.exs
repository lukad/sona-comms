defmodule SonaCommsWeb.OffboardingTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts.Scope
  alias SonaComms.Chat
  alias SonaComms.Org

  setup do
    demo_org_fixture()
  end

  test "removing Charlie through Staff pushes their open chat to /no-access", %{
    conn: conn,
    org: org,
    alice: alice,
    charlie: charlie,
    bristol: bristol,
    conversations: c
  } do
    charlie_conn = log_in_user(build_conn(), charlie)
    {:ok, charlie_lv, _html} = live(charlie_conn, ~p"/c/#{c.foh.id}")
    assert has_element?(charlie_lv, "#conversation-header")

    # Charlie also has a DM, which must close too
    {:ok, dm} = Chat.start_dm(member_scope_fixture(charlie), alice.id)

    [membership] =
      Org.list_memberships(Scope.for_system(org.id), venue_id: bristol.id)
      |> Enum.filter(&(&1.user_id == charlie.id))

    {:ok, alice_lv, _html} =
      conn |> log_in_user(alice) |> live(~p"/org/members?venue_id=#{bristol.id}")

    alice_lv |> element("#end-membership-#{membership.id}") |> render_click()
    refute has_element?(alice_lv, "#members-#{membership.id}")

    assert {"/no-access", flash} = assert_redirect(charlie_lv)
    assert flash["error"] =~ "no longer have access"

    for id <- [c.foh.id, c.bristol.id, c.org.id, dm.id] do
      assert {:error, {:redirect, %{to: "/no-access"}}} = live(charlie_conn, ~p"/c/#{id}")
    end

    assert {:error, {:redirect, %{to: "/no-access"}}} = live(charlie_conn, ~p"/")
    assert {:ok, _lv, _html} = live(charlie_conn, ~p"/no-access")
  end
end
