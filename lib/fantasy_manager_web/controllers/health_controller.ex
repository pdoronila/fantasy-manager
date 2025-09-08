defmodule FantasyManagerWeb.HealthController do
  use FantasyManagerWeb, :controller

  alias FantasyManager.Repo
  
  @doc """
  Basic health check endpoint
  """
  def check(conn, _params) do
    json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
  end

  @doc """
  Readiness check - verifies dependencies are ready
  """
  def ready(conn, _params) do
    case check_dependencies() do
      :ok -> 
        json(conn, %{status: "ready", checks: %{database: "ok", cache: "ok"}})
      {:error, errors} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "not_ready", errors: errors})
    end
  end

  @doc """
  Liveness check - basic application health
  """
  def live(conn, _params) do
    json(conn, %{status: "alive", uptime: get_uptime()})
  end

  defp check_dependencies() do
    errors = []
    
    # Check database connection
    errors = case check_database() do
      :ok -> errors
      {:error, reason} -> [%{service: "database", error: reason} | errors]
    end
    
    # Check cache
    errors = case check_cache() do
      :ok -> errors
      {:error, reason} -> [%{service: "cache", error: reason} | errors]
    end
    
    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  defp check_database() do
    try do
      Repo.query!("SELECT 1")
      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp check_cache() do
    try do
      case Process.whereis(FantasyManager.Cache) do
        nil -> {:error, "cache not running"}
        _pid -> :ok
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp get_uptime() do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
end