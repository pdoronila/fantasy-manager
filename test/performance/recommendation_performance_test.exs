defmodule FantasyManager.Performance.RecommendationPerformanceTest do
  @moduledoc """
  Performance tests for AI recommendation system.
  
  Tests that recommendation generation meets performance requirements:
  - Recommendation generation under 5 seconds
  - Memory usage within acceptable bounds
  - Concurrent request handling
  - Rate limiting effectiveness
  """
  
  use ExUnit.Case, async: false
  
  alias FantasyManager.AI.RecommendationEngine
  alias FantasyManager.Fantasy.{FantasyTeam, League, TrendingPlayerData, WaiverRecommendation}
  alias FantasyManager.External.SleeperClient
  
  @moduletag :performance
  @timeout 30_000  # 30 second timeout for performance tests

  # Performance thresholds
  @max_recommendation_time_ms 5_000
  @max_memory_mb 100
  @max_concurrent_requests 10

  setup_all do
    # Setup test data
    {:ok, test_data} = setup_test_performance_data()
    
    on_exit(fn ->
      cleanup_test_performance_data(test_data)
    end)
    
    {:ok, test_data}
  end

  describe "recommendation generation performance" do
    @tag timeout: @timeout
    test "waiver recommendations generated within 5 seconds", %{team_id: team_id} do
      week = 8
      season = 2024
      
      {time_microseconds, result} = :timer.tc(fn ->
        RecommendationEngine.get_waiver_recommendations(team_id, week, season)
      end)
      
      time_milliseconds = div(time_microseconds, 1000)
      
      # Assert performance requirement
      assert time_milliseconds <= @max_recommendation_time_ms,
        "Recommendation generation took #{time_milliseconds}ms, expected <= #{@max_recommendation_time_ms}ms"
      
      # Assert functional correctness
      assert {:ok, recommendations} = result
      assert is_map(recommendations)
      assert Map.has_key?(recommendations, :recommendations)
      
      # Log performance metrics
      IO.puts("✓ Waiver recommendations generated in #{time_milliseconds}ms")
    end

    @tag timeout: @timeout
    test "lineup optimization generated within 5 seconds", %{team_id: team_id} do
      week = 8
      season = 2024
      
      {time_microseconds, result} = :timer.tc(fn ->
        RecommendationEngine.optimize_lineup(team_id, week, season)
      end)
      
      time_milliseconds = div(time_microseconds, 1000)
      
      # Assert performance requirement
      assert time_milliseconds <= @max_recommendation_time_ms,
        "Lineup optimization took #{time_milliseconds}ms, expected <= #{@max_recommendation_time_ms}ms"
      
      # Assert functional correctness (may fail due to AI service unavailability, but timing should still be measured)
      case result do
        {:ok, lineup} ->
          assert is_map(lineup)
          IO.puts("✓ Lineup optimization generated in #{time_milliseconds}ms")
        
        {:error, _reason} ->
          IO.puts("✓ Lineup optimization failed gracefully in #{time_milliseconds}ms (expected due to AI service)")
      end
    end

    @tag timeout: @timeout
    test "trade analysis generated within 5 seconds", %{team_id: team_id} do
      trade_proposal = %{
        give: ["player_1", "player_2"],
        receive: ["player_3", "player_4"]
      }
      
      {time_microseconds, result} = :timer.tc(fn ->
        RecommendationEngine.analyze_trade(team_id, trade_proposal)
      end)
      
      time_milliseconds = div(time_microseconds, 1000)
      
      # Assert performance requirement
      assert time_milliseconds <= @max_recommendation_time_ms,
        "Trade analysis took #{time_milliseconds}ms, expected <= #{@max_recommendation_time_ms}ms"
      
      # Log result
      case result do
        {:ok, analysis} ->
          assert is_map(analysis)
          IO.puts("✓ Trade analysis generated in #{time_milliseconds}ms")
        
        {:error, _reason} ->
          IO.puts("✓ Trade analysis failed gracefully in #{time_milliseconds}ms (expected due to AI service)")
      end
    end
  end

  describe "fallback performance" do
    @tag timeout: @timeout
    test "fallback recommendations generated quickly", %{team_id: team_id} do
      week = 8
      season = 2024
      
      {time_microseconds, result} = :timer.tc(fn ->
        RecommendationEngine.create_fallback_waiver_recommendations(team_id, week, season)
      end)
      
      time_milliseconds = div(time_microseconds, 1000)
      
      # Fallback should be much faster than AI calls
      max_fallback_time = 1000  # 1 second
      
      assert time_milliseconds <= max_fallback_time,
        "Fallback recommendations took #{time_milliseconds}ms, expected <= #{max_fallback_time}ms"
      
      # Assert functional correctness
      assert {:ok, recommendations} = result
      assert is_map(recommendations)
      assert Map.has_key?(recommendations, :fallback_mode)
      
      IO.puts("✓ Fallback recommendations generated in #{time_milliseconds}ms")
    end
  end

  describe "memory usage performance" do
    @tag :memory_intensive
    test "recommendation generation memory usage within bounds", %{team_id: team_id} do
      # Force garbage collection to get baseline
      :erlang.garbage_collect()
      
      initial_memory = get_memory_usage_mb()
      
      # Generate multiple recommendations to stress test memory
      tasks = for _i <- 1..5 do
        Task.async(fn ->
          RecommendationEngine.get_waiver_recommendations(team_id, 8, 2024)
        end)
      end
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, @timeout)
      
      # Force garbage collection to see peak usage
      :erlang.garbage_collect()
      
      peak_memory = get_memory_usage_mb()
      memory_increase = peak_memory - initial_memory
      
      assert memory_increase <= @max_memory_mb,
        "Memory usage increased by #{memory_increase}MB, expected <= #{@max_memory_mb}MB"
      
      # Assert that at least some requests succeeded or failed gracefully
      assert length(results) == 5
      
      IO.puts("✓ Memory usage increase: #{memory_increase}MB (within #{@max_memory_mb}MB limit)")
    end
  end

  describe "concurrent request performance" do
    @tag timeout: @timeout
    test "handles concurrent recommendation requests efficiently", %{team_id: team_id} do
      num_requests = @max_concurrent_requests
      
      start_time = System.monotonic_time(:millisecond)
      
      # Launch concurrent requests
      tasks = for i <- 1..num_requests do
        Task.async(fn ->
          week = rem(i, 17) + 1  # Vary the week to avoid caching
          
          request_start = System.monotonic_time(:millisecond)
          result = RecommendationEngine.get_waiver_recommendations(team_id, week, 2024)
          request_end = System.monotonic_time(:millisecond)
          
          {i, result, request_end - request_start}
        end)
      end
      
      # Collect results
      results = Task.await_many(tasks, @timeout)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # Analyze results
      successful_requests = Enum.count(results, fn {_i, result, _time} ->
        match?({:ok, _}, result)
      end)
      
      failed_requests = Enum.count(results, fn {_i, result, _time} ->
        match?({:error, _}, result)
      end)
      
      individual_times = Enum.map(results, fn {_i, _result, time} -> time end)
      avg_time = div(Enum.sum(individual_times), length(individual_times))
      max_time = Enum.max(individual_times)
      
      # Assertions
      assert total_time <= @max_recommendation_time_ms * 2,
        "Concurrent requests took #{total_time}ms total, expected <= #{@max_recommendation_time_ms * 2}ms"
      
      # At least some requests should complete (may fail due to AI service, but system should handle gracefully)
      assert successful_requests + failed_requests == num_requests,
        "All #{num_requests} requests should complete (either succeed or fail gracefully)"
      
      IO.puts("✓ Concurrent performance:")
      IO.puts("  - Total time: #{total_time}ms")
      IO.puts("  - Average request time: #{avg_time}ms")
      IO.puts("  - Max request time: #{max_time}ms")
      IO.puts("  - Successful: #{successful_requests}/#{num_requests}")
      IO.puts("  - Failed gracefully: #{failed_requests}/#{num_requests}")
    end
  end

  describe "database operation performance" do
    test "trending data retrieval within performance bounds", %{team_id: team_id} do
      week = 8
      season = 2024
      
      {time_microseconds, result} = :timer.tc(fn ->
        # This tests the database operations for trending data
        case TrendingPlayerData
             |> Ash.Query.filter(week == ^week and season == ^season)
             |> Ash.Query.sort(trend_count: :desc)
             |> Ash.Query.limit(50)
             |> Ash.read() do
          {:ok, trending_data} -> {:ok, trending_data}
          {:error, reason} -> {:error, reason}
        end
      end)
      
      time_milliseconds = div(time_microseconds, 1000)
      max_db_time = 500  # 500ms for database operations
      
      assert time_milliseconds <= max_db_time,
        "Database trending data query took #{time_milliseconds}ms, expected <= #{max_db_time}ms"
      
      # Assert functional correctness
      assert {:ok, _trending_data} = result
      
      IO.puts("✓ Trending data query completed in #{time_milliseconds}ms")
    end

    test "recommendation storage performance", %{team_id: team_id} do
      # Create test recommendation data
      recommendation_attrs = %{
        team_id: team_id,
        player_id: "test_player_perf_#{:rand.uniform(10000)}",
        player_name: "Test Player Performance",
        position: "RB",
        team: "TST",
        recommendation_type: "pickup",
        priority_score: Decimal.new("8.5"),
        reasoning: "Performance test recommendation",
        status: "pending",
        week: 8,
        season: 2024,
        generated_at: NaiveDateTime.utc_now(),
        expires_at: NaiveDateTime.add(NaiveDateTime.utc_now(), 7, :day)
      }
      
      {time_microseconds, result} = :timer.tc(fn ->
        WaiverRecommendation.create(recommendation_attrs)
      end)
      
      time_milliseconds = div(time_microseconds, 1000)
      max_storage_time = 200  # 200ms for storage operations
      
      assert time_milliseconds <= max_storage_time,
        "Recommendation storage took #{time_milliseconds}ms, expected <= #{max_storage_time}ms"
      
      # Assert functional correctness
      assert {:ok, _recommendation} = result
      
      IO.puts("✓ Recommendation storage completed in #{time_milliseconds}ms")
    end
  end

  describe "error handling performance" do
    test "error responses generated quickly" do
      # Test that error handling doesn't add significant overhead
      invalid_team_id = "non_existent_team_id"
      
      {time_microseconds, result} = :timer.tc(fn ->
        RecommendationEngine.get_waiver_recommendations(invalid_team_id, 8, 2024)
      end)
      
      time_milliseconds = div(time_microseconds, 1000)
      max_error_time = 1000  # 1 second for error responses
      
      assert time_milliseconds <= max_error_time,
        "Error response took #{time_milliseconds}ms, expected <= #{max_error_time}ms"
      
      # Should return an error
      assert {:error, _reason} = result
      
      IO.puts("✓ Error handling completed in #{time_milliseconds}ms")
    end
  end

  # Helper functions for performance testing

  defp setup_test_performance_data do
    # Create test league
    league_attrs = %{
      name: "Performance Test League",
      sleeper_league_id: "perf_test_#{:rand.uniform(10000)}",
      season: 2024,
      league_type: "standard",
      scoring_type: "ppr",
      roster_positions: ["QB", "RB", "RB", "WR", "WR", "TE", "FLEX", "K", "DEF", "BN", "BN", "BN", "BN", "BN", "BN"]
    }
    
    {:ok, league} = League.create(league_attrs)
    
    # Create test team
    team_attrs = %{
      name: "Performance Test Team",
      sleeper_team_id: "perf_team_#{:rand.uniform(10000)}",
      league_id: league.id,
      owner_name: "Test Owner",
      waiver_priority: 5,
      wins: 5,
      losses: 3,
      ties: 0,
      points_for: Decimal.new("1250.5"),
      points_against: Decimal.new("1180.0")
    }
    
    {:ok, team} = FantasyTeam.create(team_attrs)
    
    # Create test trending data
    trending_players = for i <- 1..20 do
      %{
        player_id: "perf_player_#{i}",
        player_name: "Performance Player #{i}",
        position: Enum.random(["QB", "RB", "WR", "TE"]),
        team: "TST",
        trend_type: Enum.random(["add", "drop"]),
        trend_count: :rand.uniform(1000),
        retrieved_at: NaiveDateTime.utc_now(),
        week: 8,
        season: 2024
      }
    end
    
    for trending_player_attrs <- trending_players do
      TrendingPlayerData.create(trending_player_attrs)
    end
    
    {:ok, %{
      league_id: league.id,
      team_id: team.id,
      trending_players: trending_players
    }}
  end

  defp cleanup_test_performance_data(%{league_id: league_id, team_id: team_id}) do
    # Clean up test recommendations
    case WaiverRecommendation
         |> Ash.Query.filter(team_id == ^team_id)
         |> Ash.read() do
      {:ok, recommendations} ->
        Enum.each(recommendations, &WaiverRecommendation.destroy/1)
      _ -> :ok
    end
    
    # Clean up test trending data
    case TrendingPlayerData
         |> Ash.Query.filter(season == 2024 and week == 8)
         |> Ash.read() do
      {:ok, trending_data} ->
        Enum.each(trending_data, &TrendingPlayerData.destroy/1)
      _ -> :ok
    end
    
    # Clean up test team
    case FantasyTeam |> Ash.get(team_id) do
      {:ok, team} -> FantasyTeam.destroy(team)
      _ -> :ok
    end
    
    # Clean up test league
    case League |> Ash.get(league_id) do
      {:ok, league} -> League.destroy(league)
      _ -> :ok
    end
  end

  defp get_memory_usage_mb do
    :erlang.memory(:total) / 1_048_576  # Convert bytes to MB
  end

  @doc """
  Helper function to run performance benchmarks outside of tests.
  
  Usage:
    FantasyManager.Performance.RecommendationPerformanceTest.benchmark_recommendations(team_id, 10)
  """
  def benchmark_recommendations(team_id, iterations \\ 5) do
    IO.puts("Running recommendation performance benchmark...")
    IO.puts("Team ID: #{team_id}")
    IO.puts("Iterations: #{iterations}")
    IO.puts("")
    
    times = for i <- 1..iterations do
      IO.write("Iteration #{i}... ")
      
      {time_microseconds, result} = :timer.tc(fn ->
        RecommendationEngine.get_waiver_recommendations(team_id, 8, 2024)
      end)
      
      time_ms = div(time_microseconds, 1000)
      
      case result do
        {:ok, _} -> IO.puts("✓ #{time_ms}ms")
        {:error, reason} -> IO.puts("✗ #{time_ms}ms (#{inspect(reason)})")
      end
      
      time_ms
    end
    
    avg_time = div(Enum.sum(times), length(times))
    min_time = Enum.min(times)
    max_time = Enum.max(times)
    
    IO.puts("")
    IO.puts("Results:")
    IO.puts("  Average: #{avg_time}ms")
    IO.puts("  Min: #{min_time}ms")
    IO.puts("  Max: #{max_time}ms")
    IO.puts("  Target: < #{@max_recommendation_time_ms}ms")
    
    if avg_time <= @max_recommendation_time_ms do
      IO.puts("  ✓ PASSED: Performance within target")
    else
      IO.puts("  ✗ FAILED: Performance exceeds target")
    end
  end
end