defmodule FantasyManager.External.SleeperClient do
  @moduledoc """
  Sleeper API client with caching and rate limiting.
  
  Provides access to Sleeper API endpoints with built-in caching,
  error handling, and rate limiting. Caches responses based on
  data freshness requirements:
  - Player info: 24h TTL (rarely changes)
  - League/roster data: 10min TTL (changes during trades/waivers)
  - Game stats: 1h TTL during games, 6h otherwise
  """

  use Tesla
  require Logger

  @base_url "https://api.sleeper.com/v1"
  @default_timeout 30_000
  # @rate_limit_per_minute 60

  plug Tesla.Middleware.BaseUrl, @base_url
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Timeout, timeout: @default_timeout
  plug Tesla.Middleware.Retry,
    delay: 1000,
    max_retries: 3,
    max_delay: 5000,
    should_retry: &should_retry/1

  plug Tesla.Middleware.Headers, [
    {"user-agent", "FantasyManager/1.0"},
    {"accept", "application/json"}
  ]

  @doc """
  Get all NFL players from Sleeper API.
  Returns a map with player_id as keys and player data as values.
  Cached for 24 hours since player info rarely changes.
  """
  def get_all_players do
    cache_key = "sleeper:players:all"
    
    case Cachex.get(:sleeper_cache, cache_key) do
      {:ok, nil} ->
        case get("/players/nfl") do
          {:ok, %Tesla.Env{status: 200, body: players}} ->
            # Cache for 24 hours
            Cachex.put(:sleeper_cache, cache_key, players, ttl: :timer.hours(24))
            {:ok, players}
          
          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.error("Sleeper API error getting players: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          
          {:error, reason} ->
            Logger.error("Sleeper API request failed: #{inspect(reason)}")
            {:error, {:network_error, reason}}
        end
      
      {:ok, cached_players} ->
        {:ok, cached_players}
      
      {:error, reason} ->
        Logger.error("Cache error: #{inspect(reason)}")
        # Fallback to direct API call if cache fails
        get_all_players_direct()
    end
  end

  @doc """
  Get league information by Sleeper league ID.
  Cached for 10 minutes since league settings rarely change during season.
  """
  def get_league(league_id) do
    cache_key = "sleeper:league:#{league_id}"
    
    case Cachex.get(:sleeper_cache, cache_key) do
      {:ok, nil} ->
        case get("/league/#{league_id}") do
          {:ok, %Tesla.Env{status: 200, body: league}} ->
            # Cache for 10 minutes
            Cachex.put(:sleeper_cache, cache_key, league, ttl: :timer.minutes(10))
            {:ok, league}
          
          {:ok, %Tesla.Env{status: 404}} ->
            {:error, :league_not_found}
          
          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.error("Sleeper API error getting league #{league_id}: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          
          {:error, reason} ->
            Logger.error("Sleeper API request failed for league #{league_id}: #{inspect(reason)}")
            {:error, {:network_error, reason}}
        end
      
      {:ok, cached_league} ->
        {:ok, cached_league}
      
      {:error, reason} ->
        Logger.error("Cache error: #{inspect(reason)}")
        get_league_direct(league_id)
    end
  end

  @doc """
  Get users (managers) for a league.
  Cached for 10 minutes since league membership rarely changes.
  """
  def get_league_users(league_id) do
    cache_key = "sleeper:league_users:#{league_id}"
    
    case Cachex.get(:sleeper_cache, cache_key) do
      {:ok, nil} ->
        case get("/league/#{league_id}/users") do
          {:ok, %Tesla.Env{status: 200, body: users}} ->
            Cachex.put(:sleeper_cache, cache_key, users, ttl: :timer.minutes(10))
            {:ok, users}
          
          {:ok, %Tesla.Env{status: 404}} ->
            {:error, :league_not_found}
          
          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.error("Sleeper API error getting league users #{league_id}: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          
          {:error, reason} ->
            Logger.error("Sleeper API request failed for league users #{league_id}: #{inspect(reason)}")
            {:error, {:network_error, reason}}
        end
      
      {:ok, cached_users} ->
        {:ok, cached_users}
      
      {:error, reason} ->
        Logger.error("Cache error: #{inspect(reason)}")
        get_league_users_direct(league_id)
    end
  end

  @doc """
  Get rosters for a league.
  Cached for 10 minutes since rosters change during trades/waivers.
  """
  def get_league_rosters(league_id) do
    cache_key = "sleeper:league_rosters:#{league_id}"
    
    case Cachex.get(:sleeper_cache, cache_key) do
      {:ok, nil} ->
        case get("/league/#{league_id}/rosters") do
          {:ok, %Tesla.Env{status: 200, body: rosters}} ->
            Cachex.put(:sleeper_cache, cache_key, rosters, ttl: :timer.minutes(10))
            {:ok, rosters}
          
          {:ok, %Tesla.Env{status: 404}} ->
            {:error, :league_not_found}
          
          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.error("Sleeper API error getting league rosters #{league_id}: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          
          {:error, reason} ->
            Logger.error("Sleeper API request failed for league rosters #{league_id}: #{inspect(reason)}")
            {:error, {:network_error, reason}}
        end
      
      {:ok, cached_rosters} ->
        {:ok, cached_rosters}
      
      {:error, reason} ->
        Logger.error("Cache error: #{inspect(reason)}")
        get_league_rosters_direct(league_id)
    end
  end

  @doc """
  Get matchups for a specific week in a league.
  Cached for 1 hour during games, 6 hours otherwise.
  """
  def get_league_matchups(league_id, week) do
    cache_key = "sleeper:league_matchups:#{league_id}:#{week}"
    
    # Dynamic TTL based on game status
    ttl = if in_season?(), do: :timer.hours(1), else: :timer.hours(6)
    
    case Cachex.get(:sleeper_cache, cache_key) do
      {:ok, nil} ->
        case get("/league/#{league_id}/matchups/#{week}") do
          {:ok, %Tesla.Env{status: 200, body: matchups}} ->
            Cachex.put(:sleeper_cache, cache_key, matchups, ttl: ttl)
            {:ok, matchups}
          
          {:ok, %Tesla.Env{status: 404}} ->
            {:error, :matchups_not_found}
          
          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.error("Sleeper API error getting matchups #{league_id}/#{week}: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          
          {:error, reason} ->
            Logger.error("Sleeper API request failed for matchups #{league_id}/#{week}: #{inspect(reason)}")
            {:error, {:network_error, reason}}
        end
      
      {:ok, cached_matchups} ->
        {:ok, cached_matchups}
      
      {:error, reason} ->
        Logger.error("Cache error: #{inspect(reason)}")
        get_league_matchups_direct(league_id, week)
    end
  end

  @doc """
  Get current NFL state (week, season info).
  Cached for 1 hour.
  """
  def get_nfl_state do
    cache_key = "sleeper:nfl_state"
    
    case Cachex.get(:sleeper_cache, cache_key) do
      {:ok, nil} ->
        case get("/state/nfl") do
          {:ok, %Tesla.Env{status: 200, body: state}} ->
            Cachex.put(:sleeper_cache, cache_key, state, ttl: :timer.hours(1))
            {:ok, state}
          
          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.error("Sleeper API error getting NFL state: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          
          {:error, reason} ->
            Logger.error("Sleeper API request failed for NFL state: #{inspect(reason)}")
            {:error, {:network_error, reason}}
        end
      
      {:ok, cached_state} ->
        {:ok, cached_state}
      
      {:error, reason} ->
        Logger.error("Cache error: #{inspect(reason)}")
        get_nfl_state_direct()
    end
  end

  @doc """
  Get trending players from Sleeper API.
  
  Args:
    trend_type - "add" for most added players, "drop" for most dropped players
  
  Returns:
    {:ok, %{player_id => count}} - Map of player IDs to trend counts
    {:error, reason} - Error details
  
  Cached for 15 minutes as trending data changes frequently but not constantly.
  """
  def get_trending_players(trend_type) when trend_type in ["add", "drop"] do
    cache_key = "sleeper:trending:#{trend_type}"
    
    case Cachex.get(:sleeper_cache, cache_key) do
      {:ok, nil} ->
        case get("/players/nfl/trending/#{trend_type}") do
          {:ok, %Tesla.Env{status: 200, body: trending_data}} ->
            # Cache for 15 minutes
            Cachex.put(:sleeper_cache, cache_key, trending_data, ttl: :timer.minutes(15))
            {:ok, trending_data}
          
          {:ok, %Tesla.Env{status: 404}} ->
            {:error, "Trending data not found"}
          
          {:ok, %Tesla.Env{status: 429}} ->
            {:error, "API rate limit exceeded"}
          
          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.error("Sleeper API error getting trending #{trend_type}: #{status} - #{inspect(body)}")
            {:error, "API error: #{status}"}
          
          {:error, %Tesla.Error{reason: :timeout}} ->
            Logger.error("Sleeper API timeout getting trending #{trend_type}")
            {:error, "API timeout"}
          
          {:error, reason} ->
            Logger.error("Sleeper API request failed for trending #{trend_type}: #{inspect(reason)}")
            {:error, "Network error: #{inspect(reason)}"}
        end
      
      {:ok, cached_trending} ->
        {:ok, cached_trending}
      
      {:error, reason} ->
        Logger.error("Cache error: #{inspect(reason)}")
        get_trending_players_direct(trend_type)
    end
  end
  
  def get_trending_players(trend_type) do
    {:error, "Invalid trend type: #{trend_type}. Must be 'add' or 'drop'"}
  end

  @doc """
  Clear all Sleeper-related cache entries.
  Useful for forcing fresh data during development or after errors.
  """
  def clear_cache do
    case Cachex.keys(:sleeper_cache) do
      {:ok, keys} ->
        sleeper_keys = Enum.filter(keys, &String.starts_with?(&1, "sleeper:"))
        Enum.each(sleeper_keys, &Cachex.del(:sleeper_cache, &1))
        {:ok, length(sleeper_keys)}
      
      {:error, reason} ->
        Logger.error("Failed to clear cache: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp should_retry({:ok, %Tesla.Env{status: status}}) when status in [429, 500, 502, 503, 504], do: true
  defp should_retry({:ok, %Tesla.Env{}}), do: false
  defp should_retry({:error, _}), do: true

  defp get_all_players_direct do
    case get("/players/nfl") do
      {:ok, %Tesla.Env{status: 200, body: players}} ->
        {:ok, players}
      
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp get_league_direct(league_id) do
    case get("/league/#{league_id}") do
      {:ok, %Tesla.Env{status: 200, body: league}} ->
        {:ok, league}
      
      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :league_not_found}
      
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp get_league_users_direct(league_id) do
    case get("/league/#{league_id}/users") do
      {:ok, %Tesla.Env{status: 200, body: users}} ->
        {:ok, users}
      
      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :league_not_found}
      
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp get_league_rosters_direct(league_id) do
    case get("/league/#{league_id}/rosters") do
      {:ok, %Tesla.Env{status: 200, body: rosters}} ->
        {:ok, rosters}
      
      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :league_not_found}
      
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp get_league_matchups_direct(league_id, week) do
    case get("/league/#{league_id}/matchups/#{week}") do
      {:ok, %Tesla.Env{status: 200, body: matchups}} ->
        {:ok, matchups}
      
      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :matchups_not_found}
      
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp get_nfl_state_direct do
    case get("/state/nfl") do
      {:ok, %Tesla.Env{status: 200, body: state}} ->
        {:ok, state}
      
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}
      
      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp get_trending_players_direct(trend_type) do
    case get("/players/nfl/trending/#{trend_type}") do
      {:ok, %Tesla.Env{status: 200, body: trending_data}} ->
        {:ok, trending_data}
      
      {:ok, %Tesla.Env{status: 404}} ->
        {:error, "Trending data not found"}
      
      {:ok, %Tesla.Env{status: 429}} ->
        {:error, "API rate limit exceeded"}
      
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "API error: #{status}"}
      
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  # Simple heuristic to determine if we're in NFL season
  # Could be enhanced to check actual NFL state
  defp in_season? do
    now = DateTime.utc_now()
    # NFL season roughly September through February
    now.month >= 9 or now.month <= 2
  end
end