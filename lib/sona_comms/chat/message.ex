defmodule SonaComms.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias SonaComms.Chat.Conversation

  schema "messages" do
    field :kind, Ecto.Enum, values: [:text, :announcement], default: :text
    field :body, :string

    # virtual, announcements only, per viewer
    field :ack_count, :integer, virtual: true
    field :recipient_count, :integer, virtual: true
    # :pending | :acknowledged | nil (not a recipient)
    field :my_ack, :any, virtual: true
    # when the viewer acknowledged it, for "Read at 14:02"; nil unless my_ack is :acknowledged
    field :my_acknowledged_at, :utc_datetime_usec, virtual: true

    belongs_to :conversation, Conversation
    belongs_to :sender, SonaComms.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
