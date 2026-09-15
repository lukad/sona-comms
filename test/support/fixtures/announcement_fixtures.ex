defmodule SonaComms.AnnouncementFixtures do
  @moduledoc """
  This module defines test helpers for announcements via the
  `SonaComms.Chat` context.
  """

  import SonaComms.AccountsFixtures
  import SonaComms.OrgFixtures

  alias SonaComms.Accounts.Scope
  alias SonaComms.Chat

  @doc """
  Adds `count` staff to a `demo_org_fixture/0`, alternating between
  London · Kitchen and Bristol · FOH. With 43, the org conversation has 45
  people besides Alice, as in the seeds.
  """
  def extra_staff_fixture(%{kitchen: kitchen, foh: foh}, count) do
    for i <- 1..count do
      user = user_fixture(%{name: "Staff #{i}"})
      membership_fixture(user, if(rem(i, 2) == 0, do: kitchen, else: foh))
      user
    end
  end

  @doc """
  Posts an announcement as the scope's user. Accepts `body:`.
  """
  def announcement_fixture(%Scope{} = scope, conversation, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "Announcement #{System.unique_integer([:positive])}"})
    {:ok, message} = Chat.post_announcement(scope, conversation.id, %{body: attrs.body})
    message
  end
end
