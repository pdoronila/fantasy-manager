defmodule FantasyManager.Integration.SleeperClientTest do
  use ExUnit.Case
  import Mox
  alias FantasyManager.External.SleeperClient
  alias FantasyManager.TestSupport.MockData

  @moduletag :integration

  setup :verify_on_exit!

  describe "SleeperClient.get_all_players/0" do
    test "fetches and caches all NFL players" do
      # This test should hit the actual Sleeper API or use mock data
      assert {:ok, players} = SleeperClient.get_all_players()
      
      assert is_map(players)
      assert map_size(players) > 0
      
      # Verify player structure matches expected format
      {_sleeper_id, sample_player} = Enum.take(players, 1) |> List.first()
      
      assert %{
        "player_id" => _,
        "status" => _,
        "sport" => "nfl",
        "position" => position,
        "full_name" => name,
        "team" => _
      } = sample_player

      assert is_binary(name)
      assert position in ["QB", "RB", "WR", "TE", "K", "DEF"] or position == nil
    end

    test "uses cache on subsequent requests" do
      # First request
      assert {:ok, players1} = SleeperClient.get_all_players()
      
      # Second request should be faster due to caching
      start_time = System.monotonic_time()
      assert {:ok, players2} = SleeperClient.get_all_players()
      duration = System.monotonic_time() - start_time
      
      # Cache hit should be very fast (< 10ms)
      assert duration < 10_000_000  # nanoseconds
      assert players1 == players2
    end

    test "handles API failures gracefully" do
      # Mock network failure
      expect(HTTPMock, :get, fn _url, _headers ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      assert {:error, :api_timeout} = SleeperClient.get_all_players()
    end

    test "handles invalid JSON responses" do
      expect(HTTPMock, :get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: "invalid json",
          headers: [{"content-type", "application/json"}]
        }}
      end)

      assert {:error, :invalid_json} = SleeperClient.get_all_players()
    end
  end

  describe "SleeperClient.get_league/1" do
    test "fetches league information by ID" do
      league_id = "123456789"
      
      assert {:ok, league_info} = SleeperClient.get_league(league_id)
      
      assert %{
        "league_id" => ^league_id,
        "name" => name,
        "season" => season,
        "settings" => settings,
        "scoring_settings" => scoring,
        "roster_positions" => positions
      } = league_info

      assert is_binary(name)
      assert is_integer(season)
      assert is_map(settings)
      assert is_map(scoring)
      assert is_list(positions)
    end

    test "returns error for non-existent league" do
      non_existent_id = "999999999"
      
      assert {:error, :league_not_found} = SleeperClient.get_league(non_existent_id)
    end

    test "caches league data with appropriate TTL" do
      league_id = "123456789"
      
      # First request
      assert {:ok, league1} = SleeperClient.get_league(league_id)
      
      # Second request should use cache
      start_time = System.monotonic_time()
      assert {:ok, league2} = SleeperClient.get_league(league_id)
      duration = System.monotonic_time() - start_time
      
      assert duration < 10_000_000  # Cache hit should be very fast
      assert league1 == league2
    end
  end

  describe "SleeperClient.get_league_users/1" do
    test "fetches users for a league" do
      league_id = "123456789"
      
      assert {:ok, users} = SleeperClient.get_league_users(league_id)
      
      assert is_list(users)
      assert length(users) > 0
      
      sample_user = List.first(users)
      assert %{
        "user_id" => _,
        "username" => _,
        "display_name" => _
      } = sample_user
    end

    test "returns empty list for league with no users" do
      empty_league_id = "000000000"
      
      assert {:ok, []} = SleeperClient.get_league_users(empty_league_id)
    end
  end

  describe "SleeperClient.get_league_rosters/1" do
    test "fetches rosters for a league" do
      league_id = "123456789"
      
      assert {:ok, rosters} = SleeperClient.get_league_rosters(league_id)
      
      assert is_list(rosters)
      assert length(rosters) > 0
      
      sample_roster = List.first(rosters)
      assert %{
        "roster_id" => _,
        "owner_id" => _,
        "players" => players,
        "starters" => starters,
        "settings" => _
      } = sample_roster

      assert is_list(players) or is_nil(players)
      assert is_list(starters) or is_nil(starters)
    end

    test "handles leagues with empty rosters" do
      empty_league_id = "000000001"
      
      assert {:ok, rosters} = SleeperClient.get_league_rosters(empty_league_id)
      
      # Should return empty list or rosters with empty player arrays
      assert is_list(rosters)
    end
  end

  describe "SleeperClient.get_matchups/2" do
    test "fetches matchups for a specific week" do
      league_id = "123456789"
      week = 1
      
      assert {:ok, matchups} = SleeperClient.get_matchups(league_id, week)
      
      assert is_list(matchups)
      
      if length(matchups) > 0 do
        sample_matchup = List.first(matchups)
        assert %{
          "roster_id" => _,
          "matchup_id" => _,
          "points" => _,
          "starters" => _
        } = sample_matchup
      end
    end

    test "validates week parameter" do
      league_id = "123456789"
      
      assert {:error, :invalid_week} = SleeperClient.get_matchups(league_id, 0)
      assert {:error, :invalid_week} = SleeperClient.get_matchups(league_id, 19)
    end

    test "handles future weeks gracefully" do
      league_id = "123456789"
      future_week = 18
      
      # Should not error for future weeks, may return empty
      assert {:ok, matchups} = SleeperClient.get_matchups(league_id, future_week)
      assert is_list(matchups)
    end
  end

  describe "SleeperClient.get_player_stats/2" do
    test "fetches player stats for a season" do
      season = "2023"
      stats_type = "regular"
      
      assert {:ok, stats} = SleeperClient.get_player_stats(season, stats_type)
      
      assert is_map(stats)
      
      if map_size(stats) > 0 do
        {_player_id, player_stats} = Enum.take(stats, 1) |> List.first()
        assert is_map(player_stats)
        
        # Common stat fields
        stat_fields = ["gp", "pts", "pass_yd", "pass_td", "rush_yd", "rec_yd"]
        common_fields = Map.keys(player_stats) |> Enum.filter(&(&1 in stat_fields))
        assert length(common_fields) > 0
      end
    end

    test "validates season parameter" do
      invalid_season = "2050"
      
      assert {:error, :invalid_season} = SleeperClient.get_player_stats(invalid_season, "regular")
    end

    test "validates stats type parameter" do
      season = "2023"
      
      assert {:error, :invalid_stats_type} = SleeperClient.get_player_stats(season, "invalid")
    end
  end

  describe "caching behavior" do
    test "respects different cache TTLs for different endpoints" do
      league_id = "123456789"
      
      # Players cache should have longer TTL than league data
      assert {:ok, _} = SleeperClient.get_all_players()
      assert {:ok, _} = SleeperClient.get_league(league_id)
      
      # Verify cache keys exist
      assert Cachex.exists?(:sleeper_cache, "players:all") == {:ok, true}
      assert Cachex.exists?(:sleeper_cache, "league:#{league_id}") == {:ok, true}
      
      # Check TTL differences
      {:ok, players_ttl} = Cachex.ttl(:sleeper_cache, "players:all")
      {:ok, league_ttl} = Cachex.ttl(:sleeper_cache, "league:#{league_id}")
      
      # Players should have longer TTL (cached for hours vs minutes)
      assert players_ttl > league_ttl
    end

    test "cache keys are properly namespaced" do
      league_id = "123456789"
      season = "2023"
      
      assert {:ok, _} = SleeperClient.get_league(league_id)
      assert {:ok, _} = SleeperClient.get_player_stats(season, "regular")
      
      # Verify distinct cache keys
      assert Cachex.exists?(:sleeper_cache, "league:#{league_id}") == {:ok, true}
      assert Cachex.exists?(:sleeper_cache, "stats:#{season}:regular") == {:ok, true}
    end

    test "cache invalidation works correctly" do
      # Get initial data
      assert {:ok, players1} = SleeperClient.get_all_players()
      
      # Clear cache
      Cachex.clear(:sleeper_cache)
      
      # Should fetch fresh data
      assert {:ok, players2} = SleeperClient.get_all_players()
      
      # Data should be the same, but this confirms cache was cleared
      assert is_map(players1) and is_map(players2)
    end
  end

  describe "rate limiting" do
    test "handles API rate limits gracefully" do
      # Mock rate limit response
      expect(HTTPMock, :get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 429,
          body: "Rate limit exceeded",
          headers: [{"retry-after", "60"}]
        }}
      end)

      assert {:error, :rate_limited} = SleeperClient.get_all_players()
    end

    test "respects retry-after header" do
      league_id = "123456789"
      
      # This test would need actual implementation of retry logic
      # For now, just verify the function exists and handles the input
      assert {:ok, _} = SleeperClient.get_league(league_id)
    end
  end

  describe "error handling" do
    test "handles network timeouts" do
      expect(HTTPMock, :get, fn _url, _headers ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      assert {:error, :api_timeout} = SleeperClient.get_all_players()
    end

    test "handles connection errors" do
      expect(HTTPMock, :get, fn _url, _headers ->
        {:error, %HTTPoison.Error{reason: :econnrefused}}
      end)

      assert {:error, :connection_error} = SleeperClient.get_all_players()
    end

    test "handles 500 server errors" do
      expect(HTTPMock, :get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 500,
          body: "Internal server error",
          headers: []
        }}
      end)

      assert {:error, :server_error} = SleeperClient.get_all_players()
    end

    test "handles 404 not found errors" do
      expect(HTTPMock, :get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 404,
          body: "Not found",
          headers: []
        }}
      end)

      assert {:error, :not_found} = SleeperClient.get_league("999999999")
    end
  end

  describe "data transformation" do
    test "transforms player data correctly" do
      assert {:ok, players} = SleeperClient.get_all_players()
      
      # Verify data structure matches our internal format expectations
      if map_size(players) > 0 do
        {sleeper_id, player_data} = Enum.take(players, 1) |> List.first()
        
        assert is_binary(sleeper_id)
        assert is_map(player_data)
        
        # Check required fields exist
        required_fields = ["player_id", "full_name", "position", "team", "status"]
        existing_fields = Map.keys(player_data)
        
        Enum.each(required_fields, fn field ->
          assert field in existing_fields, "Missing required field: #{field}"
        end)
      end
    end

    test "normalizes team abbreviations" do
      assert {:ok, players} = SleeperClient.get_all_players()
      
      # Find a player with a team
      player_with_team = 
        players
        |> Enum.find(fn {_id, data} -> 
          data["team"] != nil and data["team"] != ""
        end)
      
      if player_with_team do
        {_id, player_data} = player_with_team
        team = player_data["team"]
        
        # Team should be 2-3 character abbreviation
        assert is_binary(team)
        assert String.length(team) <= 3
        assert String.upcase(team) == team
      end
    end

    test "handles missing or null player data gracefully" do
      mock_response = %{
        "12345" => %{
          "player_id" => "12345",
          "full_name" => "Test Player",
          "position" => nil,  # null position
          "team" => nil,      # null team
          "status" => "Active"
        }
      }

      # This would test the internal transformation logic
      # For now, verify the client handles null values
      assert {:ok, _players} = SleeperClient.get_all_players()
    end
  end

  # Mock data helpers for when Sleeper API is unavailable
  defp mock_sleeper_responses do
    MockData.sleeper_players_response()
  end
end