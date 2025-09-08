defmodule FantasyManager.Jobs.CleanupJob do
  @moduledoc """
  Background job for cleaning up expired and stale data.
  
  This job handles the automated cleanup of:
  - Expired trending player data (older than configurable threshold)
  - Old waiver recommendations that are no longer relevant
  - Cache entries for inactive leagues
  - Orphaned temporary data
  
  Designed to run daily to maintain database performance and
  keep storage usage under control.
  """

  require Logger

  alias FantasyManager.Fantasy.{TrendingPlayerData, WaiverRecommendation, League, FantasyTeam}
  require Ash.Query
  import Ash.Expr

  # Configuration constants
  @default_trending_data_retention_days 30
  @default_recommendation_retention_days 14
  @default_inactive_league_threshold_days 90
  @default_batch_size 1000

  @doc """
  Runs the complete cleanup process.
  
  ## Options
  - `:trending_retention_days` - Days to keep trending data, defaults to 30
  - `:recommendation_retention_days` - Days to keep recommendations, defaults to 14
  - `:inactive_league_days` - Days to consider a league inactive, defaults to 90
  - `:batch_size` - Number of records to process per batch, defaults to 1000
  - `:dry_run` - Preview operations without executing, defaults to false
  """
  def run(opts \\ []) do
    Logger.info("Starting cleanup job with options: #{inspect(opts)}")
    
    start_time = System.monotonic_time(:millisecond)
    trending_retention = Keyword.get(opts, :trending_retention_days, @default_trending_data_retention_days)
    recommendation_retention = Keyword.get(opts, :recommendation_retention_days, @default_recommendation_retention_days)
    inactive_threshold = Keyword.get(opts, :inactive_league_days, @default_inactive_league_threshold_days)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    dry_run = Keyword.get(opts, :dry_run, false)

    result = %{
      started_at: NaiveDateTime.utc_now(),
      dry_run: dry_run,
      operations: [],
      errors: [],
      summary: %{}
    }

    try do
      result
      |> cleanup_expired_trending_data(trending_retention, batch_size, dry_run)
      |> cleanup_old_recommendations(recommendation_retention, batch_size, dry_run)
      |> cleanup_inactive_league_data(inactive_threshold, dry_run)
      |> cleanup_orphaned_data(batch_size, dry_run)
      |> optimize_database_performance(dry_run)
      |> finalize_cleanup_result(start_time)
    rescue
      error ->
        Logger.error("Cleanup job failed: #{inspect(error)}")
        
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
  Cleans up trending data older than the retention period.
  """
  defp cleanup_expired_trending_data(result, retention_days, batch_size, dry_run) do
    Logger.info("Cleaning up trending data older than #{retention_days} days")
    
    operation_start = System.monotonic_time(:millisecond)
    cutoff_date = NaiveDateTime.utc_now() |> NaiveDateTime.add(-retention_days, :day)
    
    operation_result = if dry_run do
      # Count records that would be deleted
      case TrendingPlayerData
           |> Ash.Query.filter(retrieved_at < ^cutoff_date)
           |> Ash.count() do
        {:ok, count} ->
          %{
            dry_run: true,
            records_to_delete: count,
            cutoff_date: cutoff_date,
            estimated_batches: div(count + batch_size - 1, batch_size)
          }
        
        {:error, reason} ->
          %{error: "Failed to count trending data: #{inspect(reason)}"}
      end
    else
      delete_trending_data_in_batches(cutoff_date, batch_size)
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :cleanup_expired_trending_data,
        duration_ms: operation_time,
        result: operation_result
      }],
      errors: result.errors ++ (if operation_result[:error], do: [operation_result[:error]], else: [])
    }
  end

  defp delete_trending_data_in_batches(cutoff_date, batch_size) do
    total_deleted = 0
    batch_count = 0
    errors = []

    delete_batch_result = delete_trending_batch(cutoff_date, batch_size, total_deleted, batch_count, errors)
    
    %{
      records_deleted: delete_batch_result.total_deleted,
      batches_processed: delete_batch_result.batch_count,
      errors: delete_batch_result.errors
    }
  end

  defp delete_trending_batch(cutoff_date, batch_size, total_deleted, batch_count, errors) do
    case TrendingPlayerData
         |> Ash.Query.filter(retrieved_at < ^cutoff_date)
         |> Ash.Query.limit(batch_size)
         |> Ash.read() do
      {:ok, records} when length(records) == 0 ->
        # No more records to delete
        %{total_deleted: total_deleted, batch_count: batch_count, errors: errors}
      
      {:ok, records} ->
        # Delete this batch
        delete_results = records
        |> Enum.map(&TrendingPlayerData.destroy/1)
        |> Enum.reduce(%{deleted: 0, errors: []}, fn result, acc ->
          case result do
            {:ok, _} -> %{acc | deleted: acc.deleted + 1}
            {:error, error} -> %{acc | errors: acc.errors ++ [error]}
          end
        end)
        
        new_total = total_deleted + delete_results.deleted
        new_errors = errors ++ delete_results.errors
        
        if length(records) < batch_size do
          # This was the last batch
          %{total_deleted: new_total, batch_count: batch_count + 1, errors: new_errors}
        else
          # Continue with next batch
          delete_trending_batch(cutoff_date, batch_size, new_total, batch_count + 1, new_errors)
        end
      
      {:error, reason} ->
        %{total_deleted: total_deleted, batch_count: batch_count, errors: errors ++ [reason]}
    end
  end

  @doc """
  Cleans up old waiver recommendations.
  """
  defp cleanup_old_recommendations(result, retention_days, batch_size, dry_run) do
    Logger.info("Cleaning up recommendations older than #{retention_days} days")
    
    operation_start = System.monotonic_time(:millisecond)
    cutoff_date = NaiveDateTime.utc_now() |> NaiveDateTime.add(-retention_days, :day)
    
    operation_result = if dry_run do
      # Count recommendations that would be deleted/archived
      cases = [
        {:expired, WaiverRecommendation |> Ash.Query.filter(expires_at < ^NaiveDateTime.utc_now())},
        {:old_applied, WaiverRecommendation |> Ash.Query.filter(status == "applied" and generated_at < ^cutoff_date)},
        {:old_dismissed, WaiverRecommendation |> Ash.Query.filter(status == "dismissed" and generated_at < ^cutoff_date)}
      ]
      
      counts = cases
      |> Enum.map(fn {type, query} ->
        case Ash.count(query) do
          {:ok, count} -> {type, count}
          {:error, _} -> {type, 0}
        end
      end)
      |> Enum.into(%{})
      
      %{
        dry_run: true,
        expired_recommendations: counts[:expired] || 0,
        old_applied_recommendations: counts[:old_applied] || 0,
        old_dismissed_recommendations: counts[:old_dismissed] || 0,
        total_to_clean: (counts[:expired] || 0) + (counts[:old_applied] || 0) + (counts[:old_dismissed] || 0)
      }
    else
      cleanup_recommendation_categories(cutoff_date, batch_size)
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :cleanup_old_recommendations,
        duration_ms: operation_time,
        result: operation_result
      }],
      errors: result.errors ++ (operation_result[:errors] || [])
    }
  end

  defp cleanup_recommendation_categories(cutoff_date, batch_size) do
    now = NaiveDateTime.utc_now()
    
    # Clean expired recommendations
    expired_result = cleanup_recommendations_by_query(
      WaiverRecommendation |> Ash.Query.filter(expires_at < ^now),
      batch_size,
      :expired
    )
    
    # Clean old applied recommendations
    applied_result = cleanup_recommendations_by_query(
      WaiverRecommendation |> Ash.Query.filter(status == "applied" and generated_at < ^cutoff_date),
      batch_size,
      :old_applied
    )
    
    # Clean old dismissed recommendations
    dismissed_result = cleanup_recommendations_by_query(
      WaiverRecommendation |> Ash.Query.filter(status == "dismissed" and generated_at < ^cutoff_date),
      batch_size,
      :old_dismissed
    )
    
    %{
      expired_deleted: expired_result.deleted,
      applied_deleted: applied_result.deleted,
      dismissed_deleted: dismissed_result.deleted,
      total_deleted: expired_result.deleted + applied_result.deleted + dismissed_result.deleted,
      errors: expired_result.errors ++ applied_result.errors ++ dismissed_result.errors
    }
  end

  defp cleanup_recommendations_by_query(query, batch_size, category) do
    case Ash.read(query |> Ash.Query.limit(batch_size)) do
      {:ok, recommendations} ->
        delete_results = recommendations
        |> Enum.map(&WaiverRecommendation.destroy/1)
        |> Enum.reduce(%{deleted: 0, errors: []}, fn result, acc ->
          case result do
            {:ok, _} -> %{acc | deleted: acc.deleted + 1}
            {:error, error} -> %{acc | errors: acc.errors ++ [%{category: category, error: error}]}
          end
        end)
        
        if length(recommendations) == batch_size do
          # There might be more, continue recursively
          next_result = cleanup_recommendations_by_query(query, batch_size, category)
          %{
            deleted: delete_results.deleted + next_result.deleted,
            errors: delete_results.errors ++ next_result.errors
          }
        else
          delete_results
        end
      
      {:error, reason} ->
        %{deleted: 0, errors: [%{category: category, error: reason}]}
    end
  end

  @doc """
  Cleans up data related to inactive leagues.
  """
  defp cleanup_inactive_league_data(result, inactive_threshold_days, dry_run) do
    Logger.info("Cleaning up inactive league data older than #{inactive_threshold_days} days")
    
    operation_start = System.monotonic_time(:millisecond)
    
    operation_result = if dry_run do
      %{
        dry_run: true,
        note: "Would identify and clean data for leagues inactive for #{inactive_threshold_days}+ days",
        operations: [
          "Clear cached data for inactive leagues",
          "Archive old league statistics",
          "Remove temporary league data"
        ]
      }
    else
      # For now, this is a placeholder for future league cleanup logic
      # In production, this might:
      # - Clear cached roster data for leagues that haven't been accessed
      # - Archive old league settings and rules
      # - Clean up temporary league analysis data
      
      %{
        leagues_analyzed: 0,
        cache_entries_cleared: 0,
        note: "Inactive league cleanup not yet implemented"
      }
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :cleanup_inactive_league_data,
        duration_ms: operation_time,
        result: operation_result
      }]
    }
  end

  @doc """
  Cleans up orphaned and temporary data.
  """
  defp cleanup_orphaned_data(result, batch_size, dry_run) do
    Logger.info("Cleaning up orphaned data")
    
    operation_start = System.monotonic_time(:millisecond)
    
    operation_result = if dry_run do
      %{
        dry_run: true,
        checks_to_perform: [
          "Recommendations without valid teams",
          "Trending data for non-existent players",
          "Temporary AI analysis results",
          "Expired cache entries"
        ],
        note: "Would identify and clean orphaned records"
      }
    else
      orphan_results = %{
        recommendations_cleaned: cleanup_orphaned_recommendations(batch_size),
        trending_cleaned: cleanup_orphaned_trending_data(batch_size),
        temp_data_cleaned: cleanup_temporary_data()
      }
      
      %{
        total_orphans_cleaned: 
          orphan_results.recommendations_cleaned + 
          orphan_results.trending_cleaned + 
          orphan_results.temp_data_cleaned,
        breakdown: orphan_results
      }
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :cleanup_orphaned_data,
        duration_ms: operation_time,
        result: operation_result
      }]
    }
  end

  defp cleanup_orphaned_recommendations(batch_size) do
    # Find recommendations for teams that no longer exist
    # This is a placeholder - would need to join with team existence checks
    0
  end

  defp cleanup_orphaned_trending_data(batch_size) do
    # Find trending data for players that are no longer valid
    # This is a placeholder - would need player validation logic
    0
  end

  defp cleanup_temporary_data do
    # Clean up any temporary analysis results, cached computations, etc.
    # This is a placeholder for future temporary data cleanup
    0
  end

  @doc """
  Performs database optimization tasks.
  """
  defp optimize_database_performance(result, dry_run) do
    Logger.info("Optimizing database performance")
    
    operation_start = System.monotonic_time(:millisecond)
    
    operation_result = if dry_run do
      %{
        dry_run: true,
        optimizations: [
          "VACUUM ANALYZE on trending_player_data",
          "VACUUM ANALYZE on waiver_recommendations", 
          "Update table statistics",
          "Check for unused indexes"
        ],
        note: "Would perform database maintenance tasks"
      }
    else
      # In production, this might run database maintenance commands
      # For now, just log that optimization would occur
      %{
        tables_optimized: 0,
        indexes_analyzed: 0,
        note: "Database optimization not yet implemented"
      }
    end

    operation_time = System.monotonic_time(:millisecond) - operation_start

    %{result | 
      operations: result.operations ++ [%{
        name: :optimize_database_performance,
        duration_ms: operation_time,
        result: operation_result
      }]
    }
  end

  defp finalize_cleanup_result(result, start_time) do
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

    Logger.info("Cleanup job completed: #{inspect(summary)}")
    
    final_result
  end
end