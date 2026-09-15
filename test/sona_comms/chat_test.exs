defmodule SonaComms.ChatTest do
  use SonaComms.DataCase, async: true

  import SonaComms.AccountsFixtures
  import SonaComms.ChatFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Chat
  alias SonaComms.Chat.{Conversation, Participant}

  setup do
    demo = demo_org_fixture()

    Map.merge(demo, %{
      alice_scope: member_scope_fixture(demo.alice),
      bob_scope: member_scope_fixture(demo.bob),
      charlie_scope: member_scope_fixture(demo.charlie)
    })
  end

  defp titles(scope), do: Enum.map(Chat.list_conversations(scope), & &1.display_title)

  defp unread(scope, conversation) do
    {:ok, conversation} = Chat.get_conversation(scope, conversation.id)
    conversation.unread_count
  end

  describe "list_conversations/1" do
    test "orders by kind, then recency, with display titles", %{
      alice: alice,
      alice_scope: alice_scope,
      bob_scope: bob_scope,
      charlie: charlie,
      conversations: c
    } do
      assert titles(alice_scope) == ["Sona Hospitality Group", "Bristol", "London"]

      message_fixture(alice_scope, c.london)
      assert titles(alice_scope) == ["Sona Hospitality Group", "London", "Bristol"]

      dm_fixture(alice_scope, member_scope_fixture(charlie).user)
      dm_fixture(bob_scope, alice)
      group_fixture(bob_scope, [alice], title: "Saturday wedding crew")

      assert titles(bob_scope) == [
               "Sona Hospitality Group",
               "London",
               "London · Kitchen",
               "Saturday wedding crew",
               "Alice"
             ]

      assert [_, _, %Conversation{kind: :team, title: "London · Kitchen"}, _, dm] =
               Chat.list_conversations(bob_scope)

      assert %Conversation{kind: :dm, title: nil, display_title: "Alice"} = dm
    end

    test "returns active participations only", %{
      bob_scope: bob_scope,
      charlie: charlie
    } do
      group = group_fixture(bob_scope, [charlie], title: "Crew")
      assert "Crew" in titles(bob_scope)

      assert :ok = Chat.leave_group(bob_scope, group.id)
      refute "Crew" in titles(bob_scope)
    end
  end

  describe "unread counts" do
    test "count others' messages, ignore your own and reset on mark_read/2", %{
      alice_scope: alice_scope,
      bob_scope: bob_scope,
      conversations: c
    } do
      assert unread(bob_scope, c.org) == 0

      message_fixture(alice_scope, c.org)
      message_fixture(alice_scope, c.org)
      message_fixture(bob_scope, c.org)

      assert unread(bob_scope, c.org) == 2
      assert unread(alice_scope, c.org) == 1

      Chat.subscribe_user(bob_scope)
      assert :ok = Chat.mark_read(bob_scope, c.org.id)
      org_id = c.org.id
      assert_receive {:conversation_read, ^org_id}

      assert unread(bob_scope, c.org) == 0
      assert unread(alice_scope, c.org) == 1
    end

    test "list_conversations/1 sets unread_count", %{
      alice_scope: alice_scope,
      bob_scope: bob_scope,
      conversations: c
    } do
      message_fixture(alice_scope, c.london)

      counts = Map.new(Chat.list_conversations(bob_scope), &{&1.id, &1.unread_count})
      assert counts == %{c.org.id => 0, c.london.id => 1, c.kitchen.id => 0}
    end
  end

  describe "access" do
    test "non-participants and leavers get :not_found", %{
      bob_scope: bob_scope,
      charlie: charlie,
      charlie_scope: charlie_scope,
      conversations: c
    } do
      kitchen_message = message_fixture(bob_scope, c.kitchen)

      group = group_fixture(charlie_scope, [member_scope_fixture(charlie).user, bob_scope.user])
      group_message = message_fixture(bob_scope, group)
      assert :ok = Chat.leave_group(bob_scope, group.id)

      for {scope, conversation, message} <- [
            {charlie_scope, c.kitchen, kitchen_message},
            {bob_scope, group, group_message}
          ] do
        assert {:error, :not_found} = Chat.get_conversation(scope, conversation.id)
        assert {:error, :not_found} = Chat.list_messages(scope, conversation.id)
        assert {:error, :not_found} = Chat.list_participants(scope, conversation.id)
        assert {:error, :not_found} = Chat.get_message(scope, message.id)
        assert {:error, :not_found} = Chat.post_message(scope, conversation.id, %{body: "hi"})
        assert {:error, :not_found} = Chat.mark_read(scope, conversation.id)
        assert {:error, :not_found} = Chat.subscribe_conversation(scope, conversation.id)
      end

      assert {:error, :not_found} = Chat.get_conversation(bob_scope, "not-an-id")
    end

    test "subscribe_conversation/2 subscribes participants", %{
      bob_scope: bob_scope,
      conversations: c
    } do
      assert :ok = Chat.subscribe_conversation(bob_scope, c.kitchen.id)
      {:ok, message} = Chat.post_message(bob_scope, c.kitchen.id, %{body: "hi"})
      assert_receive {:message_created, _, message_id}
      assert message_id == message.id
    end

    test "list_participants/2 lists active participants by name", %{
      alice: alice,
      bob: bob,
      bob_scope: bob_scope,
      conversations: c
    } do
      assert {:ok, users} = Chat.list_participants(bob_scope, c.london.id)
      assert Enum.map(users, & &1.id) == [alice.id, bob.id]
    end
  end

  describe "messages" do
    test "list_messages/3 honours limit: and before:, oldest first", %{
      bob_scope: bob_scope,
      conversations: c
    } do
      [first, second, third] = for _ <- 1..3, do: message_fixture(bob_scope, c.kitchen)

      assert {:ok, messages} = Chat.list_messages(bob_scope, c.kitchen.id)
      assert Enum.map(messages, & &1.id) == [first.id, second.id, third.id]
      assert hd(messages).sender.id == bob_scope.user.id

      assert {:ok, messages} = Chat.list_messages(bob_scope, c.kitchen.id, limit: 2)
      assert Enum.map(messages, & &1.id) == [second.id, third.id]

      assert {:ok, messages} =
               Chat.list_messages(bob_scope, c.kitchen.id, before: third.inserted_at)

      assert Enum.map(messages, & &1.id) == [first.id, second.id]
    end

    test "post_message/3 broadcasts {:message_created, conversation_id, message_id}", %{
      alice_scope: alice_scope,
      bob_scope: bob_scope,
      conversations: c
    } do
      assert :ok = Chat.subscribe_conversation(alice_scope, c.org.id)

      assert {:ok, message} = Chat.post_message(bob_scope, c.org.id, %{"body" => "Morning!"})
      assert message.kind == :text
      assert message.sender.id == bob_scope.user.id

      org_id = c.org.id
      message_id = message.id
      assert_receive {:message_created, ^org_id, ^message_id}

      assert Repo.get!(Conversation, org_id).last_message_at == message.inserted_at
      assert {:ok, %{body: "Morning!"}} = Chat.get_message(alice_scope, message_id)
    end

    test "post_message/3 validates the body", %{bob_scope: bob_scope, conversations: c} do
      assert {:error, changeset} = Chat.post_message(bob_scope, c.org.id, %{"body" => "  "})
      assert "can't be blank" in errors_on(changeset).body

      assert {:error, changeset} =
               Chat.post_message(bob_scope, c.org.id, %{"body" => String.duplicate("a", 4001)})

      assert "should be at most 4000 character(s)" in errors_on(changeset).body
    end
  end

  describe "DMs and groups" do
    test "start_dm/2 is idempotent in either direction", %{
      bob: bob,
      bob_scope: bob_scope,
      charlie: charlie,
      charlie_scope: charlie_scope
    } do
      assert {:ok, dm} = Chat.start_dm(bob_scope, charlie.id)
      assert %Conversation{kind: :dm, display_title: "Charlie"} = dm

      assert {:ok, again} = Chat.start_dm(bob_scope, to_string(charlie.id))
      assert {:ok, reverse} = Chat.start_dm(charlie_scope, bob.id)
      assert again.id == dm.id
      assert reverse.id == dm.id
      assert reverse.display_title == "Bob"

      assert Repo.aggregate(
               from(p in Participant, where: p.conversation_id == ^dm.id),
               :count
             ) == 2
    end

    test "start_dm/2 rejects self and non-members", %{
      bob: bob,
      bob_scope: bob_scope
    } do
      assert {:error, :not_found} = Chat.start_dm(bob_scope, bob.id)
      assert {:error, :not_found} = Chat.start_dm(bob_scope, user_fixture().id)
      assert {:error, :not_found} = Chat.start_dm(bob_scope, "nope")

      stranger = user_fixture()
      membership_fixture(stranger, venue_fixture(organisation_fixture()))
      assert {:error, :not_found} = Chat.start_dm(bob_scope, stranger.id)
    end

    test "create_group/2 adds the creator and members", %{
      bob: bob,
      bob_scope: bob_scope,
      charlie: charlie
    } do
      assert {:ok, group} =
               Chat.create_group(bob_scope, %{
                 "title" => "Saturday wedding crew",
                 "user_ids" => [to_string(charlie.id), to_string(bob.id)]
               })

      assert %Conversation{kind: :group, title: "Saturday wedding crew"} = group
      assert group.created_by_id == bob.id

      assert {:ok, users} = Chat.list_participants(bob_scope, group.id)
      assert Enum.map(users, & &1.id) == [bob.id, charlie.id]
    end

    test "create_group/2 validates its members", %{bob: bob, bob_scope: bob_scope} do
      stranger = user_fixture()

      assert {:error, changeset} =
               Chat.create_group(bob_scope, %{"title" => "Crew", "user_ids" => [stranger.id]})

      assert "must all be in your organisation" in errors_on(changeset).user_ids

      assert {:error, changeset} =
               Chat.create_group(bob_scope, %{"title" => "Crew", "user_ids" => [bob.id]})

      assert "pick at least one person" in errors_on(changeset).user_ids

      assert {:error, changeset} = Chat.create_group(bob_scope, %{"title" => ""})
      assert "can't be blank" in errors_on(changeset).title
    end

    test "leave_group/2 works for groups only", %{
      bob_scope: bob_scope,
      charlie: charlie,
      conversations: c
    } do
      group = group_fixture(bob_scope, [charlie])
      dm = dm_fixture(bob_scope, charlie)

      assert {:error, :not_leavable} = Chat.leave_group(bob_scope, c.kitchen.id)
      assert {:error, :not_leavable} = Chat.leave_group(bob_scope, c.org.id)
      assert {:error, :not_leavable} = Chat.leave_group(bob_scope, dm.id)

      assert :ok = Chat.leave_group(bob_scope, group.id)
      assert {:error, :not_found} = Chat.leave_group(bob_scope, group.id)
    end
  end

  describe "sync_participants/2" do
    test "raises for :dm and :group", %{bob_scope: bob_scope, charlie: charlie} do
      dm = dm_fixture(bob_scope, charlie)
      group = group_fixture(bob_scope, [charlie])

      assert_raise ArgumentError, fn -> Chat.sync_participants(dm, %{}) end
      assert_raise ArgumentError, fn -> Chat.sync_participants(group, %{}) end
    end
  end
end
