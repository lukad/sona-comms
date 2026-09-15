defmodule SonaComms.Org.Organisation do
  use Ecto.Schema
  import Ecto.Changeset

  alias SonaComms.Org.Venue

  schema "organisations" do
    field :name, :string

    has_many :venues, Venue

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organisation, attrs) do
    organisation
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
  end
end
