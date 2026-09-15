defmodule SonaComms.OrgFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `SonaComms.Org` context.
  """

  import SonaComms.AccountsFixtures

  alias SonaComms.Accounts.{Scope, User}
  alias SonaComms.Chat
  alias SonaComms.Org
  alias SonaComms.Org.{Team, Venue}
  alias SonaComms.Repo

  def organisation_fixture(attrs \\ %{}) do
    {:ok, organisation} =
      attrs
      |> Enum.into(%{name: "Organisation #{System.unique_integer([:positive])}"})
      |> Org.create_organisation()

    organisation
  end

  def venue_fixture(organisation, attrs \\ %{}) do
    {:ok, venue} =
      Org.create_venue(
        Scope.for_system(organisation.id),
        Enum.into(attrs, %{name: "Venue #{System.unique_integer([:positive])}"})
      )

    venue
  end

  def team_fixture(%Venue{} = venue, attrs \\ %{}) do
    {:ok, team} =
      Org.create_team(
        Scope.for_system(venue.organisation_id),
        venue.id,
        Enum.into(attrs, %{name: "Team #{System.unique_integer([:positive])}"})
      )

    team
  end

  @doc """
  Gives `user` a venue-level membership (`%Venue{}`) or a team membership
  (`%Team{}`). Accepts `role:`, defaulting to `:staff`.
  """
  def membership_fixture(user, venue_or_team, attrs \\ %{})

  def membership_fixture(%User{} = user, %Team{} = team, attrs) do
    create_membership(user, Repo.get!(Venue, team.venue_id), team, attrs)
  end

  def membership_fixture(%User{} = user, %Venue{} = venue, attrs) do
    create_membership(user, venue, nil, attrs)
  end

  defp create_membership(user, venue, team, attrs) do
    attrs = Enum.into(attrs, %{role: :staff})

    {:ok, membership} =
      Org.create_membership(Scope.for_system(venue.organisation_id), %{
        email: user.email,
        venue_id: venue.id,
        team_id: team && team.id,
        role: attrs.role
      })

    membership
  end

  @doc """
  A member scope for `user`, as `SonaCommsWeb.OrgAuth` builds it.
  """
  def member_scope_fixture(%User{} = user) do
    {:ok, scope} = Org.put_member_scope(Scope.for_user(user))
    scope
  end

  @doc """
  The demo organisation from PRODUCT.md:

    * Alice: venue-level admin at London and Bristol
    * Bob: manager on London · Kitchen
    * Charlie: staff on Bristol · FOH
  """
  def demo_org_fixture do
    org = organisation_fixture(%{name: "Sona Hospitality Group"})
    london = venue_fixture(org, %{name: "London"})
    bristol = venue_fixture(org, %{name: "Bristol"})
    kitchen = team_fixture(london, %{name: "Kitchen"})
    foh = team_fixture(bristol, %{name: "FOH"})

    alice = user_fixture(%{name: "Alice"})
    bob = user_fixture(%{name: "Bob"})
    charlie = user_fixture(%{name: "Charlie"})

    membership_fixture(alice, london, role: :admin)
    membership_fixture(alice, bristol, role: :admin)
    membership_fixture(bob, kitchen, role: :manager)
    membership_fixture(charlie, foh)

    %{
      org: org,
      london: london,
      bristol: bristol,
      kitchen: kitchen,
      foh: foh,
      alice: alice,
      bob: bob,
      charlie: charlie,
      conversations: %{
        org: Chat.get_derived_conversation(:org, org.id),
        london: Chat.get_derived_conversation(:venue, london.id),
        kitchen: Chat.get_derived_conversation(:team, kitchen.id),
        bristol: Chat.get_derived_conversation(:venue, bristol.id),
        foh: Chat.get_derived_conversation(:team, foh.id)
      }
    }
  end
end
