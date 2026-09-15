defmodule SonaComms.Org.Team do
  use Ecto.Schema
  import Ecto.Changeset

  alias SonaComms.Org.Venue

  schema "teams" do
    field :name, :string
    # active people on the team, set by Org.list_venues/1
    field :member_count, :integer, virtual: true, default: 0

    belongs_to :venue, Venue

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name,
      name: :teams_venue_id_name_index,
      message: "is already a team at this venue"
    )
  end
end
