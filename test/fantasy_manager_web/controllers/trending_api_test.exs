defmodule FantasyManagerWeb.Controllers.TrendingApiTest do
  use FantasyManagerWeb.ConnCase, async: true

  describe "GET /api/v1/trending/players" do
    test "returns 200 with list of trending players", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/trending/players")
      
      assert %{
        "data" => players,
        "meta" => %{
          "total" => _total,
          "page" => 1,
          "per_page" => 20,
          "retrieved_at" => _,
          "cache_expires_at" => _
        }
      } = json_response(conn, 200)
      
      assert is_list(players)
      
      # Verify player structure if any exist
      if length(players) > 0 do
        player = hd(players)
        assert %{
          "id" => _,
          "player_id" => _,
          "player_name" => _,
          "position" => _,
          "team" => _,
          "trend_type" => trend_type,
          "trend_count" => count,
          "retrieved_at" => _,
          "week" => _,
          "season" => _
        } = player
        
        assert trend_type in ["add", "drop"]
        assert is_integer(count) and count >= 0
      end
    end

    test "supports trend_type filtering", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/trending/players?trend_type=add")
      
      assert %{"data" => players} = json_response(conn, 200)
      
      # All returned players should have "add" trend type
      Enum.each(players, fn player ->
        assert player["trend_type"] == "add"
      end)
    end

    test "supports position filtering", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/trending/players?position=QB")
      
      assert %{"data" => players} = json_response(conn, 200)
      
      # All returned players should be QBs
      Enum.each(players, fn player ->
        assert player["position"] == "QB"
      end)
    end

    test "supports week and season filtering", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/trending/players?week=8&season=2024")
      
      assert %{"data" => players} = json_response(conn, 200)
      
      # All returned players should be from week 8, season 2024
      Enum.each(players, fn player ->
        assert player["week"] == 8
        assert player["season"] == 2024
      end)
    end

    test "supports pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/trending/players?page=2&per_page=5")
      
      assert %{
        "data" => players,
        "meta" => %{
          "page" => 2,
          "per_page" => 5
        }
      } = json_response(conn, 200)
      
      assert length(players) <= 5
    end

    test "returns cached data with appropriate headers", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/trending/players")
      
      assert %{
        "meta" => %{
          "cache_expires_at" => expires_at
        }
      } = json_response(conn, 200)
      
      assert is_binary(expires_at)
      assert get_resp_header(conn, "cache-control") != []
    end
  end

  describe "GET /api/v1/trending/players/:player_id/history" do
    test "returns trending history for specific player", %{conn: conn} do
      player_id = "test_player_123"
      
      conn = get(conn, ~p"/api/v1/trending/players/#{player_id}/history")
      
      assert %{
        "data" => %{
          "player_id" => ^player_id,
          "player_name" => _,
          "position" => _,
          "team" => _,
          "history" => history
        },
        "meta" => %{
          "total_entries" => _,
          "weeks_tracked" => _
        }
      } = json_response(conn, 200)
      
      assert is_list(history)
      
      # Verify history entry structure if any exist
      if length(history) > 0 do
        entry = hd(history)
        assert %{
          "week" => _,
          "season" => _,
          "trend_type" => trend_type,
          "trend_count" => count,
          "retrieved_at" => _
        } = entry
        
        assert trend_type in ["add", "drop"]
        assert is_integer(count) and count >= 0
      end
    end

    test "supports date range filtering", %{conn: conn} do
      player_id = "test_player_123"
      
      conn = get(conn, ~p"/api/v1/trending/players/#{player_id}/history?start_week=1&end_week=8&season=2024")
      
      assert %{
        "data" => %{
          "history" => history
        }
      } = json_response(conn, 200)
      
      # All history entries should be within the specified range
      Enum.each(history, fn entry ->
        assert entry["week"] >= 1
        assert entry["week"] <= 8
        assert entry["season"] == 2024
      end)
    end

    test "supports trend_type filtering", %{conn: conn} do
      player_id = "test_player_123"
      
      conn = get(conn, ~p"/api/v1/trending/players/#{player_id}/history?trend_type=add")
      
      assert %{
        "data" => %{
          "history" => history
        }
      } = json_response(conn, 200)
      
      # All history entries should be "add" trends
      Enum.each(history, fn entry ->
        assert entry["trend_type"] == "add"
      end)
    end

    test "returns 404 for non-existent player", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/trending/players/non_existent_player/history")
      
      assert %{"error" => "Player not found"} = json_response(conn, 404)
    end

    test "returns empty history for player with no trending data", %{conn: conn} do
      player_id = "player_no_data"
      
      conn = get(conn, ~p"/api/v1/trending/players/#{player_id}/history")
      
      assert %{
        "data" => %{
          "history" => []
        },
        "meta" => %{
          "total_entries" => 0
        }
      } = json_response(conn, 200)
    end
  end

  describe "POST /api/v1/trending/sync" do
    test "syncs trending data from Sleeper API", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => 8,
        "season" => 2024
      })
      
      assert %{
        "data" => %{
          "sync_status" => "completed",
          "players_synced" => count,
          "sync_time" => sync_time,
          "week" => 8,
          "season" => 2024,
          "trend_type" => "add"
        }
      } = json_response(conn, 200)
      
      assert is_integer(count) and count >= 0
      assert is_binary(sync_time)
    end

    test "syncs both add and drop trends when trend_type not specified", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/trending/sync", %{
        "week" => 8,
        "season" => 2024
      })
      
      assert %{
        "data" => %{
          "sync_status" => "completed",
          "add_players_synced" => add_count,
          "drop_players_synced" => drop_count
        }
      } = json_response(conn, 200)
      
      assert is_integer(add_count) and add_count >= 0
      assert is_integer(drop_count) and drop_count >= 0
    end

    test "returns 400 for invalid parameters", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "invalid",
        "week" => 8
      })
      
      assert %{"error" => "Invalid parameters"} = json_response(conn, 400)
    end

    test "returns 400 for missing required parameters", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add"
      })
      
      assert %{"error" => "Missing required parameters"} = json_response(conn, 400)
    end

    test "returns 503 when Sleeper API is unavailable", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => 8,
        "season" => 2024,
        "force_api_failure" => true  # Test parameter to simulate API failure
      })
      
      assert %{"error" => "External API unavailable"} = json_response(conn, 503)
    end

    test "handles rate limiting from Sleeper API", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => 8,
        "season" => 2024,
        "force_rate_limit" => true  # Test parameter to simulate rate limiting
      })
      
      assert %{"error" => "API rate limit exceeded"} = json_response(conn, 429)
    end
  end
end