defmodule SonaComms.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SonaCommsWeb.Telemetry,
      SonaComms.Repo,
      {DNSCluster, query: Application.get_env(:sona_comms, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SonaComms.PubSub},
      # Start a worker by calling: SonaComms.Worker.start_link(arg)
      # {SonaComms.Worker, arg},
      # Start to serve requests, typically the last entry
      SonaCommsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SonaComms.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SonaCommsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
