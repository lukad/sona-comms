defmodule SonaCommsWeb.ChatLive.ConversationTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.AccountsFixtures
  import SonaComms.ChatFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts.Scope
  alias SonaComms.Chat
  alias SonaComms.Org

  setup do
    demo = demo_org_fixture()
    # a London · Kitchen colleague of Bob's
    dana = user_fixture(%{name: "Dana"})
    membership_fixture(dana, demo.kitchen)
    Map.put(demo, :dana, dana)
  end

  test "/c/:id renders #messages with the conversation's messages", %{
    conn: conn,
    bob: bob,
    conversations: c
  } do
    message = message_fixture(member_scope_fixture(bob), c.kitchen, body: "Prep starts at 8")

    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{c.kitchen.id}")

    assert has_element?(lv, "#conversation-header", "London · Kitchen")
    assert has_element?(lv, "#participant-count", "Team · 2 people")
    assert has_element?(lv, "#messages")
    assert has_element?(lv, "#messages-#{message.id}", "Prep starts at 8")
    assert has_element?(lv, "#message-form")
    refute has_element?(lv, "#leave-group")
  end

  test "submitting #message-form appends a message", %{conn: conn, bob: bob, conversations: c} do
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{c.kitchen.id}")

    lv
    |> form("#message-form", message: %{body: "  Fish delivery is late  \n"})
    |> render_submit()

    assert {:ok, [message]} = Chat.list_messages(member_scope_fixture(bob), c.kitchen.id)
    assert message.body == "Fish delivery is late"
    assert has_element?(lv, "#messages-#{message.id}", "Fish delivery is late")
  end

  test "a blank message is ignored and an overlong one shows an error", %{
    conn: conn,
    bob: bob,
    conversations: c
  } do
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{c.kitchen.id}")

    lv |> form("#message-form", message: %{body: "   "}) |> render_submit()
    assert {:ok, []} = Chat.list_messages(member_scope_fixture(bob), c.kitchen.id)

    html =
      lv
      |> form("#message-form", message: %{body: String.duplicate("a", 4001)})
      |> render_submit()

    assert html =~ "should be at most 4000 character(s)"
    assert {:ok, []} = Chat.list_messages(member_scope_fixture(bob), c.kitchen.id)
  end

  test "a second user's connected LiveView receives the message live", %{
    conn: conn,
    bob: bob,
    dana: dana,
    conversations: c
  } do
    {:ok, bob_lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{c.kitchen.id}")
    {:ok, dana_lv, _html} = build_conn() |> log_in_user(dana) |> live(~p"/c/#{c.kitchen.id}")

    bob_lv
    |> form("#message-form", message: %{body: "Who's on close tonight?"})
    |> render_submit()

    {:ok, [message]} = Chat.list_messages(member_scope_fixture(bob), c.kitchen.id)
    assert has_element?(dana_lv, "#messages-#{message.id}", "Who's on close tonight?")

    # read on arrival: no badge in the sidebar, nothing unread in the database
    refute has_element?(dana_lv, "#unread-#{c.kitchen.id}")

    assert {:ok, %{unread_count: 0}} =
             Chat.get_conversation(member_scope_fixture(dana), c.kitchen.id)
  end

  test "#unread-<id> increments where the conversation isn't open and clears when opened", %{
    conn: conn,
    bob: bob,
    dana: dana,
    conversations: c
  } do
    bob_scope = member_scope_fixture(bob)
    {:ok, lv, _html} = conn |> log_in_user(dana) |> live(~p"/c/#{c.london.id}")

    refute has_element?(lv, "#unread-#{c.kitchen.id}")

    message_fixture(bob_scope, c.kitchen)
    assert has_element?(lv, "#unread-#{c.kitchen.id}", "1")

    message_fixture(bob_scope, c.kitchen)

    assert has_element?(
             lv,
             ~s(#unread-#{c.kitchen.id}[aria-label="2 unread messages"]),
             "2"
           )

    lv |> element("#conversations-#{c.kitchen.id} a") |> render_click()

    assert_patch(lv, ~p"/c/#{c.kitchen.id}")
    refute has_element?(lv, "#unread-#{c.kitchen.id}")

    assert {:ok, %{unread_count: 0}} =
             Chat.get_conversation(member_scope_fixture(dana), c.kitchen.id)
  end

  test "reading a conversation in one tab clears its badge in another", %{
    conn: conn,
    bob: bob,
    dana: dana,
    conversations: c
  } do
    message_fixture(member_scope_fixture(bob), c.kitchen)
    conn = log_in_user(conn, dana)

    {:ok, other_tab, _html} = live(conn, ~p"/")
    assert has_element?(other_tab, "#unread-#{c.kitchen.id}", "1")

    {:ok, _tab, _html} = live(conn, ~p"/c/#{c.kitchen.id}")
    refute has_element?(other_tab, "#unread-#{c.kitchen.id}")
  end

  test "a non-participant opening /c/:id is redirected to / with a flash", %{
    conn: conn,
    charlie: charlie,
    conversations: c
  } do
    conn = log_in_user(conn, charlie)

    for id <- [c.kitchen.id, "nope", 0] do
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/c/#{id}")
      assert flash["error"] =~ "isn't available"
    end
  end

  test "ending the membership behind the open team conversation navigates to /", %{
    conn: conn,
    org: org,
    bob: bob,
    bristol: bristol,
    conversations: c
  } do
    # Bob keeps a membership elsewhere, so he keeps access to the app
    membership_fixture(bob, bristol)
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{c.kitchen.id}")

    system = Scope.for_system(org.id)
    kitchen = Enum.find(Org.list_memberships(system), &(&1.user_id == bob.id and &1.team_id))
    assert {:ok, _} = Org.end_membership(system, kitchen.id)

    assert {"/", flash} = assert_redirect(lv)
    assert flash["error"] =~ "no longer have access to London · Kitchen"

    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/")
    assert has_element?(lv, "#conversations-#{c.bristol.id}")
    refute has_element?(lv, "#conversations-#{c.kitchen.id}")
    refute has_element?(lv, "#conversations-#{c.london.id}")
  end

  test "losing a conversation that isn't open removes it from the sidebar", %{
    conn: conn,
    org: org,
    bob: bob,
    bristol: bristol,
    conversations: c
  } do
    membership_fixture(bob, bristol)
    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/c/#{c.org.id}")
    assert has_element?(lv, "#conversations-#{c.bristol.id}")

    system = Scope.for_system(org.id)

    bristol_membership =
      Enum.find(
        Org.list_memberships(system),
        &(&1.user_id == bob.id and &1.venue_id == bristol.id)
      )

    assert {:ok, _} = Org.end_membership(system, bristol_membership.id)

    refute has_element?(lv, "#conversations-#{c.bristol.id}")
    assert has_element?(lv, "#conversation-header")

    # a stale subscription leaks nothing
    message_fixture(member_scope_fixture(bob), c.org)
    refute has_element?(lv, "#conversations-#{c.bristol.id}")
  end

  test "joining a conversation adds it to the sidebar live", %{
    conn: conn,
    bob: bob,
    bristol: bristol,
    conversations: c
  } do
    erin = user_fixture(%{name: "Erin"})
    membership_fixture(erin, bristol)

    {:ok, lv, _html} = conn |> log_in_user(bob) |> live(~p"/")
    refute has_element?(lv, "#conversations-#{c.bristol.id}")

    membership_fixture(bob, bristol)
    assert has_element?(lv, "#conversations-#{c.bristol.id}")

    # and it's subscribed: new messages there bump the badge
    message_fixture(member_scope_fixture(erin), c.bristol)
    assert has_element?(lv, "#unread-#{c.bristol.id}", "1")
  end
end
