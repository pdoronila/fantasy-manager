# Fantasy Manager Seed Data
#
# Script for populating the database with test data. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This creates sample leagues, teams, players for browser testing
# and includes mock Sleeper data for offline development

alias FantasyManager.Fantasy.{Player, League, FantasyTeam, FantasyTeamPlayer}
alias FantasyManager.Repo

# Clear existing data (for development)
if Mix.env() == :dev do
  Repo.delete_all(FantasyTeamPlayer)
  Repo.delete_all(FantasyTeam)
  Repo.delete_all(League)
  Repo.delete_all(Player)
end

# Sample Players - Top fantasy relevant players
players = [
  # QBs
  %{
    name: "Josh Allen",
    position: :QB,
    nfl_team: "BUF",
    dynasty_value: 95,
    sleeper_id: "4881",
    injury_status: :Active,
    age: 27,
    rookie_year: 2018,
    years_pro: 6,
    keeper_eligible: true,
    state: :active
  },
  %{
    name: "Patrick Mahomes",
    position: :QB, 
    nfl_team: "KC",
    dynasty_value: 98,
    sleeper_id: "4046",
    injury_status: :Active,
    age: 28,
    rookie_year: 2017,
    years_pro: 7,
    keeper_eligible: true,
    state: :active
  },
  # RBs
  %{
    name: "Christian McCaffrey",
    position: :RB,
    nfl_team: "SF",
    dynasty_value: 85,
    sleeper_id: "4035",
    injury_status: :Active,
    age: 28,
    rookie_year: 2017,
    years_pro: 7,
    keeper_eligible: true,
    state: :active
  },
  %{
    name: "Austin Ekeler",
    position: :RB,
    nfl_team: "WAS",
    dynasty_value: 72,
    sleeper_id: "4017",
    injury_status: :Active,
    age: 29,
    rookie_year: 2017,
    years_pro: 7,
    keeper_eligible: false,
    state: :active
  },
  # WRs
  %{
    name: "Cooper Kupp",
    position: :WR,
    nfl_team: "LAR",
    dynasty_value: 82,
    sleeper_id: "4098",
    injury_status: :Active,
    age: 31,
    rookie_year: 2017,
    years_pro: 7,
    keeper_eligible: false,
    state: :active
  },
  %{
    name: "Tyreek Hill",
    position: :WR,
    nfl_team: "MIA",
    dynasty_value: 88,
    sleeper_id: "2133",
    injury_status: :Active,
    age: 30,
    rookie_year: 2016,
    years_pro: 8,
    keeper_eligible: true,
    state: :active
  },
  # TEs  
  %{
    name: "Travis Kelce",
    position: :TE,
    nfl_team: "KC",
    dynasty_value: 78,
    sleeper_id: "947",
    injury_status: :Active,
    age: 34,
    rookie_year: 2013,
    years_pro: 11,
    keeper_eligible: false,
    state: :active
  },
  %{
    name: "Mark Andrews",
    position: :TE,
    nfl_team: "BAL",
    dynasty_value: 75,
    sleeper_id: "4866",
    injury_status: :Active,
    age: 29,
    rookie_year: 2018,
    years_pro: 6,
    keeper_eligible: true,
    state: :active
  },
  # K/DST
  %{
    name: "Justin Tucker",
    position: :K,
    nfl_team: "BAL",
    dynasty_value: 45,
    sleeper_id: "1466",
    injury_status: :Active,
    age: 34,
    rookie_year: 2012,
    years_pro: 12,
    keeper_eligible: false,
    state: :active
  },
  %{
    name: "49ers",
    position: :DEF,
    nfl_team: "SF",
    dynasty_value: 35,
    sleeper_id: "SF",
    injury_status: :Active,
    age: 25,
    rookie_year: 2020,
    years_pro: 4,
    keeper_eligible: false,
    state: :active
  }
]

# Create players - handling creation with error checking
created_players = Enum.map(players, fn player_data ->
  case Player.create(player_data) do
    {:ok, player} -> 
      IO.puts("✓ Created player: #{player.name}")
      player
    {:error, error} -> 
      IO.puts("✗ Failed to create player: #{inspect(player_data)}")
      IO.puts("  Error: #{inspect(error)}")
      nil
  end
end) |> Enum.reject(&is_nil/1)

