defmodule SonaComms.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias SonaComms.Chat.{Message, Participant}

  @kinds [:dm, :group, :team, :venue, :org]

  schema "conversations" do
    # Org tables are referenced by plain ids, not belongs_to (ADR 0002)
    field :organisation_id, :id
    field :kind, Ecto.Enum, values: @kinds
    # set by the creator; NULL for dm
    field :title, :string
    # kind :venue only
    field :venue_id, :id
    # kind :team only
    field :team_id, :id
    # kind :dm only: "#{min_user_id}:#{max_user_id}"
    field :dm_key, :string
    # dm/group creator; NULL for derived
    field :created_by_id, :id
    field :last_message_at, :utc_datetime_usec

    has_many :participants, Participant
    has_many :messages, Message

    # virtual, set by list_conversations/1 and get_conversation/2
    field :unread_count, :integer, virtual: true, default: 0
    field :pending_ack_count, :integer, virtual: true, default: 0
    field :display_title, :string, virtual: true
    field :can_announce, :boolean, virtual: true, default: false
    # form-only, create_group/2
    field :user_ids, {:array, :id}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  def derived_kinds, do: [:org, :venue, :team]

  @doc false
  def derived_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> unique_constraint(:organisation_id, name: :conversations_one_per_org)
    |> unique_constraint(:venue_id, name: :conversations_one_per_venue)
    |> unique_constraint(:team_id, name: :conversations_one_per_team)
    |> check_constraint(:kind, name: :conversation_shape)
  end

  @doc false
  def group_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :user_ids])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 80)
    |> check_constraint(:kind, name: :conversation_shape)
  end

  @doc false
  def dm_changeset(conversation) do
    conversation
    |> change()
    |> unique_constraint(:dm_key, name: :conversations_one_dm_per_pair)
    |> check_constraint(:kind, name: :conversation_shape)
  end
end
