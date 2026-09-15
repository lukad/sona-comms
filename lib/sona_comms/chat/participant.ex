defmodule SonaComms.Chat.Participant do
  use Ecto.Schema

  alias SonaComms.Chat.Conversation

  schema "conversation_participants" do
    # derived kinds only, written by Chat.sync_participants/2
    field :can_announce, :boolean, default: false
    # set to join time
    field :last_read_at, :utc_datetime_usec
    # NULL = active
    field :left_at, :utc_datetime_usec

    belongs_to :conversation, Conversation
    belongs_to :user, SonaComms.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