# Sample League - Dynasty League
league_data = %{
  name: "Dynasty Test League",
  season: 2024,
  league_type: "dynasty",
  scoring_format: "ppr",
  roster_size: 16,
  playoff_teams: 4,
  trade_deadline_week: 11,
  waiver_type: "faab",
  draft_type: "auction",
  sleeper_id: "test_dynasty_123",
  dynasty_transition_year: 2020,
  keeper_count: 16,
  regular_season_weeks: 14,
  scoring_settings: %{
    "pass_yd" => 0.04,
    "pass_td" => 4.0,
    "rush_yd" => 0.1,
    "rush_td" => 6.0,
    "rec_yd" => 0.1,
    "rec_td" => 6.0,
    "rec" => 1.0
  }
}

league = League.create!(league_data)

# Sample Fantasy Teams
teams_data = [
  %{
    name: "Dynasty Dominators",
    owner_name: "Alice Johnson",
    wins: 8,
    losses: 5,
    ties: 0,
    points_for: 1567.25,
    points_against: 1445.80,
    faab_budget: 150,
    total_moves: 12,
    competitive_window: "contending",
    sleeper_id: "team_001",
    waiver_priority: 8,
    league_id: league.id
  },
  %{
    name: "Rebuilding Rockets",
    owner_name: "Bob Smith", 
    wins: 4,
    losses: 9,
    ties: 0,
    points_for: 1234.75,
    points_against: 1623.40,
    faab_budget: 95,
    total_moves: 24,
    competitive_window: "rebuilding",
    sleeper_id: "team_002", 
    waiver_priority: 2,
    league_id: league.id
  }
]

# Create teams
created_teams = Enum.map(teams_data, fn team_data ->
  FantasyTeam.create!(team_data)
end)

# Add players to teams
[team1, team2] = created_teams
[qb1, qb2, rb1, rb2, wr1, wr2, te1, te2, k1, def1] = created_players

# Team 1 roster
team1_players = [
  %{fantasy_team_id: team1.id, player_id: qb1.id, roster_position: "QB", lineup_position: "QB"},
  %{fantasy_team_id: team1.id, player_id: rb1.id, roster_position: "RB", lineup_position: "RB"},
  %{fantasy_team_id: team1.id, player_id: wr1.id, roster_position: "WR", lineup_position: "WR"},
  %{fantasy_team_id: team1.id, player_id: te1.id, roster_position: "TE", lineup_position: "TE"},
  %{fantasy_team_id: team1.id, player_id: k1.id, roster_position: "K", lineup_position: "K"}
]

# Team 2 roster  
team2_players = [
  %{fantasy_team_id: team2.id, player_id: qb2.id, roster_position: "QB", lineup_position: "QB"},
  %{fantasy_team_id: team2.id, player_id: rb2.id, roster_position: "RB", lineup_position: "RB"},
  %{fantasy_team_id: team2.id, player_id: wr2.id, roster_position: "WR", lineup_position: "WR"},
  %{fantasy_team_id: team2.id, player_id: te2.id, roster_position: "TE", lineup_position: "TE"},
  %{fantasy_team_id: team2.id, player_id: def1.id, roster_position: "DEF", lineup_position: "DEF"}
]

# Create team-player relationships
Enum.each(team1_players ++ team2_players, fn player_data ->
  FantasyTeamPlayer.create!(player_data)
end)

IO.puts """
✅ Seed data created successfully!

Created:
- #{length(players)} players
- 1 dynasty league
- #{length(teams_data)} fantasy teams
- #{length(team1_players) + length(team2_players)} player assignments

You can now test the application with this data:
- Browse leagues at http://localhost:4000/dashboard
- View league details: http://localhost:4000/dashboard/league/#{league.id}
- Test API endpoints at /api/v1/*
- Check health endpoints at /health/*

Run `mix ecto.reset` to clear all data and re-run seeds.
"""
