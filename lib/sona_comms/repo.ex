defmodule SonaComms.Repo do
  use Ecto.Repo,
    otp_app: :sona_comms,
    adapter: Ecto.Adapters.Postgres
end
