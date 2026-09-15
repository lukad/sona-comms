defmodule SonaComms.OrgTest do
  use SonaComms.DataCase, async: true

  import SonaComms.AccountsFixtures
  import SonaComms.ChatFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts
  alias SonaComms.Accounts.Scope
  alias SonaComms.Chat
  alias SonaComms.Chat.{Conversation, Participant, Receipt}
  alias SonaComms.Org
  alias SonaComms.Org.{Membership, Venue}

  # active participants of a conversation: %{user_id => can_announce}
  defp participants(%Conversation{id: id}) do
    Repo.all(
      from p in Participant,
        where: p.conversation_id == ^id and is_nil(p.left_at),
        select: {p.user_id, p.can_announce}
    )
    |> Map.new()
  end

  defp participant(%Conversation{id: id}, user) do
    Repo.get_by!(Participant, conversation_id: id, user_id: user.id)
  end

  defp membership_of(user) do
    Repo.one!(from m in Membership, where: m.user_id == ^user.id and is_nil(m.ended_at))
  end

  # Forwards everything published on "user:<id>" to the test as
  # {:user, id, message}, so several users' topics can be told apart.
  defp listen(user) do
    test = self()

    pid =
      spawn_link(fn ->
        Chat.subscribe_user(Scope.for_user(user))
        send(test, {:listening, self()})
        forward(test, user.id)
      end)

    assert_receive {:listening, ^pid}
    :ok
  end

  defp forward(test, user_id) do
    receive do
      message -> send(test, {:user, user_id, message})
    end

    forward(test, user_id)
  end

  setup do
    demo = demo_org_fixture()
    Map.put(demo, :system, Scope.for_system(demo.org.id))
  end

  describe "structure" do
    test "create_organisation/1 creates exactly one org conversation" do
      org = organisation_fixture(%{name: "Acme Hospitality"})

      assert [%Conversation{kind: :org, title: "Acme Hospitality"} = conversation] =
               Repo.all_by(Conversation, organisation_id: org.id)

      assert participants(conversation) == %{}
    end

    test "create_venue/2 creates one conversation", %{system: system, org: org} do
      assert {:ok, venue} = Org.create_venue(system, %{name: "Leeds"})
      assert venue.organisation_id == org.id

      assert [%Conversation{kind: :venue, title: "Leeds"} = conversation] =
               Repo.all_by(Conversation, venue_id: venue.id)

      assert participants(conversation) == %{}
    end

    test "a user-scoped create_venue/2 adds the creator as a venue admin", %{alice: alice} do
      assert {:ok, venue} = Org.create_venue(member_scope_fixture(alice), %{name: "Leeds"})

      assert [%Membership{role: :admin, team_id: nil}] =
               Repo.all_by(Membership, user_id: alice.id, venue_id: venue.id)

      assert participants(Chat.get_derived_conversation(:venue, venue.id)) == %{alice.id => true}
    end

    test "create_venue/2 rejects a duplicate name", %{system: system} do
      assert {:error, changeset} = Org.create_venue(system, %{name: "London"})
      assert "is already a venue" in errors_on(changeset).name
    end

    test "create_team/3 creates a \"Venue · Team\" conversation with no participants", %{
      system: system,
      london: london
    } do
      assert {:ok, team} = Org.create_team(system, london.id, %{name: "Bar"})

      conversation = Chat.get_derived_conversation(:team, team.id)
      assert conversation.title == "London · Bar"
      assert participants(conversation) == %{}
    end

    test "create_team/3 returns :not_found for another organisation's venue", %{
      london: london,
      alice: alice
    } do
      other = organisation_fixture()

      assert {:error, :not_found} =
               Org.create_team(Scope.for_system(other.id), london.id, %{name: "Bar"})

      other_venue = venue_fixture(other)

      assert {:error, :not_found} =
               Org.create_team(member_scope_fixture(alice), other_venue.id, %{name: "Bar"})
    end

    test "list_venues/1 preloads teams with member counts", %{alice: alice} do
      assert [bristol, london] = Org.list_venues(member_scope_fixture(alice))
      assert bristol.name == "Bristol"
      assert [%{name: "FOH", member_count: 1}] = bristol.teams
      assert [%{name: "Kitchen", member_count: 1}] = london.teams
    end
  end

  describe "authorization" do
    test "a non-admin scope gets :unauthorized on every structure and membership write", %{
      bob: bob,
      charlie: charlie,
      london: london
    } do
      charlie_membership = membership_of(charlie)

      for scope <- [member_scope_fixture(bob), Scope.for_user(bob)] do
        assert {:error, :unauthorized} = Org.create_venue(scope, %{name: "Leeds"})
        assert {:error, :unauthorized} = Org.create_team(scope, london.id, %{name: "Bar"})

        assert {:error, :unauthorized} =
                 Org.create_membership(scope, %{email: "new@example.com", venue_id: london.id})

        assert {:error, :unauthorized} = Org.end_membership(scope, charlie_membership.id)
        assert {:error, :unauthorized} = Org.list_venues(scope)
        assert {:error, :unauthorized} = Org.list_memberships(scope)
      end
    end

    test "an ended admin is refused even though the scope still says admin?", %{
      system: system,
      alice: alice,
      charlie: charlie,
      kitchen: kitchen
    } do
      alice_scope = member_scope_fixture(alice)
      assert alice_scope.admin?

      # keep Alice in the organisation, as staff only
      membership_fixture(alice, kitchen)

      for membership <- Repo.all_by(Membership, user_id: alice.id, role: :admin) do
        assert {:ok, _} = Org.end_membership(system, membership.id)
      end

      assert Scope.admin?(alice_scope)
      refute Org.admin?(alice_scope)
      assert {:error, :unauthorized} = Org.create_venue(alice_scope, %{name: "Leeds"})
      assert {:error, :unauthorized} = Org.end_membership(alice_scope, membership_of(charlie).id)
    end
  end

  describe "create_membership/2" do
    test "with a team adds org, venue and team participation", %{
      system: system,
      london: london,
      kitchen: kitchen,
      conversations: c
    } do
      user = user_fixture()

      assert {:ok, membership} =
               Org.create_membership(system, %{
                 email: user.email,
                 venue_id: london.id,
                 team_id: kitchen.id
               })

      assert membership.user.id == user.id
      assert membership.role == :staff

      assert participants(c.org)[user.id] == false
      assert participants(c.london)[user.id] == false
      assert participants(c.kitchen)[user.id] == false
      refute Map.has_key?(participants(c.bristol), user.id)
    end

    test "without a team adds org and venue participation only", %{
      system: system,
      london: london,
      conversations: c
    } do
      user = user_fixture()
      assert {:ok, _} = Org.create_membership(system, %{email: user.email, venue_id: london.id})

      assert Map.has_key?(participants(c.org), user.id)
      assert Map.has_key?(participants(c.london), user.id)
      refute Map.has_key?(participants(c.kitchen), user.id)
    end

    test "finds existing users by email and creates new ones", %{
      system: system,
      london: london
    } do
      existing = user_fixture()

      assert {:ok, membership} =
               Org.create_membership(system, %{email: existing.email, venue_id: london.id})

      assert membership.user_id == existing.id

      assert {:ok, membership} =
               Org.create_membership(system, %{
                 "email" => "dana@example.com",
                 "name" => "Dana",
                 "venue_id" => to_string(london.id),
                 "role" => "manager"
               })

      assert %{email: "dana@example.com", name: "Dana"} = membership.user
      assert membership.role == :manager
      assert Accounts.get_user_by_email("dana@example.com").id == membership.user_id
    end

    test "returns changeset errors for invalid placements", %{
      system: system,
      bob: bob,
      london: london,
      kitchen: kitchen,
      foh: foh
    } do
      assert {:error, changeset} =
               Org.create_membership(system, %{
                 email: bob.email,
                 venue_id: london.id,
                 team_id: kitchen.id
               })

      assert "is already on this venue or team" in errors_on(changeset).email

      assert {:error, changeset} =
               Org.create_membership(system, %{
                 email: "erin@example.com",
                 venue_id: london.id,
                 team_id: foh.id
               })

      assert "is not part of this venue" in errors_on(changeset).team_id
      refute Accounts.get_user_by_email("erin@example.com")

      other_venue = venue_fixture(organisation_fixture())

      assert {:error, changeset} =
               Org.create_membership(system, %{
                 email: "erin@example.com",
                 venue_id: other_venue.id
               })

      assert "is not part of this organisation" in errors_on(changeset).venue_id

      assert {:error, changeset} = Org.create_membership(system, %{venue_id: london.id})
      assert "can't be blank" in errors_on(changeset).email
    end

    test "rejects a user who is active in another organisation", %{
      system: system,
      london: london
    } do
      stranger = user_fixture()
      membership_fixture(stranger, venue_fixture(organisation_fixture()))

      assert {:error, changeset} =
               Org.create_membership(system, %{email: stranger.email, venue_id: london.id})

      assert "already works for another organisation" in errors_on(changeset).email
    end

    test "broadcasts {:conversation_joined, id} to the new member", %{
      system: system,
      london: london,
      kitchen: kitchen,
      bob: bob,
      conversations: c
    } do
      user = user_fixture()
      listen(user)
      listen(bob)

      membership_fixture(user, kitchen)

      for conversation <- [c.org, c.london, c.kitchen] do
        assert_receive {:user, user_id, {:conversation_joined, conversation_id}}
        assert {user_id, conversation_id} == {user.id, conversation.id}
      end

      bob_id = bob.id
      refute_receive {:user, ^bob_id, _}

      assert {:ok, _} = Org.end_membership(system, membership_of(user).id)

      for conversation <- [c.org, c.london, c.kitchen] do
        conversation_id = conversation.id
        assert_receive {:user, _, {:conversation_left, ^conversation_id}}
      end

      assert london.id
    end
  end

  describe "can_announce" do
    test "the role matrix holds for Alice, Bob and Charlie", %{
      alice: alice,
      bob: bob,
      charlie: charlie,
      conversations: c
    } do
      assert participants(c.org) == %{alice.id => true, bob.id => false, charlie.id => false}
      assert participants(c.london) == %{alice.id => true, bob.id => false}
      assert participants(c.kitchen) == %{bob.id => true}
      assert participants(c.bristol) == %{alice.id => true, charlie.id => false}
      assert participants(c.foh) == %{charlie.id => false}

      flags = fn user ->
        for c <- Chat.list_conversations(Scope.for_user(user)), do: {c.title, c.can_announce}
      end

      assert flags.(alice) == [
               {"Sona Hospitality Group", true},
               {"Bristol", true},
               {"London", true}
             ]

      assert flags.(bob) == [
               {"Sona Hospitality Group", false},
               {"London", false},
               {"London · Kitchen", true}
             ]

      assert flags.(charlie) == [
               {"Sona Hospitality Group", false},
               {"Bristol", false},
               {"Bristol · FOH", false}
             ]
    end

    test "a venue-level manager announces in their venue; a team-level admin everywhere", %{
      london: london,
      foh: foh,
      conversations: c
    } do
      venue_manager = user_fixture()
      membership_fixture(venue_manager, london, role: :manager)

      team_admin = user_fixture()
      membership_fixture(team_admin, foh, role: :admin)

      assert participants(c.org)[venue_manager.id] == false
      assert participants(c.london)[venue_manager.id] == true

      assert participants(c.org)[team_admin.id] == true
      assert participants(c.bristol)[team_admin.id] == true
      assert participants(c.foh)[team_admin.id] == true
    end

    test "a role change flips the flag", %{
      system: system,
      charlie: charlie,
      foh: foh,
      bristol: bristol,
      conversations: c
    } do
      # a venue-level membership keeps Charlie in the organisation meanwhile
      membership_fixture(charlie, bristol)

      staff = Repo.get_by!(Membership, user_id: charlie.id, team_id: foh.id)
      assert {:ok, _} = Org.end_membership(system, staff.id)
      membership_fixture(charlie, foh, role: :manager)

      assert participants(c.foh) == %{charlie.id => true}
      assert participants(c.bristol)[charlie.id] == false
    end
  end

  describe "end_membership/2" do
    test "ending one of two memberships removes only the conversation no longer backed", %{
      system: system,
      charlie: charlie,
      london: london,
      conversations: c
    } do
      membership_fixture(charlie, london)
      foh_membership = Repo.get_by!(Membership, user_id: charlie.id, venue_id: c.bristol.venue_id)

      assert {:ok, ended} = Org.end_membership(system, foh_membership.id)
      assert ended.ended_at

      assert Map.has_key?(participants(c.org), charlie.id)
      assert Map.has_key?(participants(c.london), charlie.id)
      refute Map.has_key?(participants(c.bristol), charlie.id)
      refute Map.has_key?(participants(c.foh), charlie.id)
    end

    test "ending the last one sets left_at in every derived, DM and group conversation", %{
      system: system,
      alice: alice,
      bob: bob,
      charlie: charlie,
      conversations: c
    } do
      charlie_scope = member_scope_fixture(charlie)
      dm = dm_fixture(charlie_scope, bob)
      group = group_fixture(charlie_scope, [alice, bob])

      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)

      for conversation <- [c.org, c.bristol, c.foh, dm, group] do
        assert participant(conversation, charlie).left_at
      end

      assert Chat.list_conversations(Scope.for_user(charlie)) == []
      refute participant(dm, bob).left_at
      refute participant(group, alice).left_at
    end

    test "deletes pending receipts and keeps acknowledged ones", %{
      system: system,
      alice: alice,
      bob: bob,
      charlie: charlie,
      conversations: c
    } do
      alice_scope = member_scope_fixture(alice)
      first = message_fixture(alice_scope, c.org, kind: :announcement)
      second = message_fixture(alice_scope, c.org, kind: :announcement)

      pending = receipt_fixture(first, charlie)
      acknowledged = receipt_fixture(second, charlie, acknowledged_at: DateTime.utc_now())
      bobs = receipt_fixture(first, bob)

      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)

      refute Repo.get(Receipt, pending.id)
      assert Repo.get(Receipt, acknowledged.id)
      assert Repo.get(Receipt, bobs.id)
    end

    test "broadcasts {:access_revoked, org_id} before {:conversation_left, _}", %{
      system: system,
      org: org,
      charlie: charlie,
      conversations: c
    } do
      charlie_scope = Scope.for_user(charlie)
      Org.subscribe_access(charlie_scope)
      Chat.subscribe_user(charlie_scope)

      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)

      # the mailbox also holds fixture emails; receive/1 keeps mailbox order among matches
      events =
        for _ <- 1..4 do
          receive do
            {:access_revoked, _} = event -> event
            {:conversation_left, _} = event -> event
          after
            1000 -> flunk("expected an access or conversation event")
          end
        end

      assert events == [
               {:access_revoked, org.id},
               {:conversation_left, c.org.id},
               {:conversation_left, c.bristol.id},
               {:conversation_left, c.foh.id}
             ]
    end

    test "broadcasts {:org_changed, :membership}", %{
      system: system,
      alice: alice,
      charlie: charlie
    } do
      Org.subscribe_org(member_scope_fixture(alice))
      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)
      assert_receive {:org_changed, :membership}
    end

    test "returns errors for other organisations, ended and own memberships", %{
      system: system,
      alice: alice,
      charlie: charlie,
      london: london
    } do
      foreign = membership_fixture(user_fixture(), venue_fixture(organisation_fixture()))
      assert {:error, :not_found} = Org.end_membership(system, foreign.id)
      assert {:error, :not_found} = Org.end_membership(system, "nope")

      membership = membership_of(charlie)
      assert {:ok, _} = Org.end_membership(system, membership.id)
      assert {:error, :already_ended} = Org.end_membership(system, membership.id)

      own = Repo.get_by!(Membership, user_id: alice.id, venue_id: london.id)

      assert {:error, :cannot_end_own_membership} =
               Org.end_membership(member_scope_fixture(alice), own.id)
    end
  end

  describe "afterwards" do
    test "put_member_scope/1 sets organisation_id and admin?, or returns :no_access", %{
      system: system,
      org: org,
      alice: alice,
      bob: bob,
      charlie: charlie
    } do
      assert {:ok, %Scope{organisation_id: org_id, admin?: true}} =
               Org.put_member_scope(Scope.for_user(alice))

      assert org_id == org.id

      assert {:ok, %Scope{organisation_id: ^org_id, admin?: false}} =
               Org.put_member_scope(Scope.for_user(bob))

      assert {:error, :no_access} = Org.put_member_scope(Scope.for_user(user_fixture()))

      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)
      assert {:error, :no_access} = Org.put_member_scope(Scope.for_user(charlie))
    end

    test "a rehire re-activates the same participant rows", %{
      system: system,
      charlie: charlie,
      foh: foh,
      conversations: c
    } do
      before = participant(c.foh, charlie)
      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)
      assert participant(c.foh, charlie).left_at

      membership_fixture(charlie, foh)

      rehired = participant(c.foh, charlie)
      assert rehired.id == before.id
      refute rehired.left_at
      assert DateTime.after?(rehired.last_read_at, before.last_read_at)
      refute participant(c.org, charlie).left_at
    end

    test "create_group, start_dm and leave_group broadcast to the right user topics", %{
      alice: alice,
      bob: bob,
      charlie: charlie
    } do
      listen(alice)
      listen(bob)
      listen(charlie)
      {alice_id, bob_id, charlie_id} = {alice.id, bob.id, charlie.id}

      charlie_scope = member_scope_fixture(charlie)

      dm = dm_fixture(charlie_scope, bob)
      dm_id = dm.id
      assert_receive {:user, ^bob_id, {:conversation_joined, ^dm_id}}
      refute_receive {:user, ^charlie_id, {:conversation_joined, ^dm_id}}

      # finding the existing DM broadcasts nothing
      assert dm_fixture(member_scope_fixture(bob), charlie).id == dm_id
      refute_receive {:user, _, {:conversation_joined, ^dm_id}}

      group = group_fixture(charlie_scope, [bob])
      group_id = group.id
      assert_receive {:user, ^bob_id, {:conversation_joined, ^group_id}}
      assert_receive {:user, ^charlie_id, {:conversation_joined, ^group_id}}
      refute_receive {:user, ^alice_id, _}

      assert :ok = Chat.leave_group(member_scope_fixture(bob), group_id)
      assert_receive {:user, ^bob_id, {:conversation_left, ^group_id}}
      refute_receive {:user, ^charlie_id, {:conversation_left, ^group_id}}
    end
  end

  describe "queries" do
    test "list_colleagues/1 excludes self and ended members", %{
      system: system,
      alice: alice,
      bob: bob,
      charlie: charlie
    } do
      alice_scope = member_scope_fixture(alice)
      assert Enum.map(Org.list_colleagues(alice_scope), & &1.id) == [bob.id, charlie.id]

      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)
      assert Enum.map(Org.list_colleagues(alice_scope), & &1.id) == [bob.id]
    end

    test "list_memberships/2 honours venue_id: and include_ended:", %{
      system: system,
      alice: alice,
      charlie: charlie,
      bristol: bristol
    } do
      scope = member_scope_fixture(alice)
      assert length(Org.list_memberships(scope)) == 4

      names = fn memberships -> Enum.map(memberships, & &1.user.name) end

      bristol_memberships = Org.list_memberships(scope, venue_id: bristol.id)
      assert names.(bristol_memberships) == ["Alice", "Charlie"]
      assert [%{venue: %Venue{name: "Bristol"}, team: nil} | _] = bristol_memberships

      assert {:ok, _} = Org.end_membership(system, membership_of(charlie).id)

      assert names.(Org.list_memberships(scope, venue_id: bristol.id)) == ["Alice"]

      assert names.(Org.list_memberships(scope, venue_id: bristol.id, include_ended: true)) ==
               ["Alice", "Charlie"]
    end

    test "directory/0 includes users without an active membership", %{bob: bob} do
      loner = user_fixture()
      entries = Map.new(Org.directory(), &{&1.user.id, &1.memberships})

      assert [%Membership{role: :manager}] = entries[bob.id]
      assert entries[loner.id] == []
    end
  end
end
