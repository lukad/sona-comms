defmodule SonaComms.Chat.AnnouncementsTest do
  use SonaComms.DataCase, async: true

  import SonaComms.AccountsFixtures
  import SonaComms.AnnouncementFixtures
  import SonaComms.ChatFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Chat
  alias SonaComms.Chat.{Message, Receipt}
  alias SonaComms.Org
  alias SonaComms.Org.Membership

  setup do
    demo = demo_org_fixture()

    Map.merge(demo, %{
      alice_scope: member_scope_fixture(demo.alice),
      bob_scope: member_scope_fixture(demo.bob),
      charlie_scope: member_scope_fixture(demo.charlie)
    })
  end

  defp receipt_user_ids(message) do
    Repo.all(from r in Receipt, where: r.message_id == ^message.id, select: r.user_id)
  end

  defp pending_acks(scope) do
    Map.new(Chat.list_conversations(scope), &{&1.display_title, &1.pending_ack_count})
  end

  describe "post_announcement/3" do
    test "staff get :unauthorized everywhere", %{charlie_scope: scope, conversations: c} do
      for conversation <- [c.org, c.bristol, c.foh] do
        assert {:error, :unauthorized} =
                 Chat.post_announcement(scope, conversation.id, %{body: "Hi"})
      end
    end

    test "team-level managers get :unauthorized in their venue and org conversations", %{
      bob_scope: scope,
      conversations: c
    } do
      for conversation <- [c.org, c.london] do
        assert {:error, :unauthorized} =
                 Chat.post_announcement(scope, conversation.id, %{body: "Hi"})
      end
    end

    test "DMs and group chats get :unauthorized, even for admins", %{
      alice_scope: alice_scope,
      bob: bob
    } do
      dm = dm_fixture(alice_scope, bob)
      group = group_fixture(alice_scope, [bob])

      for conversation <- [dm, group] do
        assert {:error, :unauthorized} =
                 Chat.post_announcement(alice_scope, conversation.id, %{body: "Hi"})
      end

      assert Repo.aggregate(Message, :count) == 0
    end

    test "non-participants get :not_found", %{charlie_scope: scope, conversations: c} do
      assert {:error, :not_found} = Chat.post_announcement(scope, c.kitchen.id, %{body: "Hi"})
      assert {:error, :not_found} = Chat.post_announcement(scope, "nope", %{body: "Hi"})
    end

    test "Bob can post in London · Kitchen", %{bob: bob, bob_scope: scope, conversations: c} do
      kitchen_hand = user_fixture(%{name: "Dan"})
      membership_fixture(kitchen_hand, team_of(c.kitchen))

      assert {:ok, %Message{kind: :announcement} = message} =
               Chat.post_announcement(scope, c.kitchen.id, %{body: "Deep clean Friday"})

      assert message.sender.id == bob.id
      assert receipt_user_ids(message) == [kitchen_hand.id]
      assert %{ack_count: 0, recipient_count: 1, my_ack: nil} = message
    end

    test "a venue-level manager can post in their venue conversation", %{
      alice: alice,
      bob: bob,
      london: london,
      conversations: c
    } do
      manager = user_fixture(%{name: "Venue manager"})
      membership_fixture(manager, london, role: :manager)
      scope = member_scope_fixture(manager)

      assert {:ok, message} = Chat.post_announcement(scope, c.london.id, %{body: "Fire drill"})
      assert Enum.sort(receipt_user_ids(message)) == Enum.sort([alice.id, bob.id])
      assert {:error, :unauthorized} = Chat.post_announcement(scope, c.org.id, %{body: "Hi"})
    end

    test "validates the body", %{alice_scope: scope, conversations: c} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Chat.post_announcement(scope, c.org.id, %{body: ""})

      assert "can't be blank" in errors_on(changeset).body

      assert {:error, changeset} =
               Chat.post_announcement(scope, c.org.id, %{body: String.duplicate("a", 4001)})

      assert errors_on(changeset).body != []
      assert Repo.aggregate(Receipt, :count) == 0
    end

    test "priority defaults to :mid and must be low, mid or high", %{
      alice_scope: scope,
      conversations: c
    } do
      assert {:ok, %Message{priority: :mid}} =
               Chat.post_announcement(scope, c.org.id, %{body: "Rota is up"})

      for {param, priority} <- [{"low", :low}, {"high", :high}] do
        assert {:ok, %Message{priority: ^priority}} =
                 Chat.post_announcement(scope, c.org.id, %{body: "Hi", priority: param})
      end

      assert {:error, changeset} =
               Chat.post_announcement(scope, c.org.id, %{body: "Hi", priority: "urgent"})

      assert "is invalid" in errors_on(changeset).priority
      assert %Message{priority: nil} = message_fixture(scope, c.org)
    end

    test "Alice's org announcement creates 45 receipts, none for her, and broadcasts",
         %{
           alice: alice,
           alice_scope: scope,
           conversations: c
         } = demo do
      extra_staff_fixture(demo, 43)
      :ok = Chat.subscribe_conversation(scope, c.org.id)

      assert {:ok, message} = Chat.post_announcement(scope, c.org.id, %{body: "Allergens"})

      assert length(receipt_user_ids(message)) == 45
      refute alice.id in receipt_user_ids(message)
      assert %{ack_count: 0, recipient_count: 45, my_ack: nil} = message

      message_id = message.id
      org_id = c.org.id
      assert_receive {:message_created, ^org_id, ^message_id}

      {:ok, conversation} = Chat.get_conversation(scope, c.org.id)
      assert conversation.last_message_at == message.inserted_at
    end
  end

  describe "acknowledge/2" do
    setup %{alice_scope: scope, conversations: c} do
      %{message: announcement_fixture(scope, c.org)}
    end

    test "is idempotent and broadcasts once", %{
      bob_scope: scope,
      conversations: c,
      message: message
    } do
      :ok = Chat.subscribe_conversation(scope, c.org.id)

      {:ok, %Message{my_ack: :pending, my_acknowledged_at: nil}} =
        Chat.get_message(scope, message.id)

      assert {:ok, %Receipt{acknowledged_at: %DateTime{} = at}} =
               Chat.acknowledge(scope, message.id)

      message_id = message.id
      assert_receive {:ack_updated, ^message_id, %{acknowledged: 1, total: 2}}

      assert {:ok, %Receipt{acknowledged_at: ^at}} =
               Chat.acknowledge(scope, to_string(message.id))

      refute_receive {:ack_updated, _, _}

      assert {:ok, %Message{my_ack: :acknowledged, my_acknowledged_at: ^at, ack_count: 1}} =
               Chat.get_message(scope, message.id)
    end

    test "non-recipients get :not_found", %{
      alice_scope: alice_scope,
      london: london,
      message: message
    } do
      late_joiner = user_fixture()
      membership_fixture(late_joiner, london)
      outsider = user_fixture()
      membership_fixture(outsider, venue_fixture(organisation_fixture()))

      assert {:error, :not_found} = Chat.acknowledge(alice_scope, message.id)

      assert {:error, :not_found} =
               Chat.acknowledge(member_scope_fixture(late_joiner), message.id)

      assert {:error, :not_found} = Chat.acknowledge(member_scope_fixture(outsider), message.id)
      assert {:error, :not_found} = Chat.acknowledge(alice_scope, "nope")
    end

    test "text messages have no receipts",
         %{alice_scope: alice_scope, bob_scope: bob_scope} = ctx do
      text = message_fixture(alice_scope, ctx.conversations.org)

      assert {:error, :not_found} = Chat.acknowledge(bob_scope, text.id)

      assert {:ok, %Message{ack_count: nil, recipient_count: nil, my_ack: nil}} =
               Chat.get_message(bob_scope, text.id)
    end
  end

  describe "list_receipts/2" do
    setup %{alice_scope: scope, conversations: c} do
      %{message: announcement_fixture(scope, c.london)}
    end

    test ":not_found for non-participants, :unauthorized for staff and team managers", %{
      bob_scope: bob_scope,
      charlie_scope: charlie_scope,
      message: message
    } do
      assert {:error, :not_found} = Chat.list_receipts(charlie_scope, message.id)
      assert {:error, :unauthorized} = Chat.list_receipts(bob_scope, message.id)
      assert {:error, :not_found} = Chat.list_receipts(bob_scope, "nope")
    end

    test "the sender and other announcers see receipts with users", %{
      alice_scope: alice_scope,
      bob: bob,
      bob_scope: bob_scope,
      london: london,
      message: message
    } do
      co_admin = user_fixture(%{name: "Zed"})
      membership_fixture(co_admin, london, role: :admin)
      Chat.acknowledge(bob_scope, message.id)

      assert {:ok, [%Receipt{user: %{id: bob_id}, acknowledged_at: %DateTime{}}]} =
               Chat.list_receipts(alice_scope, message.id)

      assert bob_id == bob.id

      assert {:ok, [_bob_receipt]} =
               Chat.list_receipts(member_scope_fixture(co_admin), message.id)
    end

    test "text messages are :not_found", %{alice_scope: scope, conversations: c} do
      text = message_fixture(scope, c.london)
      assert {:error, :not_found} = Chat.list_receipts(scope, text.id)
    end
  end

  test "late joiners have my_ack: nil and aren't counted", %{
    alice_scope: alice_scope,
    london: london,
    conversations: c
  } do
    message = announcement_fixture(alice_scope, c.org)
    late_joiner = user_fixture()
    membership_fixture(late_joiner, london)
    scope = member_scope_fixture(late_joiner)

    assert {:ok, %Message{my_ack: nil, recipient_count: 2}} = Chat.get_message(scope, message.id)
    assert {:ok, [%Message{my_ack: nil}]} = Chat.list_messages(scope, c.org.id)
    assert pending_acks(scope)["Sona Hospitality Group"] == 0
  end

  test "pending_ack_count is set in list_conversations/1 and get_conversation/2", %{
    alice_scope: alice_scope,
    charlie_scope: charlie_scope,
    conversations: c
  } do
    first = announcement_fixture(alice_scope, c.org)
    announcement_fixture(alice_scope, c.org)
    announcement_fixture(alice_scope, c.bristol)
    message_fixture(alice_scope, c.org)

    assert pending_acks(charlie_scope) == %{
             "Sona Hospitality Group" => 2,
             "Bristol" => 1,
             "Bristol · FOH" => 0
           }

    {:ok, _} = Chat.acknowledge(charlie_scope, first.id)
    assert {:ok, %{pending_ack_count: 1}} = Chat.get_conversation(charlie_scope, c.org.id)
    assert {:ok, [_, %{my_ack: :pending}, _]} = Chat.list_messages(charlie_scope, c.org.id)

    assert pending_acks(alice_scope)["Sona Hospitality Group"] == 0
  end

  describe "list_pending_announcements/1" do
    test "lists what's left to read, high first and newest first within a priority", %{
      alice_scope: alice_scope,
      charlie_scope: charlie_scope,
      conversations: c
    } do
      low = announcement_fixture(alice_scope, c.org, priority: :low)
      old_high = announcement_fixture(alice_scope, c.bristol, priority: :high)
      mid = announcement_fixture(alice_scope, c.org, priority: :mid)
      new_high = announcement_fixture(alice_scope, c.org, priority: :high)
      read = announcement_fixture(alice_scope, c.org, priority: :high)
      {:ok, _} = Chat.acknowledge(charlie_scope, read.id)
      message_fixture(alice_scope, c.org)

      pending = Chat.list_pending_announcements(charlie_scope)

      assert Enum.map(pending, & &1.id) == [new_high.id, old_high.id, mid.id, low.id]
      assert Enum.all?(pending, &(&1.my_ack == :pending))
      assert [%{conversation: %{title: "Sona Hospitality Group"}, sender: %{}} | _] = pending

      # the sender holds no receipts
      assert Chat.list_pending_announcements(alice_scope) == []
    end

    test "drops announcements from conversations the user has left", %{
      alice_scope: alice_scope,
      charlie: charlie,
      charlie_scope: charlie_scope,
      conversations: c
    } do
      announcement_fixture(alice_scope, c.org, priority: :high)
      assert [_] = Chat.list_pending_announcements(charlie_scope)

      {:ok, _} = Org.end_membership(alice_scope, Repo.get_by!(Membership, user_id: charlie.id).id)

      assert Chat.list_pending_announcements(charlie_scope) == []
    end
  end

  describe "offboarding" do
    test "dropping a pending recipient shrinks the total and broadcasts it",
         %{
           alice_scope: alice_scope,
           bob: bob,
           bob_scope: bob_scope,
           charlie: charlie,
           conversations: c
         } = demo do
      extra_staff_fixture(demo, 43)
      message = announcement_fixture(alice_scope, c.org)
      {:ok, _} = Chat.acknowledge(bob_scope, message.id)
      :ok = Chat.subscribe_conversation(alice_scope, c.org.id)

      {:ok, _} = Org.end_membership(alice_scope, Repo.get_by!(Membership, user_id: charlie.id).id)

      message_id = message.id
      assert_receive {:ack_updated, ^message_id, %{acknowledged: 1, total: 44}}

      assert {:ok, %Message{ack_count: 1, recipient_count: 44}} =
               Chat.get_message(alice_scope, message.id)

      # an acknowledged recipient stays counted after leaving
      {:ok, _} = Org.end_membership(alice_scope, Repo.get_by!(Membership, user_id: bob.id).id)
      refute_receive {:ack_updated, ^message_id, _}

      assert {:ok, %Message{ack_count: 1, recipient_count: 44}} =
               Chat.get_message(alice_scope, message.id)
    end
  end

  defp team_of(conversation), do: Repo.get!(SonaComms.Org.Team, conversation.team_id)
end
