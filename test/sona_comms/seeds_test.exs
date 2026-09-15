defmodule SonaComms.SeedsTest do
  use SonaComms.DataCase, async: true

  import ExUnit.CaptureIO

  alias SonaComms.Accounts
  alias SonaComms.Accounts.{Scope, User}
  alias SonaComms.Chat
  alias SonaComms.Chat.{Conversation, Participant}
  alias SonaComms.Org
  alias SonaComms.Org.{Organisation, Team, Venue}

  defp run_seeds, do: capture_io(fn -> Code.eval_file("priv/repo/seeds.exs") end)

  defp persona(name), do: Accounts.get_user_by_email("#{name}@sona.test")

  defp conversations(user) do
    user
    |> Scope.for_user()
    |> Chat.list_conversations()
    |> Enum.map(&{&1.title, &1.can_announce})
    |> Enum.sort()
  end

  test "seeds the demo organisation" do
    run_seeds()

    assert Repo.aggregate(Venue, :count) == 3
    assert Repo.aggregate(Team, :count) == 9
    assert Repo.aggregate(User, :count) == 46
    assert Repo.aggregate(Conversation, :count) == 13

    org = Repo.one!(Organisation)
    org_conversation = Repo.get_by!(Conversation, organisation_id: org.id, kind: :org)

    assert Repo.aggregate(
             from(p in Participant,
               where: p.conversation_id == ^org_conversation.id and is_nil(p.left_at)
             ),
             :count
           ) == 46

    assert conversations(persona("alice")) == [
             {"Bristol", true},
             {"London", true},
             {"Manchester", true},
             {"Sona Hospitality Group", true}
           ]

    assert conversations(persona("bob")) == [
             {"London", false},
             {"London · Kitchen", true},
             {"Sona Hospitality Group", false}
           ]

    assert conversations(persona("charlie")) == [
             {"Bristol", false},
             {"Bristol · FOH", false},
             {"Sona Hospitality Group", false}
           ]

    memberships =
      Scope.for_system(org.id)
      |> Org.list_memberships()
      |> Enum.group_by(& &1.user.email, &{&1.role, &1.venue.name, &1.team && &1.team.name})

    assert Enum.sort(memberships["alice@sona.test"]) == [
             {:admin, "Bristol", nil},
             {:admin, "London", nil},
             {:admin, "Manchester", nil}
           ]

    assert memberships["bob@sona.test"] == [{:manager, "London", "Kitchen"}]
    assert memberships["charlie@sona.test"] == [{:staff, "Bristol", "FOH"}]
  end

  test "seeds unread sample messages for Bob" do
    run_seeds()

    unread =
      persona("bob")
      |> Scope.for_user()
      |> Chat.list_conversations()
      |> Map.new(&{&1.title, &1.unread_count})

    assert unread["Sona Hospitality Group"] == 1
    assert unread["London · Kitchen"] == 2
  end

  test "a second run raises" do
    run_seeds()
    assert_raise RuntimeError, ~r/mix ecto.reset/, fn -> run_seeds() end
  end
end
