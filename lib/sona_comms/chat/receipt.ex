defmodule SonaComms.Chat.Receipt do
  use Ecto.Schema

  alias SonaComms.Chat.Message

  # kind :announcement messages only
  schema "message_receipts" do
    # NULL = pending
    field :acknowledged_at, :utc_datetime_usec

    belongs_to :message, Message
    belongs_to :user, SonaComms.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
