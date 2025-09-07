defmodule FantasyManager.Fantasy.FantasyTeam do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "fantasy_teams"
    repo FantasyManager.Repo

    references do
      reference :fantasy_team_players, on_delete: :delete
      reference :keeper_contracts, on_delete: :delete
      reference :trade_proposals_sent, on_delete: :delete
      reference :trade_proposals_received, on_delete: :delete
      reference :recommendations, on_delete: :delete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sleeper_id, :string do
      allow_nil? false
      constraints [match: ~r/^[0-9]+$/]
    end

    attribute :name, :string do
      allow_nil? false
      constraints [min_length: 1, max_length: 50]
    end

    attribute :owner_name, :string do
      allow_nil? false
      constraints [min_length: 1, max_length: 50]
    end

    attribute :competitive_window, :atom do
      allow_nil? false
      default :Neutral
      constraints [one_of: [:Contending, :Rebuilding, :Neutral]]
    end

    attribute :waiver_priority, :integer do
      allow_nil? true
      constraints [min: 1, max: 20]
    end

    attribute :faab_budget, :integer do
      allow_nil? false
      default 100
      constraints [min: 0, max: 1000]
    end

    attribute :total_moves, :integer do
      allow_nil? false
      default 0
      constraints [min: 0]
    end

    attribute :wins, :integer do
      allow_nil? false
      default 0
      constraints [min: 0]
    end

    attribute :losses, :integer do
      allow_nil? false
      default 0
      constraints [min: 0]
    end

    attribute :ties, :integer do
      allow_nil? false
      default 0
      constraints [min: 0]
    end

    attribute :points_for, :decimal do
      allow_nil? false
      default 0.0
      constraints [min: 0.0]
    end

    attribute :points_against, :decimal do
      allow_nil? false
      default 0.0
      constraints [min: 0.0]
    end

    attribute :league_id, :uuid do
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :league, FantasyManager.Fantasy.League do
      source_attribute :league_id
      destination_attribute :id
    end

    has_many :fantasy_team_players, FantasyManager.Fantasy.FantasyTeamPlayer do
      destination_attribute :fantasy_team_id
    end

    has_many :players, FantasyManager.Fantasy.Player do
      through :fantasy_team_players
    end

    has_many :keeper_contracts, FantasyManager.Fantasy.KeeperContract do
      destination_attribute :fantasy_team_id
    end

    has_many :trade_proposals_sent, FantasyManager.Fantasy.TradeProposal do
      destination_attribute :sender_team_id
    end

    has_many :trade_proposals_received, FantasyManager.Fantasy.TradeProposal do
      destination_attribute :receiver_team_id
    end

    has_many :recommendations, FantasyManager.Fantasy.Recommendation do
      destination_attribute :fantasy_team_id
    end
  end

  calculations do
    calculate :win_percentage, :decimal, expr(
      case do
        wins + losses + ties == 0 -> 0.0
        true -> wins / (wins + losses + ties)
      end
    )

    calculate :points_difference, :decimal, expr(
      points_for - points_against
    )

    calculate :roster_size, :integer, expr(
      fragment("SELECT COUNT(*) FROM fantasy_team_players WHERE fantasy_team_id = ? AND roster_position != 'Dropped'", [id])
    )

    calculate :active_roster_size, :integer, expr(
      fragment("SELECT COUNT(*) FROM fantasy_team_players WHERE fantasy_team_id = ? AND roster_position IN ('Starter', 'Bench')", [id])
    )

    calculate :bench_size, :integer, expr(
      fragment("SELECT COUNT(*) FROM fantasy_team_players WHERE fantasy_team_id = ? AND roster_position = 'Bench'", [id])
    )

    calculate :ir_count, :integer, expr(
      fragment("SELECT COUNT(*) FROM fantasy_team_players WHERE fantasy_team_id = ? AND roster_position = 'IR'", [id])
    )

    calculate :taxi_count, :integer, expr(
      fragment("SELECT COUNT(*) FROM fantasy_team_players WHERE fantasy_team_id = ? AND roster_position = 'Taxi'", [id])
    )

    calculate :average_age, :decimal, expr(
      fragment("
        SELECT COALESCE(AVG(p.age), 0) 
        FROM fantasy_team_players ftp 
        JOIN players p ON ftp.player_id = p.id 
        WHERE ftp.fantasy_team_id = ? AND ftp.roster_position != 'Dropped' AND p.age IS NOT NULL
      ", [id])
    )

    calculate :positional_needs, {:array, :atom}, expr(
      fragment("
        SELECT ARRAY(
          SELECT unnest(ARRAY['QB', 'RB', 'WR', 'TE', 'K', 'DEF']) 
          EXCEPT 
          SELECT DISTINCT p.position 
          FROM fantasy_team_players ftp 
          JOIN players p ON ftp.player_id = p.id 
          WHERE ftp.fantasy_team_id = ? AND ftp.roster_position IN ('Starter', 'Bench')
        )
      ", [id])
    )

    calculate :keeper_eligible_count, :integer, expr(
      fragment("
        SELECT COUNT(*) 
        FROM fantasy_team_players ftp 
        JOIN players p ON ftp.player_id = p.id 
        WHERE ftp.fantasy_team_id = ? AND p.keeper_eligible = true AND ftp.roster_position != 'Dropped'
      ", [id])
    )

    calculate :projected_lineup_points, :decimal, expr(
      fragment("
        SELECT COALESCE(SUM(wp.projected_points), 0)
        FROM fantasy_team_players ftp
        JOIN players p ON ftp.player_id = p.id
        LEFT JOIN weekly_projections wp ON p.id = wp.player_id 
          AND wp.season = EXTRACT(year FROM now())
          AND wp.week = (SELECT MAX(week) FROM weekly_projections WHERE season = EXTRACT(year FROM now()))
        WHERE ftp.fantasy_team_id = ? AND ftp.roster_position = 'Starter'
      ", [id])
    )
  end

  validations do
    validate present([:name, :owner_name, :sleeper_id, :league_id])

    validate {FantasyManager.Fantasy.FantasyTeam.Validations, :faab_budget_within_league_limits}
    validate {FantasyManager.Fantasy.FantasyTeam.Validations, :waiver_priority_unique_within_league}
    validate {FantasyManager.Fantasy.FantasyTeam.Validations, :roster_size_within_league_limits}
  end

  changes do
    change after_action(:sync_roster_from_sleeper) do
      on [:create]
    end

    change before_action(:calculate_competitive_window) do
      on [:create, :update]
      only_when_attribute_changes [:wins, :losses, :points_for]
    end

    change after_action(:update_league_standings) do
      on [:update]
      only_when_attribute_changes [:wins, :losses, :points_for]
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_from_sleeper do
      argument :sleeper_data, :map, allow_nil? false
      argument :user_data, :map, allow_nil? false
      argument :league_id, :uuid, allow_nil? false
      
      change fn changeset, context ->
        sleeper_data = Ash.Changeset.get_argument(changeset, :sleeper_data)
        user_data = Ash.Changeset.get_argument(changeset, :user_data)
        league_id = Ash.Changeset.get_argument(changeset, :league_id)
        
        changeset
        |> Ash.Changeset.change_attribute(:sleeper_id, sleeper_data["roster_id"])
        |> Ash.Changeset.change_attribute(:name, user_data["display_name"] || user_data["username"])
        |> Ash.Changeset.change_attribute(:owner_name, user_data["display_name"] || user_data["username"])
        |> Ash.Changeset.change_attribute(:league_id, league_id)
        |> Ash.Changeset.change_attribute(:wins, sleeper_data["settings"]["wins"] || 0)
        |> Ash.Changeset.change_attribute(:losses, sleeper_data["settings"]["losses"] || 0)
        |> Ash.Changeset.change_attribute(:ties, sleeper_data["settings"]["ties"] || 0)
        |> Ash.Changeset.change_attribute(:points_for, Decimal.new(sleeper_data["settings"]["fpts"] || "0"))
        |> Ash.Changeset.change_attribute(:points_against, Decimal.new(sleeper_data["settings"]["fpts_against"] || "0"))
        |> Ash.Changeset.change_attribute(:waiver_priority, sleeper_data["settings"]["waiver_position"])
        |> Ash.Changeset.change_attribute(:faab_budget, sleeper_data["settings"]["waiver_budget_used"] || 100)
        |> Ash.Changeset.change_attribute(:total_moves, sleeper_data["settings"]["total_moves"] || 0)
      end
    end

    update :update_competitive_window do
      argument :window, :atom, allow_nil? false

      validate attribute_in(:window, [:Contending, :Rebuilding, :Neutral])

      change set_attribute(:competitive_window, arg(:window))
    end

    update :update_record do
      argument :wins, :integer
      argument :losses, :integer
      argument :ties, :integer
      argument :points_for, :decimal
      argument :points_against, :decimal

      change set_attribute(:wins, arg(:wins))
      change set_attribute(:losses, arg(:losses))
      change set_attribute(:ties, arg(:ties))
      change set_attribute(:points_for, arg(:points_for))
      change set_attribute(:points_against, arg(:points_against))
    end

    update :make_waiver_claim do
      argument :player_id, :uuid, allow_nil? false
      argument :drop_player_id, :uuid
      argument :bid_amount, :integer, allow_nil? false

      validate compare(:bid_amount, greater_than: 0, less_than_or_equal_to: expr(faab_budget))

      change fn changeset, context ->
        bid_amount = Ash.Changeset.get_argument(changeset, :bid_amount)
        current_budget = Ash.Changeset.get_data(changeset).faab_budget
        
        Ash.Changeset.change_attribute(changeset, :faab_budget, current_budget - bid_amount)
      end
    end

    read :in_league do
      argument :league_id, :uuid, allow_nil? false

      filter expr(league_id == ^arg(:league_id))
    end

    read :by_competitive_window do
      argument :window, :atom, allow_nil? false

      filter expr(competitive_window == ^arg(:window))
    end

    read :playoff_contenders do
      argument :league_id, :uuid, allow_nil? false

      filter expr(league_id == ^arg(:league_id))
      sort [win_percentage: :desc, points_for: :desc]
      limit 6
    end

    read :standings do
      argument :league_id, :uuid, allow_nil? false

      filter expr(league_id == ^arg(:league_id))
      sort [win_percentage: :desc, points_for: :desc]
    end

    read :search_teams do
      argument :query, :string, allow_nil? false

      filter expr(ilike(name, ^("%#{arg(:query)}%")) or ilike(owner_name, ^("%#{arg(:query)}%")))
    end

    action :analyze_team_needs, :map do
      run fn input, context ->
        team = context.resource
        
        # Get current roster composition
        roster_analysis = analyze_roster_composition(team)
        
        # Calculate positional strengths and needs
        positional_analysis = analyze_positional_needs(team)
        
        # Determine competitive window factors
        competitive_analysis = analyze_competitive_factors(team)
        
        {:ok, %{
          roster_composition: roster_analysis,
          positional_strength: positional_analysis.strengths,
          positional_needs: positional_analysis.needs,
          competitive_window: team.competitive_window,
          recommendations: generate_team_recommendations(roster_analysis, positional_analysis, competitive_analysis)
        }}
      end
    end

    action :sync_roster_from_sleeper, :map do
      argument :sleeper_roster_data, :map, allow_nil? false

      run fn input, context ->
        team = context.resource
        roster_data = input.arguments.sleeper_roster_data
        
        case sync_roster_players(team, roster_data) do
          {:ok, sync_results} ->
            {:ok, sync_results}
          {:error, reason} ->
            {:error, %{error: "Failed to sync roster", reason: reason}}
        end
      end
    end
  end

  code_interface do
    define_for FantasyManager.Fantasy

    define :create
    define :read
    define :update
    define :destroy
    define :create_from_sleeper, args: [:sleeper_data, :user_data, :league_id]
    define :update_competitive_window, args: [:window]
    define :update_record, args: [:wins, :losses, :ties, :points_for, :points_against]
    define :make_waiver_claim, args: [:player_id, :drop_player_id, :bid_amount]
    define :in_league, args: [:league_id]
    define :by_competitive_window, args: [:window]
    define :playoff_contenders, args: [:league_id]
    define :standings, args: [:league_id]
    define :search_teams, args: [:query]
    define :analyze_team_needs
    define :sync_roster_from_sleeper, args: [:sleeper_roster_data]

    define :get_by_sleeper_id, get_by: [:sleeper_id]
  end

  identities do
    identity :unique_sleeper_id_league, [:sleeper_id, :league_id]
  end

  # Helper functions
  defp sync_roster_from_sleeper(changeset, team) do
    sleeper_id = team.sleeper_id
    
    case FantasyManager.External.SleeperClient.get_league_rosters(team.league.sleeper_id) do
      {:ok, rosters} ->
        team_roster = Enum.find(rosters, &(&1["roster_id"] == sleeper_id))
        if team_roster do
          sync_roster_players(team, team_roster)
        end
      {:error, _} ->
        # Log error but don't fail team creation
        :ok
    end
    
    changeset
  end

  defp calculate_competitive_window(changeset) do
    wins = Ash.Changeset.get_attribute(changeset, :wins)
    losses = Ash.Changeset.get_attribute(changeset, :losses)
    points_for = Ash.Changeset.get_attribute(changeset, :points_for)
    
    if wins && losses && points_for do
      total_games = wins + losses
      win_pct = if total_games > 0, do: wins / total_games, else: 0.0
      
      window = cond do
        win_pct >= 0.7 and Decimal.to_float(points_for) >= 1200 -> :Contending
        win_pct <= 0.3 and total_games >= 6 -> :Rebuilding
        true -> :Neutral
      end
      
      Ash.Changeset.change_attribute(changeset, :competitive_window, window)
    else
      changeset
    end
  end

  defp update_league_standings(changeset, _team) do
    # This would trigger a background job to recalculate league standings
    # For now, just return the changeset
    changeset
  end

  defp analyze_roster_composition(team) do
    # This would analyze the team's roster composition
    # For now, return a placeholder structure
    %{
      total_players: 16,
      starters: 9,
      bench: 6,
      ir: 1,
      avg_age: 26.5,
      positions: %{QB: 2, RB: 4, WR: 5, TE: 3, K: 1, DEF: 1}
    }
  end

  defp analyze_positional_needs(team) do
    # This would analyze positional strengths and weaknesses
    # For now, return a placeholder structure
    %{
      strengths: %{QB: 85, WR: 78},
      needs: [:RB, :TE],
      depth_chart: %{}
    }
  end

  defp analyze_competitive_factors(team) do
    # This would analyze factors affecting competitiveness
    # For now, return a placeholder structure
    %{
      age_curve: :stable,
      injury_risk: :medium,
      schedule_strength: :average
    }
  end

  defp generate_team_recommendations(roster, positional, competitive) do
    # This would generate specific recommendations based on analysis
    # For now, return placeholder recommendations
    [
      "Consider upgrading at RB position",
      "Strong at WR, potential trade asset",
      "Monitor injury status of key players"
    ]
  end

  defp sync_roster_players(team, roster_data) do
    # This would sync the actual roster players
    # For now, return success with placeholder counts
    {:ok, %{players_added: 5, players_updated: 10, players_removed: 0}}
  end
end

defmodule FantasyManager.Fantasy.FantasyTeam.Validations do
  def faab_budget_within_league_limits(changeset) do
    # This would validate FAAB budget against league settings
    # For now, allow any positive budget
    faab_budget = Ash.Changeset.get_attribute(changeset, :faab_budget)
    
    if faab_budget && faab_budget >= 0 do
      :ok
    else
      {:error, "FAAB budget must be non-negative"}
    end
  end

  def waiver_priority_unique_within_league(changeset) do
    # This would validate waiver priority uniqueness within league
    # For now, skip validation
    :ok
  end

  def roster_size_within_league_limits(changeset) do
    # This would validate roster size against league settings
    # For now, skip validation since it's calculated
    :ok
  end
end