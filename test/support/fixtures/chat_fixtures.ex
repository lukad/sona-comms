defmodule SonaComms.ChatFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `SonaComms.Chat` context.
  """

  alias SonaComms.Accounts.{Scope, User}
  alias SonaComms.Chat
  alias SonaComms.Chat.{Message, Receipt}
  alias SonaComms.Repo

  @doc """
  Posts a message as the scope's user. Accepts `body:` and `kind:`; a
  `kind: :announcement` message is posted as text and then relabelled.
  """
  def message_fixture(%Scope{} = scope, conversation, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "Message #{System.unique_integer([:positive])}"})
    {:ok, message} = Chat.post_message(scope, conversation.id, %{body: attrs.body})

    case Map.get(attrs, :kind, :text) do
      :text -> message
      kind -> message |> Ecto.Changeset.change(kind: kind) |> Repo.update!()
    end
  end

  def dm_fixture(%Scope{} = scope, %User{} = other) do
    {:ok, conversation} = Chat.start_dm(scope, other.id)
    conversation
  end

  def group_fixture(%Scope{} = scope, users, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{title: "Group #{System.unique_integer([:positive])}"})

    {:ok, conversation} =
      Chat.create_group(scope, %{
        "title" => attrs.title,
        "user_ids" => Enum.map(users, & &1.id)
      })

    conversation
  end

  @doc """
  Inserts a receipt directly. Accepts `acknowledged_at:`; nil means pending.
  """
  def receipt_fixture(%Message{} = message, %User{} = user, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{acknowledged_at: nil})

    Repo.insert!(%Receipt{
      message_id: message.id,
      user_id: user.id,
      acknowledged_at: attrs.acknowledged_at
    })
  end
end
