defmodule SonaCommsWeb.OrgLive.MembersTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.AccountsFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts
  alias SonaComms.Accounts.Scope
  alias SonaComms.Chat
  alias SonaComms.Org

  setup %{conn: conn} do
    demo = demo_org_fixture()

    memberships =
      Scope.for_system(demo.org.id)
      |> Org.list_memberships()
      |> Map.new(&{{&1.user_id, &1.venue_id}, &1})

    demo
    |> Map.put(:conn, log_in_user(conn, demo.alice))
    |> Map.put(:memberships, memberships)
  end

  defp membership(%{memberships: memberships}, user, venue),
    do: Map.fetch!(memberships, {user.id, venue.id})

  test "lists everyone's venue, team and role", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members")

    bob = membership(ctx, ctx.bob, ctx.london)
    alice = membership(ctx, ctx.alice, ctx.bristol)

    assert has_element?(lv, "#members")
    assert has_element?(lv, "#members-#{bob.id}", "Bob")
    assert has_element?(lv, "#members-#{bob.id}", "London")
    assert has_element?(lv, "#members-#{bob.id}", "Kitchen")
    assert has_element?(lv, "#members-#{bob.id}", "Manager")
    assert has_element?(lv, "#members-#{alice.id}", "Whole venue")
    assert has_element?(lv, "#members-#{alice.id}", "Admin")
    # admins can't remove themselves
    refute has_element?(lv, "#end-membership-#{alice.id}")
  end

  test "#member-venue-filter narrows #members", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members")

    bob = membership(ctx, ctx.bob, ctx.london)
    charlie = membership(ctx, ctx.charlie, ctx.bristol)
    assert has_element?(lv, "#members-#{bob.id}")

    lv |> form("#member-venue-filter", venue_id: ctx.bristol.id) |> render_change()
    assert_patch(lv, ~p"/org/members?venue_id=#{ctx.bristol.id}")

    assert has_element?(lv, "#members-#{charlie.id}")
    refute has_element?(lv, "#members-#{bob.id}")

    lv |> form("#member-venue-filter", venue_id: "") |> render_change()
    assert_patch(lv, ~p"/org/members")
    assert has_element?(lv, "#members-#{bob.id}")
  end

  test "an unknown venue filter shows everyone", ctx do
    other_venue = organisation_fixture() |> venue_fixture()
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members?venue_id=#{other_venue.id}")

    assert has_element?(lv, "#members-#{membership(ctx, ctx.bob, ctx.london).id}")
  end

  test "#membership-form with a new email creates the user, membership and participations",
       ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members?venue_id=#{ctx.bristol.id}")

    lv |> element("#new-membership-button") |> render_click()
    assert_patch(lv, ~p"/org/members/new?venue_id=#{ctx.bristol.id}")

    # the team select offers the chosen venue's teams
    assert has_element?(lv, "#membership_team_id option[value='#{ctx.foh.id}']")
    refute has_element?(lv, "#membership_team_id option[value='#{ctx.kitchen.id}']")
    assert has_element?(lv, "#membership_team_id option[value='']", "No team (whole venue)")

    lv
    |> form("#membership-form", membership: %{venue_id: ctx.london.id})
    |> render_change()

    assert has_element?(lv, "#membership_team_id option[value='#{ctx.kitchen.id}']")
    refute has_element?(lv, "#membership_team_id option[value='#{ctx.foh.id}']")

    lv
    |> form("#membership-form", membership: %{venue_id: ctx.bristol.id})
    |> render_change()

    lv
    |> form("#membership-form",
      membership: %{
        email: "dana@sona.test",
        name: "Dana",
        venue_id: ctx.bristol.id,
        team_id: ctx.foh.id,
        role: "manager"
      }
    )
    |> render_submit()

    assert_patch(lv, ~p"/org/members?venue_id=#{ctx.bristol.id}")

    dana = Accounts.get_user_by_email("dana@sona.test")
    assert dana.name == "Dana"

    assert [membership] =
             Scope.for_system(ctx.org.id)
             |> Org.list_memberships()
             |> Enum.filter(&(&1.user_id == dana.id))

    assert membership.team_id == ctx.foh.id
    assert membership.role == :manager
    assert has_element?(lv, "#members-#{membership.id}", "Dana")

    c = ctx.conversations

    assert dana
           |> member_scope_fixture()
           |> Chat.list_conversations()
           |> Enum.map(& &1.id)
           |> Enum.sort() ==
             Enum.sort([c.org.id, c.bristol.id, c.foh.id])
  end

  test "#membership-form finds an existing user by email", ctx do
    dana = user_fixture(%{name: "Dana"})
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members/new")

    lv
    |> form("#membership-form",
      membership: %{email: dana.email, venue_id: ctx.london.id, role: "staff"}
    )
    |> render_submit()

    assert_patch(lv, ~p"/org/members")

    assert [%{user_id: user_id, team_id: nil}] =
             Org.list_memberships(Scope.for_system(ctx.org.id), venue_id: ctx.london.id)
             |> Enum.filter(&(&1.user_id == dana.id))

    assert user_id == dana.id
  end

  test "changing the venue clears a team from the previous venue", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members/new?venue_id=#{ctx.bristol.id}")

    lv
    |> form("#membership-form", membership: %{venue_id: ctx.bristol.id, team_id: ctx.foh.id})
    |> render_change()

    assert has_element?(lv, "#membership_team_id option[selected][value='#{ctx.foh.id}']")

    lv
    |> form("#membership-form", membership: %{venue_id: ctx.london.id})
    |> render_change(%{membership: %{team_id: ctx.foh.id}})

    refute has_element?(lv, "#membership_team_id option[selected]")
  end

  test "an invalid team or venue combination shows errors", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members/new")

    lv
    |> form("#membership-form",
      membership: %{email: "dana@sona.test", venue_id: ctx.london.id, role: "staff"}
    )
    |> render_submit(%{membership: %{team_id: ctx.foh.id}})

    assert has_element?(lv, "#membership-form", "is not part of this venue")

    other_venue = organisation_fixture() |> venue_fixture()

    lv
    |> form("#membership-form", membership: %{email: "dana@sona.test", role: "staff"})
    |> render_submit(%{membership: %{venue_id: other_venue.id, team_id: ""}})

    assert has_element?(lv, "#membership-form", "is not part of this organisation")

    lv
    |> form("#membership-form", membership: %{venue_id: ctx.london.id})
    |> render_change()

    lv
    |> form("#membership-form",
      membership: %{email: ctx.bob.email, venue_id: ctx.london.id, team_id: ctx.kitchen.id}
    )
    |> render_submit()

    assert has_element?(lv, "#membership-form", "is already on this venue or team")
    assert is_nil(Accounts.get_user_by_email("dana@sona.test"))
  end

  test "#end-membership-<id> asks for confirmation and removes the row", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members?venue_id=#{ctx.bristol.id}")
    charlie = membership(ctx, ctx.charlie, ctx.bristol)

    assert has_element?(lv, "#end-membership-#{charlie.id}", "Remove from Bristol · FOH")

    assert has_element?(
             lv,
             ~s|#end-membership-#{charlie.id}[data-confirm="Charlie will lose access to Bristol · FOH chats. If this is their only venue or team, they lose access to all chats."]|
           )

    lv |> element("#end-membership-#{charlie.id}") |> render_click()

    refute has_element?(lv, "#members-#{charlie.id}")
    assert render(lv) =~ "Charlie removed from Bristol · FOH."
    assert {:error, :no_access} = Org.put_member_scope(Scope.for_user(ctx.charlie))
  end

  test "another admin's changes show live", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/org/members")

    dana = user_fixture(%{name: "Dana"})
    membership = membership_fixture(dana, ctx.kitchen)
    assert has_element?(lv, "#members-#{membership.id}", "Dana")

    {:ok, _} = Org.end_membership(Scope.for_system(ctx.org.id), membership.id)
    refute has_element?(lv, "#members-#{membership.id}")
  end

  test "Bob and Charlie are redirected away from /org/members", ctx do
    for user <- [ctx.bob, ctx.charlie], path <- [~p"/org/members", ~p"/org/members/new"] do
      assert {:error, {:redirect, %{to: "/"}}} = ctx.conn |> log_in_user(user) |> live(path)
    end
  end
end
