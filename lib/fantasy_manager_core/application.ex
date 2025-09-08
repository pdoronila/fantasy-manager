defmodule FantasyManager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FantasyManagerWeb.Telemetry,
      FantasyManager.Repo,
      {DNSCluster, query: Application.get_env(:fantasy_manager, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FantasyManager.PubSub},
      # HTTP client for Tesla
      {Finch, name: FantasyManager.Finch, pools: Application.get_env(:fantasy_manager, :finch_pools, [])},
      # Main cache process (for health checks)
      Supervisor.child_spec({Cachex, name: FantasyManager.Cache, options: [ttl: :timer.minutes(5)]}, id: :main_cache),
      # Cache for external API responses
      Supervisor.child_spec({Cachex, name: :api_cache, options: [ttl: :timer.hours(1)]}, id: :api_cache),
      Supervisor.child_spec({Cachex, name: :player_cache, options: [ttl: :timer.hours(24)]}, id: :player_cache),
      Supervisor.child_spec({Cachex, name: :projection_cache, options: [ttl: :timer.minutes(30)]}, id: :projection_cache),
      # Sleeper API cache with multi-level TTL
      Supervisor.child_spec({Cachex, name: :sleeper_cache, options: [ttl: :timer.hours(1), max_size: 10_000]}, id: :sleeper_cache),
      # Start to serve requests, typically the last entry
      FantasyManagerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [
      strategy: :one_for_one, 
      name: FantasyManager.Supervisor,
      max_restarts: 3,
      max_seconds: 5
    ]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FantasyManagerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
