defmodule SonaCommsWeb.OrgLive.IndexTest do
  use SonaCommsWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts.Scope
  alias SonaComms.Chat
  alias SonaComms.Chat.Participant
  alias SonaComms.Org
  alias SonaComms.Org.{Team, Venue}
  alias SonaComms.Repo

  setup %{conn: conn} do
    demo = demo_org_fixture()
    Map.put(demo, :conn, log_in_user(conn, demo.alice))
  end

  test "admin sees #venues with their teams and people counts", %{
    conn: conn,
    london: london,
    bristol: bristol,
    kitchen: kitchen,
    foh: foh
  } do
    {:ok, lv, _html} = live(conn, ~p"/org")

    assert has_element?(lv, "#venues")
    assert has_element?(lv, "#venues-#{london.id}", "London")
    assert has_element?(lv, "#venues-#{bristol.id}", "Bristol")
    # Alice (venue-level) and Bob (Kitchen)
    assert has_element?(lv, "#venues-#{london.id}", "2 people")
    assert has_element?(lv, "#teams-#{kitchen.id}", "1 person")
    assert has_element?(lv, "#teams-#{foh.id}", "1 person")
    assert has_element?(lv, "#new-team-#{london.id}")
  end

  test "#venue-form creates a venue, its conversation and Alice's membership", %{
    conn: conn,
    org: org,
    alice: alice
  } do
    {:ok, lv, _html} = live(conn, ~p"/org")

    lv |> element("#new-venue-button") |> render_click()
    assert_patch(lv, ~p"/org/venues/new")

    lv |> form("#venue-form", venue: %{name: ""}) |> render_change()
    assert has_element?(lv, "#venue-form", "can't be blank")

    lv |> form("#venue-form", venue: %{name: "Leeds"}) |> render_submit()
    assert_patch(lv, ~p"/org")

    leeds = Repo.get_by!(Venue, organisation_id: org.id, name: "Leeds")
    assert has_element?(lv, "#venues-#{leeds.id}", "Leeds")
    assert has_element?(lv, "#venues-#{leeds.id}", "1 person")
    refute has_element?(lv, "#venue-form")

    conversation = Chat.get_derived_conversation(:venue, leeds.id)
    assert conversation.title == "Leeds"

    assert [membership] = Org.list_memberships(Scope.for_system(org.id), venue_id: leeds.id)
    assert membership.user_id == alice.id
    assert membership.role == :admin
    assert is_nil(membership.team_id)

    assert alice
           |> member_scope_fixture()
           |> Chat.list_conversations()
           |> Enum.map(& &1.id)
           |> Enum.member?(conversation.id)
  end

  test "#venue-form shows an error for a duplicate name", %{conn: conn, org: org} do
    {:ok, lv, _html} = live(conn, ~p"/org/venues/new")

    lv |> form("#venue-form", venue: %{name: "London"}) |> render_submit()

    assert has_element?(lv, "#venue-form", "is already a venue")
    assert Repo.aggregate(where(Venue, organisation_id: ^org.id), :count) == 2
  end

  test "#team-form creates a team whose conversation has no participants", %{
    conn: conn,
    bristol: bristol
  } do
    {:ok, lv, _html} = live(conn, ~p"/org")

    lv |> element("#new-team-#{bristol.id}") |> render_click()
    assert_patch(lv, ~p"/org/venues/#{bristol.id}/teams/new")

    lv |> form("#team-form", team: %{name: "Bar"}) |> render_submit()
    assert_patch(lv, ~p"/org")

    team = Repo.get_by!(Team, venue_id: bristol.id, name: "Bar")
    assert has_element?(lv, "#teams-#{team.id}", "0 people")

    conversation = Chat.get_derived_conversation(:team, team.id)
    assert conversation.title == "Bristol · Bar"

    assert Repo.aggregate(where(Participant, conversation_id: ^conversation.id), :count) == 0
  end

  test "#team-form shows an error for a duplicate name", %{conn: conn, bristol: bristol} do
    {:ok, lv, _html} = live(conn, ~p"/org/venues/#{bristol.id}/teams/new")

    lv |> form("#team-form", team: %{name: "FOH"}) |> render_submit()

    assert has_element?(lv, "#team-form", "is already a team at this venue")
  end

  test "a team form for another organisation's venue goes back to /org", %{conn: conn} do
    other_venue = organisation_fixture() |> venue_fixture()

    {:ok, lv, _html} = live(conn, ~p"/org")
    assert {:error, {:live_redirect, _}} = live(conn, ~p"/org/venues/#{other_venue.id}/teams/new")

    render_patch(lv, ~p"/org/venues/#{other_venue.id}/teams/new")
    assert_patch(lv, ~p"/org")
    refute has_element?(lv, "#team-form")
  end

  test "another admin's changes show live", %{conn: conn, org: org, bristol: bristol} do
    {:ok, lv, _html} = live(conn, ~p"/org")

    {:ok, venue} = Org.create_venue(Scope.for_system(org.id), %{name: "Leeds"})
    assert has_element?(lv, "#venues-#{venue.id}", "Leeds")

    team = team_fixture(bristol, %{name: "Bar"})
    assert has_element?(lv, "#teams-#{team.id}", "0 people")

    membership_fixture(SonaComms.AccountsFixtures.user_fixture(), team)
    assert has_element?(lv, "#teams-#{team.id}", "1 person")
  end

  test "Bob and Charlie are redirected away from /org", %{conn: conn, bob: bob, charlie: charlie} do
    for user <- [bob, charlie],
        path <- [~p"/org", ~p"/org/venues/new"] do
      assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in_user(user) |> live(path)
    end
  end
end
