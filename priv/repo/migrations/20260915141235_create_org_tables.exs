defmodule SonaComms.Repo.Migrations.CreateOrgTables do
  use Ecto.Migration

  def change do
    create table(:organisations) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:venues) do
      add :organisation_id, references(:organisations), null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:venues, [:organisation_id, :name])

    create table(:teams) do
      add :venue_id, references(:venues), null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:venue_id, :name])
    # target of the memberships composite FK
    create unique_index(:teams, [:id, :venue_id])

    create table(:memberships) do
      add :user_id, references(:users), null: false
      add :venue_id, references(:venues), null: false
      # (team_id, venue_id) -> teams(id, venue_id): the team must belong to the venue
      add :team_id, references(:teams, with: [venue_id: :venue_id])
      add :role, :string, null: false, default: "staff"
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:user_id, :venue_id, :team_id],
             where: "ended_at IS NULL",
             nulls_distinct: false,
             name: :memberships_one_active_per_slot
           )

    create index(:memberships, [:venue_id], where: "ended_at IS NULL")
    create index(:memberships, [:team_id], where: "ended_at IS NULL")
    create index(:memberships, [:user_id])

    create constraint(:memberships, :ended_after_start,
             check: "ended_at IS NULL OR ended_at >= inserted_at"
           )
  end
end
