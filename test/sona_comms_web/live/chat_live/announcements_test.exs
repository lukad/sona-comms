defmodule SonaCommsWeb.ChatLive.AnnouncementsTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.AnnouncementFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Chat

  setup do
    demo = demo_org_fixture()

    Map.merge(demo, %{
      alice_scope: member_scope_fixture(demo.alice),
      bob_scope: member_scope_fixture(demo.bob),
      charlie_scope: member_scope_fixture(demo.charlie)
    })
  end

  defp live_as(user, path), do: build_conn() |> log_in_user(user) |> live(path)

  test "Alice announces, Bob reads it and Alice's count updates live",
       %{
         alice: alice,
         alice_scope: alice_scope,
         bob: bob,
         conversations: c
       } = demo do
    extra_staff_fixture(demo, 43)
    {:ok, bob_lv, _html} = live_as(bob, ~p"/c/#{c.org.id}")
    {:ok, alice_lv, _html} = live_as(alice, ~p"/c/#{c.org.id}/announce")

    assert alice_lv
           |> form("#announcement-form", message: %{body: ""})
           |> render_change() =~ "can&#39;t be blank"

    alice_lv
    |> form("#announcement-form", message: %{body: "Allergen update: sesame from Monday."})
    |> render_submit()

    assert_patch(alice_lv, ~p"/c/#{c.org.id}")
    {:ok, [message]} = Chat.list_messages(alice_scope, c.org.id)

    assert has_element?(alice_lv, "#ack-summary-#{message.id}", "0 of 45 read")
    refute has_element?(alice_lv, "#ack-#{message.id}")

    assert has_element?(bob_lv, "#ack-#{message.id}")
    refute has_element?(bob_lv, "#ack-summary-#{message.id}")

    bob_lv |> element("#ack-#{message.id}") |> render_click()

    assert has_element?(bob_lv, "#acked-#{message.id}")
    refute has_element?(bob_lv, "#ack-#{message.id}")
    assert has_element?(alice_lv, "#ack-summary-#{message.id}", "1 of 45 read")
  end

  test "the receipts modal lists who has and hasn't read it, live", %{
    alice: alice,
    alice_scope: alice_scope,
    bob_scope: bob_scope,
    charlie_scope: charlie_scope,
    conversations: c
  } do
    message = announcement_fixture(alice_scope, c.org)
    {:ok, _} = Chat.acknowledge(bob_scope, message.id)

    {:ok, lv, _html} = live_as(alice, ~p"/c/#{c.org.id}")
    lv |> element("#ack-summary-#{message.id}") |> render_click()
    assert_patch(lv, ~p"/c/#{c.org.id}/announcements/#{message.id}")

    assert has_element?(lv, "#receipts-modal")
    assert has_element?(lv, "#receipts-summary", "of 2 read")
    assert has_element?(lv, "#read-receipts", "Bob")
    assert has_element?(lv, "#pending-receipts", "Charlie")

    {:ok, _} = Chat.acknowledge(charlie_scope, message.id)
    # the broadcast came from this process, so it is handled before get_state
    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#read-receipts", "Charlie")
    refute has_element?(lv, "#pending-receipts", "Charlie")
    refute has_element?(lv, "#pending-receipts [id^='pending_receipts-']")
  end

  test "staff can't open the receipts or announce routes", %{
    alice_scope: alice_scope,
    bob: bob,
    conversations: c
  } do
    message = announcement_fixture(alice_scope, c.org)

    org_path = ~p"/c/#{c.org.id}"

    assert {:error, {:live_redirect, %{to: ^org_path, flash: %{"error" => error}}}} =
             live_as(bob, ~p"/c/#{c.org.id}/announcements/#{message.id}")

    assert error =~ "Only the sender and managers"

    assert {:error, {:live_redirect, %{to: ^org_path, flash: %{"error" => error}}}} =
             live_as(bob, ~p"/c/#{c.org.id}/announce")

    assert error =~ "Only managers and admins"

    # a connected patch is bounced back too
    {:ok, lv, _html} = live_as(bob, org_path)
    lv |> render_patch(~p"/c/#{c.org.id}/announcements/#{message.id}")
    assert_patch(lv, org_path)
    refute has_element?(lv, "#receipts-modal")
  end

  test "Bob's freshly mounted / shows the pending pill, which clears when he reads it", %{
    alice_scope: alice_scope,
    bob: bob,
    conversations: c
  } do
    message = announcement_fixture(alice_scope, c.org)

    {:ok, lv, _html} = live_as(bob, ~p"/")
    assert has_element?(lv, "#pending-acks-#{c.org.id}", "1 announcement")

    {:ok, lv, _html} = live_as(bob, ~p"/c/#{c.org.id}")
    assert has_element?(lv, "#pending-acks-#{c.org.id}")
    lv |> element("#ack-#{message.id}") |> render_click()
    refute has_element?(lv, "#pending-acks-#{c.org.id}")
  end

  test "Charlie has no #announce-button, and Bob has it only in London · Kitchen", %{
    alice: alice,
    bob: bob,
    charlie: charlie,
    conversations: c
  } do
    for conversation <- [c.org, c.bristol, c.foh] do
      {:ok, lv, _html} = live_as(charlie, ~p"/c/#{conversation.id}")
      refute has_element?(lv, "#announce-button")
    end

    for conversation <- [c.org, c.london] do
      {:ok, lv, _html} = live_as(bob, ~p"/c/#{conversation.id}")
      refute has_element?(lv, "#announce-button")
    end

    {:ok, lv, _html} = live_as(bob, ~p"/c/#{c.kitchen.id}")
    assert has_element?(lv, "#announce-button")

    {:ok, lv, _html} = live_as(alice, ~p"/c/#{c.org.id}")
    lv |> element("#announce-button") |> render_click()
    assert_patch(lv, ~p"/c/#{c.org.id}/announce")
    assert has_element?(lv, "#announcement-form")
  end
end
