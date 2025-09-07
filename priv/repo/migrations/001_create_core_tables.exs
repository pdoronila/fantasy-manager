defmodule FantasyManager.Repo.Migrations.CreateCoreTables do
  @moduledoc """
  Creates the core database tables for the fantasy football management system.
  
  This migration implements Phase 1 of the migration strategy from data-model.md:
  - Player, League, FantasyTeam, WeeklyProjection tables
  - Basic relationships and constraints
  - Essential indexes for performance
  """
  
  use Ecto.Migration

  def up do
    # Create players table
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sleeper_id, :string, null: false
      add :name, :string, null: false, size: 100
      add :position, :string, null: false
      add :nfl_team, :string, size: 3
      add :injury_status, :string, null: false, default: "Active"
      add :years_pro, :integer, null: false, default: 0
      add :age, :integer
      add :rookie_year, :integer
      add :dynasty_value, :decimal, precision: 5, scale: 2, null: false, default: 0.0
      add :keeper_eligible, :boolean, null: false, default: true
      add :state, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    # Create leagues table
    create table(:leagues, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sleeper_id, :string, null: false
      add :name, :string, null: false, size: 100
      add :season, :integer, null: false
      add :league_type, :string, null: false, default: "redraft"
      add :scoring_format, :string, null: false, default: "PPR"
      add :roster_size, :integer, null: false, default: 16
      add :keeper_count, :integer
      add :dynasty_transition_year, :integer
      add :trade_deadline_week, :integer, null: false, default: 10
      add :waiver_type, :string, null: false, default: "faab"
      add :playoff_teams, :integer, null: false, default: 6
      add :regular_season_weeks, :integer, null: false, default: 14
      add :draft_type, :string, null: false, default: "snake"
      add :settings, :map, null: false, default: %{}
      add :scoring_settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Create fantasy_teams table
    create table(:fantasy_teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sleeper_id, :string, null: false
      add :name, :string, null: false, size: 50
      add :owner_name, :string, null: false, size: 50
      add :competitive_window, :string, null: false, default: "Neutral"
      add :waiver_priority, :integer
      add :faab_budget, :integer, null: false, default: 100
      add :total_moves, :integer, null: false, default: 0
      add :wins, :integer, null: false, default: 0
      add :losses, :integer, null: false, default: 0
      add :ties, :integer, null: false, default: 0
      add :points_for, :decimal, precision: 8, scale: 2, null: false, default: 0.0
      add :points_against, :decimal, precision: 8, scale: 2, null: false, default: 0.0
      add :league_id, references(:leagues, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    # Create fantasy_team_players table (junction table for rosters)
    create table(:fantasy_team_players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fantasy_team_id, references(:fantasy_teams, on_delete: :delete_all, type: :binary_id), null: false
      add :player_id, references(:players, on_delete: :delete_all, type: :binary_id), null: false
      add :roster_position, :string, null: false, default: "Bench"
      add :lineup_position, :string
      add :acquisition_type, :string, null: false, default: "Draft"
      add :acquisition_date, :date, null: false
      add :acquisition_cost, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # Create weekly_projections table
    create table(:weekly_projections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :season, :integer, null: false
      add :week, :integer, null: false
      add :projected_points, :decimal, precision: 6, scale: 2, null: false
      add :confidence_score, :decimal, precision: 3, scale: 2, null: false, default: 0.5
      add :projection_model, :string, null: false, default: "claude-3-5-sonnet", size: 50
      add :factors_considered, :map, null: false, default: %{}
      add :created_by, :string, null: false, size: 100
      add :player_id, references(:players, on_delete: :delete_all, type: :binary_id), null: false

      # Detailed projection breakdown
      add :passing_yards, :decimal, precision: 6, scale: 2
      add :passing_tds, :decimal, precision: 4, scale: 2
      add :passing_ints, :decimal, precision: 4, scale: 2
      add :rushing_yards, :decimal, precision: 6, scale: 2
      add :rushing_tds, :decimal, precision: 4, scale: 2
      add :receiving_yards, :decimal, precision: 6, scale: 2
      add :receiving_tds, :decimal, precision: 4, scale: 2
      add :receptions, :decimal, precision: 4, scale: 2
      add :targets, :decimal, precision: 4, scale: 2

      # Contextual factors
      add :opponent, :string, size: 3
      add :game_environment, :string
      add :weather_impact, :decimal, precision: 3, scale: 2
      add :injury_risk_factor, :decimal, precision: 3, scale: 2
      add :matchup_difficulty, :string

      timestamps(type: :utc_datetime)
    end

    # Create player_stats table (for historical stats)
    create table(:player_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :player_id, references(:players, on_delete: :delete_all, type: :binary_id), null: false
      add :season, :integer, null: false
      add :week, :integer  # nullable for season totals
      add :game_id, :string
      add :opponent, :string, size: 3
      add :passing_yards, :integer, null: false, default: 0
      add :passing_tds, :integer, null: false, default: 0
      add :passing_ints, :integer, null: false, default: 0
      add :rushing_yards, :integer, null: false, default: 0
      add :rushing_tds, :integer, null: false, default: 0
      add :receiving_yards, :integer, null: false, default: 0
      add :receiving_tds, :integer, null: false, default: 0
      add :receptions, :integer, null: false, default: 0
      add :targets, :integer, null: false, default: 0
      add :fantasy_points, :decimal, precision: 6, scale: 2, null: false, default: 0.0

      timestamps(type: :utc_datetime)
    end

    # Create keeper_contracts table
    create table(:keeper_contracts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fantasy_team_id, references(:fantasy_teams, on_delete: :delete_all, type: :binary_id), null: false
      add :player_id, references(:players, on_delete: :delete_all, type: :binary_id), null: false
      add :contract_year, :integer, null: false
      add :years_remaining, :integer, null: false, default: 0
      add :keeper_cost, :integer, null: false
      add :cost_escalation, :decimal, precision: 4, scale: 2, null: false, default: 1.0
      add :is_eligible, :boolean, null: false, default: true
      add :designation_deadline, :date

      timestamps(type: :utc_datetime)
    end

    # Create matchups table
    create table(:matchups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :league_id, references(:leagues, on_delete: :delete_all, type: :binary_id), null: false
      add :season, :integer, null: false
      add :week, :integer, null: false
      add :team_1_id, references(:fantasy_teams, on_delete: :delete_all, type: :binary_id), null: false
      add :team_2_id, references(:fantasy_teams, on_delete: :delete_all, type: :binary_id), null: false
      add :team_1_score, :decimal, precision: 6, scale: 2
      add :team_2_score, :decimal, precision: 6, scale: 2
      add :is_playoffs, :boolean, null: false, default: false
      add :matchup_type, :string, null: false, default: "Regular"

      timestamps(type: :utc_datetime)
    end

    # Create trade_proposals table
    create table(:trade_proposals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sender_team_id, references(:fantasy_teams, on_delete: :delete_all, type: :binary_id), null: false
      add :receiver_team_id, references(:fantasy_teams, on_delete: :delete_all, type: :binary_id), null: false
      add :status, :string, null: false, default: "Pending"
      add :offered_players, :map, null: false, default: %{}
      add :requested_players, :map, null: false, default: %{}
      add :offered_picks, :map, null: false, default: %{}
      add :requested_picks, :map, null: false, default: %{}
      add :notes, :text
      add :expires_at, :utc_datetime
      add :ai_analysis, :map

      timestamps(type: :utc_datetime)
    end

    # Create recommendations table
    create table(:recommendations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :fantasy_team_id, references(:fantasy_teams, on_delete: :delete_all, type: :binary_id), null: false
      add :recommendation_type, :string, null: false
      add :context, :map, null: false, default: %{}
      add :recommendation_data, :map, null: false, default: %{}
      add :confidence_score, :decimal, precision: 3, scale: 2, null: false
      add :reasoning, :text, null: false
      add :time_horizon, :string, null: false, default: "Short"
      add :ai_model, :string, null: false, default: "claude-3-5-sonnet"
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Create unique constraints
    create unique_index(:players, [:sleeper_id], name: :players_sleeper_id_unique)
    create unique_index(:leagues, [:sleeper_id, :season], name: :leagues_sleeper_id_season_unique)
    create unique_index(:fantasy_teams, [:sleeper_id, :league_id], name: :fantasy_teams_sleeper_id_league_unique)
    create unique_index(:weekly_projections, [:player_id, :season, :week], name: :weekly_projections_player_season_week_unique)

    # Create performance indexes from data-model.md
    create index(:player_stats, [:player_id, :season, :week], name: :idx_player_stats_player_season_week)
    create index(:fantasy_team_players, [:fantasy_team_id], where: "roster_position != 'Dropped'", name: :idx_fantasy_team_players_team_active)
    create index(:weekly_projections, [:season, :week], name: :idx_weekly_projections_season_week)

    # External API lookups
    create index(:players, [:sleeper_id], name: :idx_players_sleeper_id)
    create index(:leagues, [:sleeper_id], name: :idx_leagues_sleeper_id)
    create index(:fantasy_teams, [:sleeper_id], name: :idx_fantasy_teams_sleeper_id)

    # AI and analysis queries
    create index(:players, [:position, :dynasty_value], name: :idx_players_position_dynasty_value)
    create index(:recommendations, [:fantasy_team_id, :recommendation_type, :expires_at], name: :idx_recommendations_team_type_expires)

    # Additional performance indexes
    create index(:fantasy_teams, [:league_id], name: :idx_fantasy_teams_league_id)
    create index(:fantasy_team_players, [:player_id], name: :idx_fantasy_team_players_player_id)
    create index(:weekly_projections, [:player_id], name: :idx_weekly_projections_player_id)
    create index(:weekly_projections, [:projection_model], name: :idx_weekly_projections_model)
    create index(:weekly_projections, [:confidence_score], name: :idx_weekly_projections_confidence)
    create index(:player_stats, [:season], name: :idx_player_stats_season)
    create index(:matchups, [:league_id, :season, :week], name: :idx_matchups_league_season_week)
    create index(:trade_proposals, [:status, :expires_at], name: :idx_trade_proposals_status_expires)
    create index(:recommendations, [:recommendation_type, :inserted_at], name: :idx_recommendations_type_date)

    # Check constraints for data integrity
    create constraint(:players, :dynasty_value_range, check: "dynasty_value >= 0 AND dynasty_value <= 100")
    create constraint(:players, :years_pro_positive, check: "years_pro >= 0")
    create constraint(:players, :age_reasonable, check: "age IS NULL OR (age >= 18 AND age <= 50)")
    
    create constraint(:leagues, :season_valid, check: "season >= 2020 AND season <= 2030")
    create constraint(:leagues, :roster_size_valid, check: "roster_size >= 10 AND roster_size <= 20")
    create constraint(:leagues, :trade_deadline_valid, check: "trade_deadline_week >= 1 AND trade_deadline_week <= 17")
    create constraint(:leagues, :keeper_count_valid, check: "keeper_count IS NULL OR (keeper_count >= 0 AND keeper_count <= roster_size)")
    
    create constraint(:fantasy_teams, :faab_budget_positive, check: "faab_budget >= 0")
    create constraint(:fantasy_teams, :record_non_negative, check: "wins >= 0 AND losses >= 0 AND ties >= 0")
    create constraint(:fantasy_teams, :points_non_negative, check: "points_for >= 0 AND points_against >= 0")
    
    create constraint(:weekly_projections, :season_valid, check: "season >= 2020 AND season <= 2030")
    create constraint(:weekly_projections, :week_valid, check: "week >= 1 AND week <= 18")
    create constraint(:weekly_projections, :confidence_valid, check: "confidence_score >= 0 AND confidence_score <= 1")
    create constraint(:weekly_projections, :projected_points_positive, check: "projected_points >= 0")
    
    create constraint(:player_stats, :season_valid, check: "season >= 2020 AND season <= 2030")
    create constraint(:player_stats, :week_valid, check: "week IS NULL OR (week >= 1 AND week <= 18)")
    create constraint(:player_stats, :stats_non_negative, check: "passing_yards >= 0 AND passing_tds >= 0 AND passing_ints >= 0 AND rushing_yards >= 0 AND rushing_tds >= 0 AND receiving_yards >= 0 AND receiving_tds >= 0 AND receptions >= 0 AND targets >= 0 AND fantasy_points >= 0")
    
    create constraint(:keeper_contracts, :years_remaining_positive, check: "years_remaining >= 0")
    create constraint(:keeper_contracts, :keeper_cost_positive, check: "keeper_cost > 0")
    create constraint(:keeper_contracts, :cost_escalation_valid, check: "cost_escalation >= 1.0")
    
    create constraint(:matchups, :week_valid, check: "week >= 1 AND week <= 18")
    create constraint(:matchups, :scores_positive, check: "team_1_score IS NULL OR team_1_score >= 0")
    create constraint(:matchups, :no_self_matchup, check: "team_1_id != team_2_id")

    # Add enum checks for specific fields
    create constraint(:players, :position_valid, check: "position IN ('QB', 'RB', 'WR', 'TE', 'K', 'DEF')")
    create constraint(:players, :injury_status_valid, check: "injury_status IN ('Active', 'Questionable', 'Doubtful', 'Out', 'IR', 'PUP')")
    create constraint(:players, :state_valid, check: "state IN ('active', 'injured', 'retired')")
    
    create constraint(:leagues, :league_type_valid, check: "league_type IN ('keeper', 'dynasty', 'redraft')")
    create constraint(:leagues, :scoring_format_valid, check: "scoring_format IN ('PPR', 'half_ppr', 'standard', 'superflex')")
    create constraint(:leagues, :waiver_type_valid, check: "waiver_type IN ('faab', 'rolling', 'reverse')")
    create constraint(:leagues, :draft_type_valid, check: "draft_type IN ('snake', 'linear', 'auction')")
    
    create constraint(:fantasy_teams, :competitive_window_valid, check: "competitive_window IN ('Contending', 'Rebuilding', 'Neutral')")
    
    create constraint(:fantasy_team_players, :roster_position_valid, check: "roster_position IN ('Starter', 'Bench', 'IR', 'Taxi', 'Dropped')")
    create constraint(:fantasy_team_players, :acquisition_type_valid, check: "acquisition_type IN ('Draft', 'Trade', 'Waiver', 'Free Agent')")
    
    create constraint(:matchups, :matchup_type_valid, check: "matchup_type IN ('Regular', 'Playoffs', 'Championship')")
    
    create constraint(:trade_proposals, :status_valid, check: "status IN ('Pending', 'Accepted', 'Rejected', 'Countered', 'Expired')")
    
    create constraint(:recommendations, :recommendation_type_valid, check: "recommendation_type IN ('Lineup', 'Trade', 'Pickup', 'Keeper', 'Dynasty')")
    create constraint(:recommendations, :time_horizon_valid, check: "time_horizon IN ('Short', 'Medium', 'Long')")
    create constraint(:recommendations, :confidence_valid, check: "confidence_score >= 0 AND confidence_score <= 1")

    # Add additional specific indexes for common queries
    create index(:weekly_projections, [:season, :week, :projected_points], name: :idx_weekly_projections_season_week_points)
    create index(:players, [:dynasty_value], where: "dynasty_value > 50", name: :idx_players_high_dynasty_value)
    create index(:fantasy_team_players, [:roster_position], name: :idx_fantasy_team_players_roster_position)
    create index(:keeper_contracts, [:is_eligible, :designation_deadline], name: :idx_keeper_contracts_eligible_deadline)
  end

  def down do
    # Drop tables in reverse order due to foreign key dependencies
    drop table(:recommendations)
    drop table(:trade_proposals)
    drop table(:matchups)
    drop table(:keeper_contracts)
    drop table(:player_stats)
    drop table(:weekly_projections)
    drop table(:fantasy_team_players)
    drop table(:fantasy_teams)
    drop table(:leagues)
    drop table(:players)
  end
end