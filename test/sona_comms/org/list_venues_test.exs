defmodule SonaComms.Org.ListVenuesTest do
  use SonaComms.DataCase, async: true

  import SonaComms.AccountsFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts.Scope
  alias SonaComms.Org

  setup do
    demo_org_fixture()
  end

  defp venue_named(venues, name), do: Enum.find(venues, &(&1.name == name))

  test "counts distinct active people per venue and per team", %{
    org: org,
    alice: alice,
    kitchen: kitchen
  } do
    # Bob gets a second, venue-level place at London: still one person there
    bob = Enum.find(Org.list_colleagues(member_scope_fixture(alice)), &(&1.name == "Bob"))
    membership_fixture(bob, SonaComms.Repo.get!(Org.Venue, kitchen.venue_id))

    venues = Org.list_venues(Scope.for_system(org.id))
    london = venue_named(venues, "London")
    bristol = venue_named(venues, "Bristol")

    assert london.member_count == 2
    assert bristol.member_count == 2
    assert [%{name: "Kitchen", member_count: 1}] = london.teams
  end

  test "ended memberships and empty venues count zero", %{org: org, charlie: charlie} do
    empty = venue_fixture(org, %{name: "Aardvark"})
    team = team_fixture(empty, %{name: "Bar"})

    [charlie_membership] =
      Org.list_memberships(Scope.for_system(org.id))
      |> Enum.filter(&(&1.user_id == charlie.id))

    {:ok, _} = Org.end_membership(Scope.for_system(org.id), charlie_membership.id)

    venues = Org.list_venues(Scope.for_system(org.id))

    assert %{member_count: 0, teams: [%{id: team_id, member_count: 0}]} =
             venue_named(venues, "Aardvark")

    assert team_id == team.id

    assert %{member_count: 1, teams: [%{name: "FOH", member_count: 0}]} =
             venue_named(venues, "Bristol")
  end

  test "is refused for non-admins", %{bob: bob} do
    assert {:error, :unauthorized} = Org.list_venues(member_scope_fixture(bob))
    assert {:error, :unauthorized} = Org.list_venues(Scope.for_user(user_fixture()))
  end
end
