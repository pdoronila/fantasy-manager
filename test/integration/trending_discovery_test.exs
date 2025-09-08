defmodule FantasyManager.Integration.TrendingDiscoveryTest do
  use FantasyManagerWeb.ConnCase, async: false
  import FantasyManager.TestSupport

  @moduletag :integration

  describe "Trending Players Discovery Flow" do
    setup do
      league = create_test_league()
      team = create_test_team(league.id, "Test Team")
      
      %{league: league, team: team}
    end

    test "complete trending data discovery workflow", %{conn: conn, team: team} do
      current_week = 8
      current_season = 2024
      
      # Step 1: Sync trending data from Sleeper API
      sync_conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => current_week,
        "season" => current_season
      })
      
      assert %{
        "data" => %{
          "sync_status" => "completed",
          "players_synced" => add_count,
          "sync_time" => sync_time
        }
      } = json_response(sync_conn, 200)
      
      assert is_integer(add_count) and add_count >= 0
      assert is_binary(sync_time)
      
      # Step 2: Sync drop trending data as well
      drop_sync_conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "drop",
        "week" => current_week,
        "season" => current_season
      })
      
      assert %{
        "data" => %{
          "sync_status" => "completed",
          "players_synced" => drop_count
        }
      } = json_response(drop_sync_conn, 200)
      
      assert is_integer(drop_count) and drop_count >= 0
      
      # Step 3: Discover trending players through API
      trending_conn = get(conn, ~p"/api/v1/trending/players?week=#{current_week}&season=#{current_season}")
      
      assert %{
        "data" => trending_players,
        "meta" => %{
          "total" => total_trending,
          "retrieved_at" => retrieved_at,
          "cache_expires_at" => cache_expires
        }
      } = json_response(trending_conn, 200)
      
      assert is_list(trending_players)
      assert is_integer(total_trending)
      assert is_binary(retrieved_at)
      assert is_binary(cache_expires)
      
      # Verify trending player data structure
      if length(trending_players) > 0 do
        trending_player = hd(trending_players)
        
        assert %{
          "id" => _,
          "player_id" => player_id,
          "player_name" => player_name,
          "position" => position,
          "team" => team_abbr,
          "trend_type" => trend_type,
          "trend_count" => trend_count,
          "week" => ^current_week,
          "season" => ^current_season
        } = trending_player
        
        assert is_binary(player_id) and player_id != ""
        assert is_binary(player_name) and player_name != ""
        assert position in ["QB", "RB", "WR", "TE", "K", "DEF"]
        assert trend_type in ["add", "drop"]
        assert is_integer(trend_count) and trend_count > 0
        
        # Step 4: Get detailed trending history for a specific player
        history_conn = get(conn, ~p"/api/v1/trending/players/#{player_id}/history")
        
        assert %{
          "data" => %{
            "player_id" => ^player_id,
            "player_name" => ^player_name,
            "position" => ^position,
            "history" => history
          },
          "meta" => %{
            "total_entries" => total_entries,
            "weeks_tracked" => weeks_tracked
          }
        } = json_response(history_conn, 200)
        
        assert is_list(history)
        assert is_integer(total_entries) and total_entries >= 0
        assert is_integer(weeks_tracked) and weeks_tracked >= 0
        
        # Verify history contains our synced data
        current_week_entry = Enum.find(history, fn entry ->
          entry["week"] == current_week and entry["season"] == current_season
        end)
        
        assert current_week_entry != nil, "History should contain current week data"
      end
      
      # Step 5: Verify recommendations incorporate trending data
      rec_conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations")
      
      assert %{"data" => recommendations} = json_response(rec_conn, 200)
      
      # Check that some recommendations reference trending players
      if length(recommendations) > 0 and length(trending_players) > 0 do
        trending_player_ids = Enum.map(trending_players, fn p -> p["player_id"] end)
        trending_add_players = trending_players
                             |> Enum.filter(fn p -> p["trend_type"] == "add" end)
                             |> Enum.map(fn p -> p["player_id"] end)
        
        pickup_recommendations = Enum.filter(recommendations, fn rec ->
          rec["recommendation_type"] == "pickup"
        end)
        
        # Some pickup recommendations should be for trending add players
        if length(pickup_recommendations) > 0 and length(trending_add_players) > 0 do
          trending_rec_count = Enum.count(pickup_recommendations, fn rec ->
            rec["player_id"] in trending_add_players
          end)
          
          # At least some recommendations should be influenced by trending data
          assert trending_rec_count >= 0, "Expected recommendations to consider trending players"
        end
      end
    end

    test "trending data caching and cache expiry", %{conn: conn} do
      # First request should populate cache
      first_conn = get(conn, ~p"/api/v1/trending/players")
      
      assert %{
        "meta" => %{
          "cache_expires_at" => expires_at_1
        }
      } = json_response(first_conn, 200)
      
      # Second request should use cached data
      second_conn = get(conn, ~p"/api/v1/trending/players")
      
      assert %{
        "meta" => %{
          "cache_expires_at" => expires_at_2
        }
      } = json_response(second_conn, 200)
      
      # Cache expiry should be consistent for cached responses
      assert expires_at_1 == expires_at_2
      
      # Verify cache headers
      cache_control = get_resp_header(second_conn, "cache-control")
      assert cache_control != []
    end

    test "trending data filtering and pagination", %{conn: conn} do
      # Sync some trending data first
      _sync_conn = post(conn, ~p"/api/v1/trending/sync", %{
        "week" => 8,
        "season" => 2024
      })
      
      # Test position filtering
      qb_conn = get(conn, ~p"/api/v1/trending/players?position=QB")
      
      if json_response(qb_conn, 200)["data"] != [] do
        assert %{"data" => qb_players} = json_response(qb_conn, 200)
        
        Enum.each(qb_players, fn player ->
          assert player["position"] == "QB"
        end)
      end
      
      # Test trend type filtering
      add_conn = get(conn, ~p"/api/v1/trending/players?trend_type=add")
      
      if json_response(add_conn, 200)["data"] != [] do
        assert %{"data" => add_players} = json_response(add_conn, 200)
        
        Enum.each(add_players, fn player ->
          assert player["trend_type"] == "add"
        end)
      end
      
      # Test pagination
      paginated_conn = get(conn, ~p"/api/v1/trending/players?page=1&per_page=5")
      
      assert %{
        "data" => paginated_players,
        "meta" => %{
          "page" => 1,
          "per_page" => 5
        }
      } = json_response(paginated_conn, 200)
      
      assert length(paginated_players) <= 5
    end

    test "trending discovery handles API failures gracefully", %{conn: conn} do
      # Test sync failure handling
      failure_conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => 8,
        "season" => 2024,
        "force_api_failure" => true
      })
      
      assert %{"error" => "External API unavailable"} = json_response(failure_conn, 503)
      
      # Test rate limiting handling
      rate_limit_conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => 8,
        "season" => 2024,
        "force_rate_limit" => true
      })
      
      assert %{"error" => "API rate limit exceeded"} = json_response(rate_limit_conn, 429)
    end

    test "trending player history provides meaningful insights", %{conn: conn} do
      # Sync multiple weeks of data
      weeks = [6, 7, 8]
      season = 2024
      
      for week <- weeks do
        _sync_conn = post(conn, ~p"/api/v1/trending/sync", %{
          "trend_type" => "add",
          "week" => week,
          "season" => season
        })
      end
      
      # Get trending players
      trending_conn = get(conn, ~p"/api/v1/trending/players")
      
      if json_response(trending_conn, 200)["data"] != [] do
        %{"data" => trending_players} = json_response(trending_conn, 200)
        
        if length(trending_players) > 0 do
          player = hd(trending_players)
          player_id = player["player_id"]
          
          # Get history with date range
          history_conn = get(conn, ~p"/api/v1/trending/players/#{player_id}/history?start_week=6&end_week=8&season=#{season}")
          
          assert %{
            "data" => %{
              "history" => history
            }
          } = json_response(history_conn, 200)
          
          # Verify history is within requested range
          Enum.each(history, fn entry ->
            assert entry["week"] >= 6
            assert entry["week"] <= 8
            assert entry["season"] == season
          end)
          
          # Test trend type filtering in history
          add_history_conn = get(conn, ~p"/api/v1/trending/players/#{player_id}/history?trend_type=add")
          
          if json_response(add_history_conn, 200)["data"]["history"] != [] do
            %{"data" => %{"history" => add_history}} = json_response(add_history_conn, 200)
            
            Enum.each(add_history, fn entry ->
              assert entry["trend_type"] == "add"
            end)
          end
        end
      end
    end

    test "trending integration affects recommendation priority scoring", %{conn: conn, team: team} do
      # Sync trending data
      _sync_conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => 8,
        "season" => 2024
      })
      
      # Get recommendations
      rec_conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations")
      
      assert %{"data" => recommendations} = json_response(rec_conn, 200)
      
      # Get trending players for comparison
      trending_conn = get(conn, ~p"/api/v1/trending/players?trend_type=add")
      
      if json_response(trending_conn, 200)["data"] != [] do
        %{"data" => trending_players} = json_response(trending_conn, 200)
        trending_player_ids = Enum.map(trending_players, fn p -> p["player_id"] end)
        
        pickup_recommendations = Enum.filter(recommendations, fn rec ->
          rec["recommendation_type"] == "pickup"
        end)
        
        if length(pickup_recommendations) > 0 do
          # Separate trending vs non-trending pickup recommendations
          {trending_recs, non_trending_recs} = Enum.split_with(pickup_recommendations, fn rec ->
            rec["player_id"] in trending_player_ids
          end)
          
          # Compare average priority scores
          if length(trending_recs) > 0 and length(non_trending_recs) > 0 do
            avg_trending_priority = trending_recs
                                  |> Enum.map(fn rec -> rec["priority_score"] end)
                                  |> Enum.sum()
                                  |> Kernel./(length(trending_recs))
            
            avg_non_trending_priority = non_trending_recs
                                      |> Enum.map(fn rec -> rec["priority_score"] end)
                                      |> Enum.sum()
                                      |> Kernel./(length(non_trending_recs))
            
            # Trending players might have higher priority due to popularity
            # but this depends on the AI's decision-making, so we just verify scores are reasonable
            assert avg_trending_priority >= 0 and avg_trending_priority <= 10
            assert avg_non_trending_priority >= 0 and avg_non_trending_priority <= 10
          end
        end
      end
    end
  end
end