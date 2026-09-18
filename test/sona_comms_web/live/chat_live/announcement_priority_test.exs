defmodule SonaCommsWeb.ChatLive.AnnouncementPriorityTest do
  use SonaCommsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SonaComms.AnnouncementFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Chat

  setup do
    demo = demo_org_fixture()
    Map.put(demo, :alice_scope, member_scope_fixture(demo.alice))
  end

  defp live_as(user, path), do: build_conn() |> log_in_user(user) |> live(path)

  describe "high priority" do
    test "Alice's high priority announcement blocks Bob, live, until he reads it", %{
      alice: alice,
      alice_scope: alice_scope,
      bob: bob,
      conversations: c
    } do
      {:ok, bob_lv, _html} = live_as(bob, ~p"/c/#{c.org.id}")
      refute has_element?(bob_lv, "#urgent-announcement-modal")

      {:ok, alice_lv, _html} = live_as(alice, ~p"/c/#{c.org.id}/announce")
      assert has_element?(alice_lv, "#announcement-priority input[value=mid][checked]")

      alice_lv
      |> form("#announcement-form", message: %{body: "Sesame in the new buns.", priority: "high"})
      |> render_submit()

      {:ok, [message]} = Chat.list_messages(alice_scope, c.org.id)
      assert message.priority == :high
      assert has_element?(alice_lv, "#announcement-#{message.id}-priority", "High priority")
      # the sender isn't asked to read her own announcement
      refute has_element?(alice_lv, "#urgent-announcement-modal")

      assert has_element?(bob_lv, "#urgent-announcement-modal", "Sesame in the new buns.")
      # no way out but reading it
      refute has_element?(bob_lv, "#urgent-announcement-modal button[aria-label=close]")
      refute has_element?(bob_lv, "#urgent-announcement-modal [phx-click-away]")

      bob_lv |> element("#urgent-ack-#{message.id}") |> render_click()

      refute has_element?(bob_lv, "#urgent-announcement-modal")
      assert has_element?(bob_lv, "#acked-#{message.id}")
      assert has_element?(alice_lv, "#ack-summary-#{message.id}", "1 of 2 read")
    end

    test "several are shown one after another, and mid and low don't block", %{
      alice_scope: alice_scope,
      bob: bob,
      conversations: c
    } do
      first = announcement_fixture(alice_scope, c.org, priority: :high)
      second = announcement_fixture(alice_scope, c.london, priority: :high)
      announcement_fixture(alice_scope, c.org, priority: :mid)
      announcement_fixture(alice_scope, c.org, priority: :low)

      {:ok, lv, _html} = live_as(bob, ~p"/")

      lv |> element("#urgent-ack-#{second.id}") |> render_click()
      lv |> element("#urgent-ack-#{first.id}") |> render_click()

      refute has_element?(lv, "#urgent-announcement-modal")
      assert has_element?(lv, "#pending-announcements-count", "2")
    end
  end

  describe "the announcements list" do
    test "shows what Bob still has to read, most urgent first, and updates live", %{
      alice_scope: alice_scope,
      bob: bob,
      conversations: c
    } do
      low = announcement_fixture(alice_scope, c.org, priority: :low)
      mid = announcement_fixture(alice_scope, c.london, priority: :mid)

      {:ok, lv, _html} = live_as(bob, ~p"/")
      assert has_element?(lv, "#pending-announcements-count", "2")
      lv |> element("#announcements-link") |> render_click()
      assert_patch(lv, ~p"/announcements")

      ids =
        lv
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#pending-announcements [id^=list-ack-]")
        |> LazyHTML.attribute("id")

      assert ids == ["list-ack-#{mid.id}", "list-ack-#{low.id}"]

      lv |> element("#list-ack-#{mid.id}") |> render_click()
      refute has_element?(lv, "#list-ack-#{mid.id}")
      assert has_element?(lv, "#pending-announcements-count", "1")

      new = announcement_fixture(alice_scope, c.org, priority: :low)
      # the broadcast came from this process, so it is handled before get_state
      _ = :sys.get_state(lv.pid)
      assert has_element?(lv, "#list-ack-#{new.id}")
      assert has_element?(lv, "#pending-announcements-count", "2")

      lv |> element("#list-ack-#{low.id}") |> render_click()
      lv |> element("#list-ack-#{new.id}") |> render_click()

      refute has_element?(lv, "#pending-announcements [id^=list-ack-]")
      refute has_element?(lv, "#pending-announcements-count")
    end

    test "links each announcement to its chat", %{
      alice_scope: alice_scope,
      bob: bob,
      conversations: c
    } do
      message = announcement_fixture(alice_scope, c.london, priority: :low)

      {:ok, lv, _html} = live_as(bob, ~p"/announcements")
      lv |> element("#pending-announcement-link-#{message.id}") |> render_click()

      assert_patch(lv, ~p"/c/#{c.london.id}")
      assert has_element?(lv, "#ack-#{message.id}")
    end
  end
end
