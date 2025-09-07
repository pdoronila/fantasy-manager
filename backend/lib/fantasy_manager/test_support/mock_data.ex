defmodule FantasyManager.TestSupport.MockData do
  @moduledoc """
  Mock data generators for offline testing and development.
  
  Provides realistic sample data that matches Sleeper API response formats
  for players, leagues, teams, rosters, and matchups. This enables:
  - Offline development and testing
  - Consistent test fixtures
  - Performance testing with large datasets
  - Demo data for UI development
  """

  @doc """
  Generate mock NFL player data in Sleeper API format.
  Returns a map with player_id as keys and player data as values.
  """
  def mock_players(count \\ 100) do
    positions = ["QB", "RB", "WR", "TE", "K", "DEF"]
    teams = ["ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", 
             "DET", "GB", "HOU", "IND", "JAX", "KC", "LAS", "LAC", "LAR", "MIA", 
             "MIN", "NE", "NO", "NYG", "NYJ", "PHI", "PIT", "SF", "SEA", "TB", "TEN", "WAS"]
    
    1..count
    |> Enum.map(fn i ->
      player_id = "player_#{i}"
      position = Enum.random(positions)
      team = Enum.random(teams)
      
      player_data = %{
        "player_id" => player_id,
        "first_name" => generate_first_name(),
        "last_name" => generate_last_name(),
        "full_name" => nil, # Will be computed
        "position" => position,
        "team" => team,
        "age" => Enum.random(21..35),
        "height" => generate_height(),
        "weight" => generate_weight(position),
        "years_exp" => Enum.random(0..15),
        "college" => generate_college(),
        "birth_date" => generate_birth_date(),
        "fantasy_positions" => [position],
        "status" => "Active",
        "injury_status" => generate_injury_status(),
        "depth_chart_order" => Enum.random(1..4),
        "search_rank" => calculate_search_rank(position, i),
        "search_full_name" => nil, # Will be computed
        "search_first_name" => nil, # Will be computed  
        "search_last_name" => nil, # Will be computed
        "sport" => "nfl",
        "active" => true,
        "metadata" => %{
          "years_exp" => Enum.random(0..15),
          "team" => team,
          "status" => "Active",
          "position" => position,
          "injury_status" => generate_injury_status()
        }
      }
      
      # Compute full name and search fields
      full_name = "#{player_data["first_name"]} #{player_data["last_name"]}"
      updated_player = player_data
        |> Map.put("full_name", full_name)
        |> Map.put("search_full_name", String.downcase(full_name))
        |> Map.put("search_first_name", String.downcase(player_data["first_name"]))
        |> Map.put("search_last_name", String.downcase(player_data["last_name"]))
      
      {player_id, updated_player}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Generate mock league data in Sleeper API format.
  """
  def mock_league(league_id \\ "test_league_123") do
    %{
      "league_id" => league_id,
      "name" => "Mock Fantasy League",
      "avatar" => "avatar_123",
      "season" => "2024",
      "season_type" => "regular",
      "total_rosters" => 12,
      "status" => "in_season",
      "sport" => "nfl",
      "settings" => %{
        "max_keepers" => 3,
        "draft_rounds" => 16,
        "trade_deadline" => 12,
        "playoff_teams" => 6,
        "playoff_rounds" => 3,
        "playoff_start_week" => 15,
        "leg" => 1,
        "playoff_seed_type" => 0,
        "playoff_type" => 0,
        "daily_waivers" => 0,
        "waiver_type" => 2,
        "waiver_clear_days" => 1,
        "waiver_day_of_week" => 3,
        "start_week" => 1,
        "taxi_years" => 0,
        "taxi_slots" => 0,
        "taxi_allow_vets" => false,
        "reserve_allow_out" => true,
        "reserve_allow_sus" => false,
        "reserve_allow_cov" => true,
        "reserve_slots" => 3,
        "playoff_week_start" => 15,
        "num_teams" => 12,
        "league_average_match" => 0,
        "last_scored_leg" => 1,
        "last_report" => nil,
        "keeper_deadline" => "2024-09-01",
        "injury_reserve" => true,
        "commissioner_direct_invite" => 0,
        "capacity_override" => 0,
        "best_ball" => 0
      },
      "scoring_settings" => mock_scoring_settings(),
      "roster_positions" => [
        "QB", "RB", "RB", "WR", "WR", "WR", "TE", "FLEX", "K", "DEF", 
        "BN", "BN", "BN", "BN", "BN", "BN", "IR", "IR", "IR"
      ],
      "metadata" => %{
        "keeper_deadline" => "2024-09-01",
        "auto_continue" => "off",
        "division_1" => "Division 1",
        "division_2" => "Division 2"
      },
      "draft_id" => "draft_123",
      "group_id" => nil,
      "bracket_id" => nil,
      "loser_bracket_id" => nil,
      "previous_league_id" => nil
    }
  end

  @doc """
  Generate mock league users (managers).
  """
  def mock_league_users(count \\ 12) do
    1..count
    |> Enum.map(fn i ->
      %{
        "user_id" => "user_#{i}",
        "username" => "manager#{i}",
        "display_name" => "Manager #{i}",
        "avatar" => "avatar_#{i}",
        "metadata" => %{
          "team_name" => "Team #{i}",
          "allow_pn" => true,
          "allow_sms" => false
        },
        "is_owner" => i == 1,
        "is_bot" => false,
        "settings" => nil
      }
    end)
  end

  @doc """
  Generate mock league rosters.
  """
  def mock_league_rosters(league_id \\ "test_league_123", user_count \\ 12) do
    mock_player_pool = mock_players(300) |> Map.keys()
    
    1..user_count
    |> Enum.map(fn i ->
      # Randomly assign players to each roster
      roster_players = mock_player_pool
        |> Enum.shuffle()
        |> Enum.take(Enum.random(16..20))
      
      starters = Enum.take(roster_players, 9)
      
      %{
        "roster_id" => i,
        "owner_id" => "user_#{i}",
        "league_id" => league_id,
        "players" => roster_players,
        "starters" => starters,
        "reserve" => [],
        "taxi" => [],
        "settings" => %{
          "wins" => Enum.random(0..10),
          "losses" => Enum.random(0..10),
          "ties" => 0,
          "fpts" => :rand.uniform() * 1000 + 800,
          "fpts_against" => :rand.uniform() * 1000 + 800,
          "fpts_decimal" => :rand.uniform(),
          "fpts_against_decimal" => :rand.uniform(),
          "ppts" => :rand.uniform() * 1000 + 800,
          "ppts_decimal" => :rand.uniform(),
          "division" => if(i <= 6, do: 1, else: 2),
          "waiver_position" => Enum.random(1..12),
          "waiver_budget_used" => Enum.random(0..100),
          "total_moves" => Enum.random(0..50),
          "record" => %{
            "wins" => Enum.random(0..10),
            "losses" => Enum.random(0..10),
            "ties" => 0
          }
        },
        "metadata" => %{
          "streak" => generate_streak(),
          "record" => "#{Enum.random(0..10)}-#{Enum.random(0..10)}"
        },
        "keepers" => generate_keepers(roster_players),
        "draft_picks" => generate_draft_picks(i),
        "co_owners" => nil
      }
    end)
  end

  @doc """
  Generate mock matchups for a specific week.
  """
  def mock_league_matchups(league_id \\ "test_league_123", week \\ 1) do
    roster_count = 12
    
    # Create matchups by pairing rosters
    1..(roster_count)
    |> Enum.chunk_every(2)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {roster_pair, matchup_id} ->
      Enum.map(roster_pair, fn roster_id ->
        %{
          "roster_id" => roster_id,
          "matchup_id" => matchup_id,
          "points" => :rand.uniform() * 150 + 80,
          "players" => generate_player_scores(),
          "starters" => generate_starter_scores(),
          "starters_points" => :rand.uniform() * 120 + 70,
          "players_points" => %{},
          "custom_points" => nil
        }
      end)
    end)
  end

  @doc """
  Generate mock NFL state.
  """
  def mock_nfl_state do
    current_week = Enum.random(1..18)
    
    %{
      "season" => "2024",
      "season_type" => "regular",
      "week" => current_week,
      "season_start_date" => "2024-09-05",
      "leg" => 1,
      "previous_season" => "2023",
      "display_week" => current_week
    }
  end

  @doc """
  Generate comprehensive mock league data including all related entities.
  """
  def mock_full_league_data(league_id \\ "test_league_123", user_count \\ 12) do
    users = mock_league_users(user_count)
    league = mock_league(league_id)
    rosters = mock_league_rosters(league_id, user_count)
    
    %{
      league: league,
      users: users,
      rosters: rosters,
      current_matchups: mock_league_matchups(league_id, 8),
      nfl_state: mock_nfl_state()
    }
  end

  # Private helper functions

  defp generate_first_name do
    names = ["Josh", "Justin", "Lamar", "Aaron", "Tom", "Patrick", "Russell", "Dak", 
             "Kyler", "Matt", "Ryan", "Kirk", "Tua", "Mac", "Trevor", "Zach", "Davis",
             "Saquon", "Christian", "Dalvin", "Alvin", "Ezekiel", "Nick", "Joe", "Austin",
             "Cooper", "Davante", "DeAndre", "Stefon", "Calvin", "Mike", "Tyreek", "Keenan",
             "Travis", "George", "Mark", "Darren", "Kyle", "Harrison"]
    
    Enum.random(names)
  end

  defp generate_last_name do
    names = ["Allen", "Herbert", "Jackson", "Rodgers", "Brady", "Mahomes", "Wilson", "Prescott",
             "Murray", "Ryan", "Tannehill", "Cousins", "Tagovailoa", "Jones", "Lawrence", "Wilson",
             "Mills", "Barkley", "McCaffrey", "Cook", "Kamara", "Elliott", "Chubb", "Mixon",
             "Ekeler", "Kupp", "Adams", "Hopkins", "Diggs", "Ridley", "Evans", "Hill", "Allen",
             "Kelce", "Kittle", "Andrews", "Waller", "Butker", "Tucker"]
    
    Enum.random(names)
  end

  defp generate_height do
    feet = Enum.random(5..6)
    inches = Enum.random(0..11)
    "#{feet}'#{inches}\""
  end

  defp generate_weight(position) do
    case position do
      "QB" -> Enum.random(200..250)
      "RB" -> Enum.random(180..230)
      "WR" -> Enum.random(170..220)
      "TE" -> Enum.random(240..280)
      "K" -> Enum.random(170..210)
      "DEF" -> Enum.random(180..300)
      _ -> Enum.random(180..250)
    end
  end

  defp generate_college do
    colleges = ["Alabama", "Georgia", "Ohio State", "Clemson", "LSU", "Oklahoma", "Texas", "Michigan",
                "Notre Dame", "Penn State", "Florida", "Auburn", "Texas A&M", "Tennessee", "South Carolina",
                "Miami", "FSU", "North Carolina", "Virginia Tech", "Wisconsin", "Iowa", "Nebraska"]
    
    Enum.random(colleges)
  end

  defp generate_birth_date do
    year = Enum.random(1985..2002)
    month = Enum.random(1..12) |> Integer.to_string() |> String.pad_leading(2, "0")
    day = Enum.random(1..28) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{year}-#{month}-#{day}"
  end

  defp generate_injury_status do
    statuses = ["", "Questionable", "Doubtful", "Out", "IR", "PUP"]
    Enum.random(statuses)
  end

  defp calculate_search_rank(position, index) do
    base_rank = case position do
      "QB" -> 1000
      "RB" -> 2000  
      "WR" -> 3000
      "TE" -> 4000
      "K" -> 5000
      "DEF" -> 6000
      _ -> 7000
    end
    
    base_rank + index
  end

  defp mock_scoring_settings do
    %{
      "pass_yd" => 0.04,
      "pass_td" => 4,
      "pass_int" => -2,
      "pass_2pt" => 2,
      "rush_yd" => 0.1,
      "rush_td" => 6,
      "rush_2pt" => 2,
      "rec_yd" => 0.1,
      "rec_td" => 6,
      "rec" => 1,
      "rec_2pt" => 2,
      "fum_lost" => -2,
      "fgm" => 3,
      "fgmiss" => 0,
      "xpm" => 1,
      "xpmiss" => 0,
      "def_td" => 6,
      "def_int" => 2,
      "def_fum_rec" => 2,
      "def_sack" => 1,
      "def_safety" => 2,
      "def_pa" => 0,
      "def_yds_allowed" => 0
    }
  end

  defp generate_streak do
    types = ["W", "L"]
    type = Enum.random(types)
    length = Enum.random(1..5)
    "#{length}#{type}"
  end

  defp generate_keepers(roster_players) do
    roster_players
    |> Enum.take(Enum.random(0..3))
    |> Enum.map(fn player_id ->
      %{
        "player_id" => player_id,
        "round" => Enum.random(1..16),
        "salary" => Enum.random(5..50)
      }
    end)
  end

  defp generate_draft_picks(roster_id) do
    current_year = 2024
    
    [current_year, current_year + 1, current_year + 2]
    |> Enum.flat_map(fn year ->
      1..3
      |> Enum.map(fn round ->
        %{
          "season" => to_string(year),
          "round" => round,
          "roster_id" => roster_id,
          "previous_owner_id" => nil,
          "owner_id" => "user_#{roster_id}"
        }
      end)
    end)
  end

  defp generate_player_scores do
    # Generate random player scores for matchup
    1..16
    |> Enum.map(fn i -> {"player_#{i}", :rand.uniform() * 25} end)
    |> Enum.into(%{})
  end

  defp generate_starter_scores do
    # Generate random starter scores
    1..9
    |> Enum.map(fn i -> "player_#{i}" end)
  end
end