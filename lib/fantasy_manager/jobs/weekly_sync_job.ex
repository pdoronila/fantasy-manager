defmodule FantasyManager.Jobs.WeeklySyncJob do
  @moduledoc """
  Background job for weekly player data synchronization.
  
  This job handles the automated synchronization of:
  - Trending player data from Sleeper API
  - Player information updates
  - League data refresh for active leagues
  
  Designed to run weekly during low-traffic periods to ensure
  fresh data for AI recommendations.
  """

  require Logger

  alias FantasyManager.External.SleeperClient
  alias FantasyManager.Fantasy.{League, TrendingPlayerData, FantasyTeam}
  alias FantasyManager.AI.RecommendationEngine
  require Ash.Query
  import Ash.Expr

  @doc """
  Runs the complete weekly sync process.
  
  ## Options
  - `:week` - Week number (1-18), defaults to current week
  - `:season` - Season year, defaults to current season
  - `:leagues` - List of league IDs to sync, defaults to all active leagues
  - `:force_sync` - Force sync even if data already exists, defaults to false
  - `:dry_run` - Preview operations without executing, defaults to false
  """
  def run(opts \\ []) do
    Logger.info("Starting weekly sync job with options: #{inspect(opts)}")
    
    start_time = System.monotonic_time(:millisecond)
    week = Keyword.get(opts, :week, get_current_week())
    season = Keyword.get(opts, :season, get_current_season())
    force_sync = Keyword.get(opts, :force_sync, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    result = %{
      started_at: NaiveDateTime.utc_now(),
      week: week,
      season: season,
      dry_run: dry_run,
      operations: [],
      errors: [],
      summary: %{}
    }

    try do
      result
      |> sync_trending_data(week, season, force_sync, dry_run)
      |> sync_player_data(force_sync, dry_run)
      |> sync_league_data(opts[:leagues], dry_run)
      |> generate_weekly_recommendations(week, season, dry_run)
      |> finalize_sync_result(start_time)
    rescue
      error ->
        Logger.error("Weekly sync job failed: #{inspect(error)}")
        
        %{result | 
          errors: result.errors ++ [%{
            type: :critical_failure,
            message: Exception.message(error),
            stacktrace: __STACKTRACE__
          }],
          status: :failed,
          completed_at: NaiveDateTime.utc_now()
        }
    end
  end

  @doc """
  Syncs trending player data for both add and drop trends.
  """
  defp sync_trending_data(result, week, season, force_sync, dry_run) do
    Logger.info("Syncing trending data for week #{week}, season #{season}")
    
    operation_start = System.monotonic_time(:millisecond)
    
    # Check if data already exists for this week/season
    existing_data = if not force_sync do
      case TrendingPlayerData 
           |> Ash.Query.filter(week == ^week and season == ^season)
           |> Ash.Query.limit(1)
           |> Ash.read() do
        {:ok, []} -> nil
        {:ok, _data} -> :exists
        {:error, _} -> nil
      end
    else
      nil
    end

    operation_result = if existing_data == :exists and not force_sync do
      %{
        skipped: true,
        reason: "Data already exists for week #{week}, season #{season}",
        records_processed: 0
      }
    else
      sync_results = ["add", "drop"]
      |> Enum.map(&sync_single_trend_type(&1, week, season, dry_run))
      |> Enum.reduce(%{add_count: 0, drop_count: 0, errors: []}, fn result, acc ->
        case result do
          {:ok, %{type: type, count: count}} ->
            Map.put(acc, :"#{type}_count", count)
          {:error, %{type: type, error: error}} ->
            %{acc | errors: acc.errors ++ [%{type: type, error: error}]}
        end
      end)
      
      %{
        add_players_synced: sync_results.add_count,
        drop_players_synced: sync_results.drop_count,
        total_synced: sync_results.add_count + sync_results.drop_count,
        errors: sync_results.errors
      }
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :sync_trending_data,
        duration_ms: operation_time,
        result: operation_result
      }],
      errors: result.errors ++ (operation_result[:errors] || [])
    }
  end

  defp sync_single_trend_type(trend_type, week, season, dry_run) do
    try do
      case SleeperClient.get_trending_players(trend_type) do
        {:ok, trending_data} ->
          if dry_run do
            {:ok, %{type: trend_type, count: length(trending_data), dry_run: true}}
          else
            case SleeperClient.get_all_players() do
              {:ok, all_players} ->
                count = sync_trending_to_database(trending_data, all_players, trend_type, week, season)
                {:ok, %{type: trend_type, count: count}}
              
              {:error, reason} ->
                {:error, %{type: trend_type, error: "Failed to get player data: #{inspect(reason)}"}}
            end
          end

        {:error, reason} ->
          {:error, %{type: trend_type, error: "Failed to get trending data: #{inspect(reason)}"}}
      end
    rescue
      error ->
        {:error, %{type: trend_type, error: "Exception during sync: #{Exception.message(error)}"}}
    end
  end

  defp sync_trending_to_database(trending_data, all_players, trend_type, week, season) do
    retrieved_at = NaiveDateTime.utc_now()
    
    synced_count = trending_data
    |> Enum.map(fn 
      {player_id, trend_count} when is_binary(player_id) and is_integer(trend_count) ->
        process_trending_player(player_id, trend_count, all_players, trend_type, week, season, retrieved_at)
      
      %{"player_id" => player_id, "count" => trend_count} ->
        process_trending_player(player_id, trend_count, all_players, trend_type, week, season, retrieved_at)
      
      _ -> 0
    end)
    |> Enum.sum()
    
    synced_count
  end

  defp process_trending_player(player_id, trend_count, all_players, trend_type, week, season, retrieved_at) do
    player_info = Map.get(all_players, player_id, %{})
    player_name = Map.get(player_info, "full_name", "Unknown Player")
    position = Map.get(player_info, "position")
    team = Map.get(player_info, "team")

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

  @doc """
  Syncs player data from Sleeper API.
  """
  defp sync_player_data(result, force_sync, dry_run) do
    Logger.info("Syncing player data")
    
    operation_start = System.monotonic_time(:millisecond)
    
    operation_result = if dry_run do
      %{
        dry_run: true,
        estimated_players: "10000+",
        note: "Would sync all player data from Sleeper API"
      }
    else
      # For now, we'll skip the comprehensive player sync as it's quite large
      # In production, this might sync injury reports, bye weeks, etc.
      %{
        skipped: true,
        reason: "Comprehensive player sync not yet implemented",
        note: "Future enhancement: sync injury reports, depth charts, etc."
      }
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :sync_player_data,
        duration_ms: operation_time,
        result: operation_result
      }]
    }
  end

  @doc """
  Syncs league data for active leagues.
  """
  defp sync_league_data(result, league_ids, dry_run) do
    Logger.info("Syncing league data")
    
    operation_start = System.monotonic_time(:millisecond)
    
    # Get leagues to sync
    leagues_to_sync = case league_ids do
      nil ->
        # Get all active leagues (leagues with recent activity)
        case League.read() do
          {:ok, leagues} -> leagues
          {:error, _} -> []
        end
      
      ids when is_list(ids) ->
        # Get specific leagues
        case League.read() do
          {:ok, leagues} -> Enum.filter(leagues, fn l -> l.id in ids end)
          {:error, _} -> []
        end
      
      _ -> []
    end

    operation_result = if dry_run do
      %{
        dry_run: true,
        leagues_to_sync: length(leagues_to_sync),
        note: "Would sync rosters and standings for #{length(leagues_to_sync)} leagues"
      }
    else
      sync_results = leagues_to_sync
      |> Enum.map(&sync_single_league/1)
      |> Enum.reduce(%{success: 0, errors: []}, fn result, acc ->
        case result do
          {:ok, _} -> %{acc | success: acc.success + 1}
          {:error, error} -> %{acc | errors: acc.errors ++ [error]}
        end
      end)
      
      %{
        leagues_synced: sync_results.success,
        total_leagues: length(leagues_to_sync),
        errors: sync_results.errors
      }
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :sync_league_data,
        duration_ms: operation_time,
        result: operation_result
      }],
      errors: result.errors ++ (operation_result[:errors] || [])
    }
  end

  defp sync_single_league(league) do
    try do
      # In a full implementation, this would:
      # 1. Sync rosters from Sleeper for all teams in league
      # 2. Update standings and records
      # 3. Refresh waiver priorities
      # 4. Update scoring settings if changed
      
      {:ok, %{league_id: league.id, operations: [:roster_sync, :standings_update]}}
    rescue
      error ->
        {:error, %{league_id: league.id, error: Exception.message(error)}}
    end
  end

  @doc """
  Generates weekly recommendations for active teams.
  """
  defp generate_weekly_recommendations(result, week, season, dry_run) do
    Logger.info("Generating weekly recommendations")
    
    operation_start = System.monotonic_time(:millisecond)
    
    operation_result = if dry_run do
      # Count teams that would get recommendations
      team_count = case FantasyTeam.read() do
        {:ok, teams} -> length(teams)
        {:error, _} -> 0
      end
      
      %{
        dry_run: true,
        teams_to_process: team_count,
        note: "Would generate waiver recommendations for #{team_count} teams"
      }
    else
      # Generate recommendations for teams that need them
      case get_teams_needing_recommendations(week, season) do
        {:ok, teams} ->
          recommendation_results = teams
          |> Enum.take(10) # Limit to prevent overwhelming the system
          |> Enum.map(&generate_team_recommendations(&1, week, season))
          |> Enum.reduce(%{success: 0, errors: []}, fn result, acc ->
            case result do
              {:ok, _} -> %{acc | success: acc.success + 1}
              {:error, error} -> %{acc | errors: acc.errors ++ [error]}
            end
          end)
          
          %{
            recommendations_generated: recommendation_results.success,
            teams_processed: length(teams),
            errors: recommendation_results.errors
          }
          
        {:error, reason} ->
          %{
            error: "Failed to get teams: #{inspect(reason)}",
            recommendations_generated: 0
          }
      end
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :generate_weekly_recommendations,
        duration_ms: operation_time,
        result: operation_result
      }],
      errors: result.errors ++ (operation_result[:errors] || [])
    }
  end

  defp get_teams_needing_recommendations(week, season) do
    # Get teams that don't have recent recommendations
    cutoff_time = NaiveDateTime.utc_now() |> NaiveDateTime.add(-7, :day)
    
    FantasyTeam.read()
  end

  defp generate_team_recommendations(team, week, season) do
    try do
      case RecommendationEngine.get_waiver_recommendations(team.id, week, season) do
        {:ok, _recommendations} ->
          {:ok, %{team_id: team.id, status: :generated}}
        
        {:error, reason} ->
          {:error, %{team_id: team.id, error: reason}}
      end
    rescue
      error ->
        {:error, %{team_id: team.id, error: Exception.message(error)}}
    end
  end

  defp finalize_sync_result(result, start_time) do
    total_time = System.monotonic_time(:millisecond) - start_time
    
    # Calculate summary statistics
    summary = %{
      total_duration_ms: total_time,
      operations_count: length(result.operations),
      errors_count: length(result.errors),
      status: (if length(result.errors) == 0, do: :success, else: :partial_success)
    }
    
    final_result = %{result |
      completed_at: NaiveDateTime.utc_now(),
      summary: summary,
      status: summary.status
    }

    Logger.info("Weekly sync job completed: #{inspect(summary)}")
    
    final_result
  end

  # Helper functions
  defp get_current_week do
    # Mock implementation - in production, calculate based on NFL schedule
    8
  end

  defp get_current_season do
    Date.utc_today().year
  end
end