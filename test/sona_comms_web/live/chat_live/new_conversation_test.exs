defmodule SonaCommsWeb.ChatLive.NewConversationTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.ChatFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Chat

  setup do
    demo_org_fixture()
  end

  describe "#new-dm-form" do
    test "creates a DM, navigates to it, and reuses it next time", %{
      conn: conn,
      bob: bob,
      charlie: charlie
    } do
      {:ok, charlie_lv, _html} = build_conn() |> log_in_user(charlie) |> live(~p"/")
      {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/new/dm")

      assert has_element?(lv, "#new-dm-form #start-dm-#{charlie.id}", "Charlie")
      refute has_element?(lv, "#start-dm-#{bob.id}")

      start_dm(lv, charlie)
      dm = only_dm(bob)
      assert_patch(lv, ~p"/c/#{dm.id}")
      assert has_element?(lv, "#conversation-header", "Charlie")
      assert has_element?(lv, "#conversations-#{dm.id}")

      # Charlie sees it appear without a reload
      assert has_element?(charlie_lv, "#conversations-#{dm.id}", "Bob")

      {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/new/dm")
      start_dm(lv, charlie)
      assert_patch(lv, ~p"/c/#{dm.id}")
      assert only_dm(bob).id == dm.id
    end

    test "the other person gets new DM messages as unread", %{
      conn: conn,
      bob: bob,
      charlie: charlie
    } do
      {:ok, charlie_lv, _html} = build_conn() |> log_in_user(charlie) |> live(~p"/")
      {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/new/dm")

      start_dm(lv, charlie)
      dm = only_dm(bob)
      assert_patch(lv, ~p"/c/#{dm.id}")

      lv |> form("#message-form", message: %{body: "Can you swap Friday?"}) |> render_submit()
      assert has_element?(charlie_lv, "#unread-#{dm.id}", "1")
    end
  end

  describe "#new-group-form" do
    test "creates a group chat visible to its members", %{
      conn: conn,
      alice: alice,
      bob: bob,
      charlie: charlie
    } do
      {:ok, charlie_lv, _html} = build_conn() |> log_in_user(charlie) |> live(~p"/")
      {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/new/group")

      lv
      |> form("#new-group-form", group: %{title: "Saturday wedding crew", user_ids: [charlie.id]})
      |> render_submit()

      [group] =
        for %{kind: :group} = c <- Chat.list_conversations(member_scope_fixture(bob)), do: c

      assert group.title == "Saturday wedding crew"
      assert_patch(lv, ~p"/c/#{group.id}")
      assert has_element?(lv, "#conversation-header", "Saturday wedding crew")
      assert has_element?(lv, "#participant-count", "2 people")

      assert has_element?(charlie_lv, "#conversations-#{group.id}", "Saturday wedding crew")
      assert {:error, :not_found} = Chat.get_conversation(member_scope_fixture(alice), group.id)
    end

    test "shows errors for a missing name or nobody picked", %{conn: conn, bob: bob} do
      {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/new/group")

      html = lv |> form("#new-group-form", group: %{title: ""}) |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert html =~ "Pick at least one person"
      assert has_element?(lv, "#new-group-form")

      assert [] =
               for(
                 %{kind: :group} = c <- Chat.list_conversations(member_scope_fixture(bob)),
                 do: c
               )
    end
  end

  test "#leave-group removes the group chat from the sidebar", %{
    conn: conn,
    bob: bob,
    charlie: charlie
  } do
    group = group_fixture(member_scope_fixture(bob), [charlie], title: "Wedding crew")
    {:ok, charlie_lv, _html} = build_conn() |> log_in_user(charlie) |> live(~p"/")
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{group.id}")

    lv |> element("#leave-group") |> render_click()

    assert_patch(lv, ~p"/")
    refute has_element?(lv, "#conversations-#{group.id}")
    assert has_element?(lv, "#no-conversation-selected")
    assert render(lv) =~ "You left Wedding crew."
    assert {:error, :not_found} = Chat.get_conversation(member_scope_fixture(bob), group.id)

    # Charlie stays in it
    assert has_element?(charlie_lv, "#conversations-#{group.id}")
  end

  test "#leave-group only shows for group chats", %{
    conn: conn,
    bob: bob,
    charlie: charlie,
    conversations: c
  } do
    dm = dm_fixture(member_scope_fixture(bob), charlie)
    conn = log_in_user(conn, bob)

    for id <- [c.org.id, c.london.id, c.kitchen.id, dm.id] do
      {:ok, lv, _html} = live(conn, ~p"/c/#{id}")
      refute has_element?(lv, "#leave-group")
    end
  end

  test "closing a modal returns to the open conversation", %{
    conn: conn,
    bob: bob,
    conversations: c
  } do
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{c.kitchen.id}")

    lv |> element("#new-dm-button") |> render_click()
    assert_patch(lv, ~p"/new/dm")
    assert has_element?(lv, "#new-dm-form")
    # the conversation stays open behind the modal
    assert has_element?(lv, "#conversation-header", "London · Kitchen")
  end

  defp start_dm(lv, user) do
    lv
    |> form("#new-dm-form")
    |> put_submitter("#start-dm-#{user.id}")
    |> render_submit()
  end

  defp only_dm(user) do
    [dm] = for %{kind: :dm} = c <- Chat.list_conversations(member_scope_fixture(user)), do: c
    dm
  end
end
