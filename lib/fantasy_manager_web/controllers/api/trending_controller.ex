defmodule FantasyManagerWeb.Api.TrendingController do
  @moduledoc """
  API controller for trending players endpoints.
  
  Handles:
  - GET /api/v1/trending/players - Get trending players
  - GET /api/v1/trending/players/:player_id/history - Get trending history for a player
  - POST /api/v1/trending/sync - Sync trending data from Sleeper API
  """
  
  use FantasyManagerWeb, :controller
  
  alias FantasyManager.Fantasy.TrendingPlayerData
  alias FantasyManager.External.SleeperClient
  
  require Ash.Query
  import Ash.Expr
  
  action_fallback FantasyManagerWeb.Api.FallbackController

  @doc """
  GET /api/v1/trending/players
  
  Retrieves trending players data.
  
  Query parameters:
  - trend_type: Filter by trend type (add, drop)
  - position: Filter by position (QB, RB, WR, TE, K, DEF)
  - week: Filter by specific week
  - season: Filter by specific season
  - page: Page number for pagination (default: 1)
  - per_page: Results per page (default: 20, max: 100)
  """
  def index(conn, params) do
    with {:ok, {trending_players, meta}} <- get_trending_players(params) do
      conn
      |> add_cache_headers()
      |> put_status(:ok)
      |> json(%{
        data: format_trending_players(trending_players),
        meta: enhance_meta_with_cache_info(meta)
      })
    end
  end

  @doc """
  GET /api/v1/trending/players/:player_id/history
  
  Retrieves trending history for a specific player.
  
  Query parameters:
  - trend_type: Filter by trend type (add, drop)
  - start_week: Start week for date range
  - end_week: End week for date range
  - season: Season to filter by (default: current season)
  """
  def history(conn, %{"player_id" => player_id} = params) do
    with {:ok, {player_history, meta}} <- get_player_trending_history(player_id, params) do
      conn
      |> put_status(:ok)
      |> json(%{
        data: format_player_history(player_id, player_history),
        meta: meta
      })
    end
  end

  @doc """
  POST /api/v1/trending/sync
  
  Syncs trending data from Sleeper API.
  
  Body parameters:
  - trend_type: Type to sync (add, drop) - optional, syncs both if not specified
  - week: Week to sync for (default: current week)
  - season: Season to sync for (default: current season)
  """
  def sync(conn, params) do
    week = parse_integer(params["week"], get_current_week())
    season = parse_integer(params["season"], get_current_season())
    trend_type = params["trend_type"]
    
    case sync_trending_data(trend_type, week, season) do
      {:ok, sync_result} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: sync_result
        })
      
      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "External API unavailable",
          detail: inspect(reason)
        })
    end
  end

  # Private functions
  
  defp get_trending_players(params) do
    # Parse query parameters
    trend_type = params["trend_type"]
    position_filter = params["position"]
    week_filter = parse_integer(params["week"], nil)
    season_filter = parse_integer(params["season"], nil)
    page = parse_integer(params["page"], 1)
    per_page = min(parse_integer(params["per_page"], 20), 100)
    
    # Build query
    query = TrendingPlayerData
    |> Ash.Query.sort(trend_count: :desc, retrieved_at: :desc)
    
    # Apply filters
    query = if trend_type do
      Ash.Query.filter(query, trend_type == ^trend_type)
    else
      query
    end
    
    query = if position_filter do
      Ash.Query.filter(query, position == ^position_filter)
    else
      query
    end
    
    query = if week_filter do
      Ash.Query.filter(query, week == ^week_filter)
    else
      query
    end
    
    query = if season_filter do
      Ash.Query.filter(query, season == ^season_filter)
    else
      query
    end
    
    # Apply pagination
    offset = (page - 1) * per_page
    paginated_query = query
    |> Ash.Query.limit(per_page)
    |> Ash.Query.offset(offset)
    
    case Ash.read(paginated_query) do
      {:ok, trending_players} ->
        # Get total count for pagination metadata
        case Ash.count(query) do
          {:ok, total_count} ->
            meta = %{
              total: total_count,
              page: page,
              per_page: per_page,
              total_pages: div(total_count + per_page - 1, per_page)
            }
            {:ok, {trending_players, meta}}
          
          {:error, reason} ->
            {:error, :internal_error, "Count query failed: #{inspect(reason)}"}
        end
      
      {:error, reason} ->
        {:error, :internal_error, "Query failed: #{inspect(reason)}"}
    end
  end
  
  defp get_player_trending_history(player_id, params) do
    # Parse query parameters
    trend_type = params["trend_type"]
    start_week = parse_integer(params["start_week"], nil)
    end_week = parse_integer(params["end_week"], nil)
    season = parse_integer(params["season"], get_current_season())
    
    # Check if player exists in trending data
    case TrendingPlayerData
         |> Ash.Query.filter(player_id == ^player_id)
         |> Ash.Query.limit(1)
         |> Ash.read() do
      {:ok, []} ->
        {:error, :not_found, "Player not found"}
      
      {:ok, _} ->
        # Build history query
        query = TrendingPlayerData
        |> Ash.Query.filter(player_id == ^player_id and season == ^season)
        |> Ash.Query.sort(week: :desc, retrieved_at: :desc)
        
        # Apply filters
        query = if trend_type do
          Ash.Query.filter(query, trend_type == ^trend_type)
        else
          query
        end
        
        query = if start_week do
          Ash.Query.filter(query, week >= ^start_week)
        else
          query
        end
        
        query = if end_week do
          Ash.Query.filter(query, week <= ^end_week)
        else
          query
        end
        
        case Ash.read(query) do
          {:ok, history} ->
            total_entries = length(history)
            weeks_tracked = history |> Enum.map(&(&1.week)) |> Enum.uniq() |> length()
            
            meta = %{
              total_entries: total_entries,
              weeks_tracked: weeks_tracked
            }
            
            {:ok, {history, meta}}
          
          {:error, reason} ->
            {:error, :internal_error, "History query failed: #{inspect(reason)}"}
        end
      
      {:error, reason} ->
        {:error, :internal_error, "Player lookup failed: #{inspect(reason)}"}
    end
  end
  
  defp sync_trending_data(nil, week, season) do
    # Sync both add and drop trends
    with {:ok, add_result} <- sync_single_trend_type("add", week, season),
         {:ok, drop_result} <- sync_single_trend_type("drop", week, season) do
      {:ok, %{
        sync_status: "completed",
        add_players_synced: add_result.players_synced,
        drop_players_synced: drop_result.players_synced,
        sync_time: NaiveDateTime.utc_now(),
        week: week,
        season: season
      }}
    end
  end
  
  defp sync_trending_data(trend_type, week, season) when trend_type in ["add", "drop"] do
    case sync_single_trend_type(trend_type, week, season) do
      {:ok, result} ->
        {:ok, %{
          sync_status: "completed",
          players_synced: result.players_synced,
          sync_time: NaiveDateTime.utc_now(),
          week: week,
          season: season,
          trend_type: trend_type
        }}
      
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp sync_trending_data(trend_type, _week, _season) do
    {:error, "Invalid trend_type: #{trend_type}. Must be 'add' or 'drop'"}
  end
  
  defp sync_single_trend_type(trend_type, week, season) do
    case SleeperClient.get_trending_players(trend_type) do
      {:ok, trending_data} ->
        # Get player info to enrich trending data
        case SleeperClient.get_all_players() do
          {:ok, all_players} ->
            players_synced = sync_trending_to_database(trending_data, all_players, trend_type, week, season)
            {:ok, %{players_synced: players_synced}}
          
          {:error, reason} ->
            {:error, "Failed to get player info: #{inspect(reason)}"}
        end
      
      {:error, "API rate limit exceeded"} ->
        {:error, "API rate limit exceeded"}
      
      {:error, reason} ->
        {:error, "Failed to get trending data: #{inspect(reason)}"}
    end
  end
  
  defp sync_trending_to_database(trending_data, all_players, trend_type, week, season) do
    retrieved_at = NaiveDateTime.utc_now()
    
    synced_count = trending_data
    |> Enum.map(fn 
      {player_id, trend_count} when is_binary(player_id) and is_integer(trend_count) ->
        player_info = Map.get(all_players, player_id, %{})
        player_name = Map.get(player_info, "full_name", "Unknown Player")
        position = Map.get(player_info, "position")
        team = Map.get(player_info, "team")
        {player_id, trend_count, player_name, position, team}
      
      %{"player_id" => player_id, "count" => trend_count} ->
        player_info = Map.get(all_players, player_id, %{})
        player_name = Map.get(player_info, "full_name", "Unknown Player")
        position = Map.get(player_info, "position")
        team = Map.get(player_info, "team")
        {player_id, trend_count, player_name, position, team}
      
      _ -> 
        nil
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.map(fn {player_id, trend_count, player_name, position, team} ->
      
      # Only sync if we have position info
      if position do
        attrs = %{
          player_id: player_id,
          player_name: player_name,
          position: position,
          team: team,
          trend_type: trend_type,
          trend_count: trend_count,
          retrieved_at: retrieved_at,
          week: week,
          season: season
        }
        
        case TrendingPlayerData.create(attrs) do
          {:ok, _trending_player} -> 1
          {:error, %Ash.Error.Invalid{errors: errors}} ->
            # Check if it's a uniqueness constraint violation (already exists)
            if Enum.any?(errors, fn error -> error.class == :invalid and String.contains?(to_string(error.message), "unique") end) do
              # Try to update instead
              case update_existing_trending_data(player_id, trend_type, week, season, trend_count, retrieved_at) do
                {:ok, _} -> 1
                {:error, _} -> 0
              end
            else
              0
            end
          {:error, _reason} -> 0
        end
      else
        0
      end
    end)
    |> Enum.sum()
    
    synced_count
  end
  
  defp update_existing_trending_data(player_id, trend_type, week, season, new_count, retrieved_at) do
    case TrendingPlayerData
         |> Ash.Query.filter(player_id == ^player_id and trend_type == ^trend_type and week == ^week and season == ^season)
         |> Ash.read_one() do
      {:ok, existing} ->
        TrendingPlayerData.update(existing, %{
          trend_count: new_count,
          retrieved_at: retrieved_at
        })
      
      {:ok, nil} -> {:error, "Record not found"}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp format_trending_players(trending_players) do
    Enum.map(trending_players, &format_trending_player/1)
  end
  
  defp format_trending_player(trending_player) do
    %{
      id: trending_player.id,
      player_id: trending_player.player_id,
      player_name: trending_player.player_name,
      position: trending_player.position,
      team: trending_player.team,
      trend_type: trending_player.trend_type,
      trend_count: trending_player.trend_count,
      retrieved_at: trending_player.retrieved_at,
      week: trending_player.week,
      season: trending_player.season
    }
  end
  
  defp format_player_history(player_id, history) do
    if length(history) > 0 do
      first_entry = hd(history)
      
      %{
        player_id: player_id,
        player_name: first_entry.player_name,
        position: first_entry.position,
        team: first_entry.team,
        history: Enum.map(history, fn entry ->
          %{
            week: entry.week,
            season: entry.season,
            trend_type: entry.trend_type,
            trend_count: entry.trend_count,
            retrieved_at: entry.retrieved_at
          }
        end)
      }
    else
      %{
        player_id: player_id,
        player_name: "Unknown",
        position: nil,
        team: nil,
        history: []
      }
    end
  end
  
  defp add_cache_headers(conn) do
    conn
    |> put_resp_header("cache-control", "public, max-age=900") # 15 minutes
    |> put_resp_header("expires", cache_expires_header())
  end
  
  defp enhance_meta_with_cache_info(meta) do
    Map.merge(meta, %{
      retrieved_at: NaiveDateTime.utc_now(),
      cache_expires_at: NaiveDateTime.add(NaiveDateTime.utc_now(), 900, :second) # 15 minutes
    })
  end
  
  defp cache_expires_header do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(900, :second) # 15 minutes
    |> NaiveDateTime.to_iso8601()
  end
  
  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
  
  defp parse_integer(value, default) when is_integer(value) and value > 0, do: value
  defp parse_integer(_, default), do: default
  
  defp get_current_week, do: 8  # Mock current week
  defp get_current_season, do: 2024  # Mock current season
end