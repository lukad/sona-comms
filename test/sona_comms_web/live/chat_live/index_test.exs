defmodule SonaCommsWeb.ChatLive.IndexTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.ChatFixtures
  import SonaComms.OrgFixtures

  setup do
    demo_org_fixture()
  end

  test "Bob sees his three conversations and not Bristol's", %{
    conn: conn,
    bob: bob,
    conversations: c
  } do
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/")

    assert has_element?(lv, "#conversations")

    for conversation <- [c.org, c.london, c.kitchen] do
      assert has_element?(lv, "#conversations-#{conversation.id}")
    end

    for conversation <- [c.bristol, c.foh] do
      refute has_element?(lv, "#conversations-#{conversation.id}")
    end
  end

  test "#no-conversation-selected shows at /", %{conn: conn, bob: bob} do
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/")

    assert has_element?(lv, "#no-conversation-selected")
    refute has_element?(lv, "#conversation-header")
    refute has_element?(lv, "#message-form")
  end

  test "the sidebar lists conversations by kind: org, venues, teams, groups, DMs", %{
    conn: conn,
    alice: alice,
    bob: bob,
    charlie: charlie,
    conversations: c
  } do
    bob_scope = member_scope_fixture(bob)
    dm = dm_fixture(bob_scope, charlie)
    group = group_fixture(bob_scope, [alice])

    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/")

    assert sidebar_ids(lv) == [c.org.id, c.london.id, c.kitchen.id, group.id, dm.id]
    assert has_element?(lv, "#conversations-#{c.org.id} p", "Organisation")
    assert has_element?(lv, "#conversations-#{group.id} p", "Group chats")
    assert has_element?(lv, "#conversations-#{dm.id} p", "Direct messages")
  end

  test "a new message moves its conversation to the top of its section", %{
    conn: conn,
    alice: alice,
    conversations: c
  } do
    {:ok, lv, _html} = conn |> log_in_user(alice) |> live(~p"/")

    # neither venue has messages yet, so they're in title order
    assert sidebar_ids(lv) == [c.org.id, c.bristol.id, c.london.id]

    message_fixture(member_scope_fixture(alice), c.london)
    assert sidebar_ids(lv) == [c.org.id, c.london.id, c.bristol.id]

    message_fixture(member_scope_fixture(alice), c.bristol)
    assert sidebar_ids(lv) == [c.org.id, c.bristol.id, c.london.id]
  end

  defp sidebar_ids(lv) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#conversations > li")
    |> LazyHTML.attribute("id")
    |> Enum.map(fn "conversations-" <> id -> String.to_integer(id) end)
  end
end
