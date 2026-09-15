defmodule SonaComms.Org.Venue do
  use Ecto.Schema
  import Ecto.Changeset

  alias SonaComms.Org.{Organisation, Team}

  schema "venues" do
    field :name, :string

    belongs_to :organisation, Organisation
    has_many :teams, Team

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name,
      name: :venues_organisation_id_name_index,
      message: "is already a venue"
    )
  end
end
