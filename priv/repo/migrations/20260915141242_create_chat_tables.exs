defmodule SonaComms.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :organisation_id, references(:organisations), null: false
      add :kind, :string, null: false
      add :title, :string
      add :venue_id, references(:venues)
      add :team_id, references(:teams)
      add :dm_key, :string
      add :created_by_id, references(:users)
      add :last_message_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:organisation_id])

    create unique_index(:conversations, [:organisation_id],
             where: "kind = 'org'",
             name: :conversations_one_per_org
           )

    create unique_index(:conversations, [:venue_id],
             where: "kind = 'venue'",
             name: :conversations_one_per_venue
           )

    create unique_index(:conversations, [:team_id],
             where: "kind = 'team'",
             name: :conversations_one_per_team
           )

    create unique_index(:conversations, [:organisation_id, :dm_key],
             where: "kind = 'dm'",
             name: :conversations_one_dm_per_pair
           )

    create constraint(:conversations, :conversation_shape,
             check: """
             (kind = 'org'   AND venue_id IS NULL     AND team_id IS NULL     AND dm_key IS NULL) OR
             (kind = 'venue' AND venue_id IS NOT NULL AND team_id IS NULL     AND dm_key IS NULL) OR
             (kind = 'team'  AND venue_id IS NULL     AND team_id IS NOT NULL AND dm_key IS NULL) OR
             (kind = 'group' AND venue_id IS NULL     AND team_id IS NULL     AND dm_key IS NULL) OR
             (kind = 'dm'    AND venue_id IS NULL     AND team_id IS NULL     AND dm_key IS NOT NULL)
             """
           )

    create table(:conversation_participants) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :user_id, references(:users), null: false
      add :can_announce, :boolean, null: false, default: false
      add :last_read_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_participants, [:conversation_id, :user_id])
    create index(:conversation_participants, [:user_id], where: "left_at IS NULL")

    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :sender_id, references(:users), null: false
      add :kind, :string, null: false, default: "text"
      add :body, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:messages, [:conversation_id, :inserted_at])

    create table(:message_receipts) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :user_id, references(:users), null: false
      add :acknowledged_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:message_receipts, [:message_id, :user_id])
    create index(:message_receipts, [:user_id], where: "acknowledged_at IS NULL")
  end
end
