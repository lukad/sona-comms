defmodule SonaComms.Org.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  alias SonaComms.Org.{Team, Venue}

  @roles [:staff, :manager, :admin]

  schema "memberships" do
    field :role, Ecto.Enum, values: @roles, default: :staff
    # NULL = active. Rows are never deleted.
    field :ended_at, :utc_datetime

    # form-only: the person is found or created by email
    field :email, :string, virtual: true
    field :name, :string, virtual: true

    belongs_to :user, SonaComms.Accounts.User
    belongs_to :venue, Venue
    # NULL = venue-level membership
    belongs_to :team, Team

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  @doc """
  Changeset for the membership form: email, name, venue_id, team_id and role.

  `user_id` is set by `SonaComms.Org.create_membership/2`, never cast.
  """
  def form_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:email, :name, :venue_id, :team_id, :role])
    |> update_change(:email, &String.trim/1)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:email, :venue_id, :role])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:email,
      name: :memberships_one_active_per_slot,
      message: "is already on this venue or team"
    )
    |> foreign_key_constraint(:team_id,
      name: :memberships_team_id_fkey,
      message: "is not part of this venue"
    )
  end

  @doc false
  def end_changeset(membership, ended_at) do
    membership
    |> change(ended_at: ended_at)
    |> check_constraint(:ended_at, name: :ended_after_start)
  end
end
