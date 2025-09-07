defmodule Backend.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BackendWeb.Telemetry,
      Backend.Repo,
      {DNSCluster, query: Application.get_env(:backend, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Backend.PubSub},
      # HTTP client for Tesla
      {Finch, name: Backend.Finch, pools: Application.get_env(:backend, :finch_pools, [])},
      # Cache for external API responses
      Supervisor.child_spec({Cachex, name: :api_cache, options: [ttl: :timer.hours(1)]}, id: :api_cache),
      Supervisor.child_spec({Cachex, name: :player_cache, options: [ttl: :timer.hours(24)]}, id: :player_cache),
      Supervisor.child_spec({Cachex, name: :projection_cache, options: [ttl: :timer.minutes(30)]}, id: :projection_cache),
      # Sleeper API cache with multi-level TTL
      Supervisor.child_spec({Cachex, name: :sleeper_cache, options: [ttl: :timer.hours(1), max_size: 10_000]}, id: :sleeper_cache),
      # Start to serve requests, typically the last entry
      BackendWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Backend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
