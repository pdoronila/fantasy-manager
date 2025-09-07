defmodule FantasyManager.Fantasy.League do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "leagues"
    repo FantasyManager.Repo

    references do
      reference :fantasy_teams, on_delete: :delete
      reference :matchups, on_delete: :delete
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
      constraints [min_length: 1, max_length: 100]
    end

    attribute :season, :integer do
      allow_nil? false
      constraints [min: 2020, max: 2030]
    end

    attribute :league_type, :atom do
      allow_nil? false
      default :redraft
      constraints [one_of: [:keeper, :dynasty, :redraft]]
    end

    attribute :scoring_format, :atom do
      allow_nil? false
      default :PPR
      constraints [one_of: [:PPR, :half_ppr, :standard, :superflex]]
    end

    attribute :roster_size, :integer do
      allow_nil? false
      default 16
      constraints [min: 10, max: 20]
    end

    attribute :keeper_count, :integer do
      allow_nil? true
      constraints [min: 0, max: 15]
    end

    attribute :dynasty_transition_year, :integer do
      allow_nil? true
      constraints [min: 2020, max: 2030]
    end

    attribute :trade_deadline_week, :integer do
      allow_nil? false
      default 10
      constraints [min: 1, max: 17]
    end

    attribute :waiver_type, :atom do
      allow_nil? false
      default :faab
      constraints [one_of: [:faab, :rolling, :reverse]]
    end

    attribute :playoff_teams, :integer do
      allow_nil? false
      default 6
      constraints [min: 2, max: 8]
    end

    attribute :regular_season_weeks, :integer do
      allow_nil? false
      default 14
      constraints [min: 12, max: 17]
    end

    attribute :draft_type, :atom do
      allow_nil? false
      default :snake
      constraints [one_of: [:snake, :linear, :auction]]
    end

    attribute :settings, :map do
      allow_nil? false
      default %{}
    end

    attribute :scoring_settings, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    has_many :fantasy_teams, FantasyManager.Fantasy.FantasyTeam do
      destination_attribute :league_id
    end

    has_many :matchups, FantasyManager.Fantasy.Matchup do
      destination_attribute :league_id
    end
  end

  calculations do
    calculate :team_count, :integer, expr(
      fragment("SELECT COUNT(*) FROM fantasy_teams WHERE league_id = ?", [id])
    )

    calculate :is_keeper_eligible, :boolean, expr(
      league_type in [:keeper, :dynasty]
    )

    calculate :is_dynasty, :boolean, expr(
      league_type == :dynasty
    )

    calculate :current_week, :integer, expr(
      fragment("
        SELECT COALESCE(
          (SELECT MAX(week) FROM matchups 
           WHERE league_id = ? AND season = ? 
           AND (team_1_score IS NOT NULL OR team_2_score IS NOT NULL)
          ) + 1, 1
        )
      ", [id, season])
    )

    calculate :playoff_start_week, :integer, expr(
      regular_season_weeks + 1
    )

    calculate :championship_week, :integer, expr(
      regular_season_weeks + 3
    )

    calculate :trade_deadline_passed, :boolean, expr(
      fragment("
        SELECT CASE 
          WHEN EXTRACT(month FROM now()) >= 9 THEN
            (SELECT COUNT(*) > 0 FROM matchups 
             WHERE league_id = ? AND season = ? AND week > ?)
          ELSE false
        END
      ", [id, season, trade_deadline_week])
    )
  end

  validations do
    validate present([:name, :sleeper_id, :season, :league_type])

    validate compare(:season, greater_than_or_equal_to: 2020, less_than_or_equal_to: 2030) do
      message "Season must be between 2020 and 2030"
    end

    validate compare(:roster_size, greater_than_or_equal_to: 10, less_than_or_equal_to: 20) do
      message "Roster size must be between 10 and 20"
    end

    validate compare(:trade_deadline_week, greater_than_or_equal_to: 1, less_than_or_equal_to: 17) do
      message "Trade deadline must be between weeks 1 and 17"
    end

    validate FantasyManager.Fantasy.League.Validations.keeper_count_valid(),
      on: [:create, :update]

    validate FantasyManager.Fantasy.League.Validations.dynasty_transition_year_valid(),
      on: [:create, :update]
  end

  changes do
    change after_action(:sync_teams_from_sleeper) do
      on [:create]
    end

    change before_action(:set_default_scoring_settings),
      on: [:create]

    change before_action(:validate_keeper_settings),
      on: [:create, :update]
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_from_sleeper do
      argument :sleeper_data, :map, allow_nil?: false
      argument :sync_teams, :boolean, default: true
      
      change fn changeset, context ->
        sleeper_data = Ash.Changeset.get_argument(changeset, :sleeper_data)
        
        changeset
        |> Ash.Changeset.change_attribute(:sleeper_id, sleeper_data["league_id"])
        |> Ash.Changeset.change_attribute(:name, sleeper_data["name"])
        |> Ash.Changeset.change_attribute(:season, sleeper_data["season"])
        |> Ash.Changeset.change_attribute(:league_type, determine_league_type(sleeper_data))
        |> Ash.Changeset.change_attribute(:scoring_format, determine_scoring_format(sleeper_data))
        |> Ash.Changeset.change_attribute(:roster_size, get_roster_size(sleeper_data))
        |> Ash.Changeset.change_attribute(:settings, sleeper_data["settings"] || %{})
        |> Ash.Changeset.change_attribute(:scoring_settings, sleeper_data["scoring_settings"] || %{})
      end
    end

    update :update_keeper_settings do
      argument :keeper_count, :integer
      argument :dynasty_transition_year, :integer

      change set_attribute(:keeper_count, arg(:keeper_count))
      change set_attribute(:dynasty_transition_year, arg(:dynasty_transition_year))
    end

    update :update_trade_deadline do
      argument :deadline_week, :integer, allow_nil?: false

      validate compare(:deadline_week, greater_than_or_equal_to: 1, less_than_or_equal_to: 17)

      change set_attribute(:trade_deadline_week, arg(:deadline_week))
    end

    read :by_season do
      argument :season, :integer, allow_nil?: false

      filter expr(season == ^arg(:season))
    end

    read :by_league_type do
      argument :type, :atom, allow_nil?: false

      filter expr(league_type == ^arg(:type))
    end

    read :keeper_leagues do
      filter expr(league_type in [:keeper, :dynasty])
    end

    read :dynasty_leagues do
      filter expr(league_type == :dynasty)
    end

    read :active_leagues do
      argument :current_season, :integer, default: 2025

      filter expr(season >= ^arg(:current_season))
    end

    action :sync_from_sleeper, :map do
      argument :sleeper_id, :string, allow_nil?: false
      argument :full_sync, :boolean, default: false

      run fn input, context ->
        sleeper_id = input.arguments.sleeper_id
        full_sync = input.arguments.full_sync
        
        case FantasyManager.External.SleeperClient.get_league(sleeper_id) do
          {:ok, league_data} ->
            case __MODULE__.get_by_sleeper_id(sleeper_id, authorize?: false) do
              {:ok, league} ->
                {:ok, updated_league} = __MODULE__.update_from_sleeper!(league, league_data, authorize?: false)
                
                sync_result = if full_sync do
                  sync_teams_and_rosters(updated_league)
                else
                  sync_teams_only(updated_league)
                end
                
                {:ok, Map.merge(%{status: "updated", league_id: updated_league.id}, sync_result)}
                
              {:error, _} ->
                {:ok, league} = __MODULE__.create_from_sleeper!(league_data, authorize?: false)
                sync_result = sync_teams_and_rosters(league)
                {:ok, Map.merge(%{status: "created", league_id: league.id}, sync_result)}
            end
          {:error, reason} ->
            {:error, %{error: "Failed to sync from Sleeper", reason: reason}}
        end
      end
    end

    action :generate_schedule, :map do
      argument :season, :integer, allow_nil?: false
      
      run fn input, context ->
        season = input.arguments.season
        league = context.resource
        
        # Generate round-robin schedule
        case generate_matchup_schedule(league, season) do
          {:ok, matchups} ->
            {:ok, %{matchups_created: length(matchups)}}
          {:error, reason} ->
            {:error, %{error: "Failed to generate schedule", reason: reason}}
        end
      end
    end
  end

  code_interface do
    domain FantasyManager.Fantasy

    define :create
    define :read
    define :update
    define :destroy
    define :create_from_sleeper, args: [:sleeper_data, :sync_teams]
    define :update_keeper_settings, args: [:keeper_count, :dynasty_transition_year]
    define :update_trade_deadline, args: [:deadline_week]
    define :by_season, args: [:season]
    define :by_league_type, args: [:type]
    define :keeper_leagues
    define :dynasty_leagues
    define :active_leagues, args: [:current_season]
    define :sync_from_sleeper, args: [:sleeper_id, :full_sync]
    define :generate_schedule, args: [:season]

    define :get_by_sleeper_id, get_by: [:sleeper_id]
    define :update_from_sleeper, action: :create_from_sleeper
    define :update_from_sleeper!, action: :create_from_sleeper
  end

  identities do
    identity :unique_sleeper_id_season, [:sleeper_id, :season]
  end

  # Helper functions
  defp determine_league_type(%{"settings" => settings}) do
    cond do
      Map.get(settings, "type") == 2 -> :dynasty
      Map.get(settings, "keeper_count", 0) > 0 -> :keeper
      true -> :redraft
    end
  end
  defp determine_league_type(_), do: :redraft

  defp determine_scoring_format(%{"scoring_settings" => scoring}) do
    ppr = Map.get(scoring, "rec", 0)
    
    cond do
      ppr >= 1.0 -> :PPR
      ppr >= 0.5 -> :half_ppr
      ppr == 0.0 -> :standard
      true -> :PPR
    end
  end
  defp determine_scoring_format(_), do: :PPR

  defp get_roster_size(%{"settings" => settings}) do
    Map.get(settings, "roster_positions", []) |> length() |> max(16)
  end
  defp get_roster_size(_), do: 16

  defp sync_teams_from_sleeper(changeset, league) do
    if Ash.Changeset.get_argument(changeset, :sync_teams, true) do
      sync_teams_only(league)
    end
    changeset
  end

  defp set_default_scoring_settings(changeset) do
    scoring_format = Ash.Changeset.get_attribute(changeset, :scoring_format)
    
    default_settings = case scoring_format do
      :PPR -> %{"rec" => 1.0, "pass_td" => 4, "rush_td" => 6, "rec_td" => 6}
      :half_ppr -> %{"rec" => 0.5, "pass_td" => 4, "rush_td" => 6, "rec_td" => 6}
      :standard -> %{"rec" => 0.0, "pass_td" => 4, "rush_td" => 6, "rec_td" => 6}
      :superflex -> %{"rec" => 1.0, "pass_td" => 4, "rush_td" => 6, "rec_td" => 6, "bonus_pass_yd_300" => 3}
      _ -> %{}
    end
    
    current_settings = Ash.Changeset.get_attribute(changeset, :scoring_settings) || %{}
    merged_settings = Map.merge(default_settings, current_settings)
    
    Ash.Changeset.change_attribute(changeset, :scoring_settings, merged_settings)
  end

  defp validate_keeper_settings(changeset) do
    league_type = Ash.Changeset.get_attribute(changeset, :league_type)
    keeper_count = Ash.Changeset.get_attribute(changeset, :keeper_count)
    roster_size = Ash.Changeset.get_attribute(changeset, :roster_size)
    
    cond do
      league_type in [:keeper, :dynasty] and is_nil(keeper_count) ->
        Ash.Changeset.add_error(changeset, field: :keeper_count, message: "Keeper count required for keeper/dynasty leagues")
      
      keeper_count && keeper_count > roster_size ->
        Ash.Changeset.add_error(changeset, field: :keeper_count, message: "Keeper count cannot exceed roster size")
      
      true -> 
        changeset
    end
  end

  defp sync_teams_only(league) do
    case FantasyManager.External.SleeperClient.get_league_users(league.sleeper_id) do
      {:ok, users} ->
        case FantasyManager.External.SleeperClient.get_league_rosters(league.sleeper_id) do
          {:ok, rosters} ->
            teams_synced = sync_fantasy_teams(league, users, rosters)
            %{teams_updated: teams_synced, players_updated: 0, rosters_synced: 0}
          {:error, _} ->
            %{teams_updated: 0, players_updated: 0, rosters_synced: 0}
        end
      {:error, _} ->
        %{teams_updated: 0, players_updated: 0, rosters_synced: 0}
    end
  end

  defp sync_teams_and_rosters(league) do
    case FantasyManager.External.SleeperClient.get_league_users(league.sleeper_id) do
      {:ok, users} ->
        case FantasyManager.External.SleeperClient.get_league_rosters(league.sleeper_id) do
          {:ok, rosters} ->
            teams_synced = sync_fantasy_teams(league, users, rosters)
            {players_synced, rosters_synced} = sync_team_rosters(league, rosters)
            %{teams_updated: teams_synced, players_updated: players_synced, rosters_synced: rosters_synced}
          {:error, _} ->
            %{teams_updated: 0, players_updated: 0, rosters_synced: 0}
        end
      {:error, _} ->
        %{teams_updated: 0, players_updated: 0, rosters_synced: 0}
    end
  end

  defp sync_fantasy_teams(league, users, rosters) do
    # This would implement the actual team synchronization logic
    # For now, return a placeholder count
    length(users)
  end

  defp sync_team_rosters(league, rosters) do
    # This would implement the actual roster synchronization logic
    # For now, return placeholder counts
    total_players = rosters |> Enum.flat_map(&(Map.get(&1, "players", []))) |> length()
    {total_players, length(rosters)}
  end

  defp generate_matchup_schedule(league, season) do
    # This would implement round-robin schedule generation
    # For now, return success with empty list
    {:ok, []}
  end
end

defmodule FantasyManager.Fantasy.League.Validations do
  def keeper_count_valid(changeset) do
    league_type = Ash.Changeset.get_attribute(changeset, :league_type)
    keeper_count = Ash.Changeset.get_attribute(changeset, :keeper_count)
    roster_size = Ash.Changeset.get_attribute(changeset, :roster_size)
    
    cond do
      league_type in [:keeper, :dynasty] and is_nil(keeper_count) ->
        {:error, "Keeper count is required for keeper and dynasty leagues"}
        
      keeper_count && keeper_count > roster_size ->
        {:error, "Keeper count cannot exceed roster size"}
        
      keeper_count && keeper_count < 0 ->
        {:error, "Keeper count must be non-negative"}
        
      true -> 
        :ok
    end
  end

  def dynasty_transition_year_valid(changeset) do
    league_type = Ash.Changeset.get_attribute(changeset, :league_type)
    dynasty_transition_year = Ash.Changeset.get_attribute(changeset, :dynasty_transition_year)
    season = Ash.Changeset.get_attribute(changeset, :season)
    
    cond do
      league_type == :dynasty and is_nil(dynasty_transition_year) ->
        # Dynasty transition year is optional, but if set should be valid
        :ok
        
      dynasty_transition_year && dynasty_transition_year < season ->
        {:error, "Dynasty transition year cannot be in the past"}
        
      dynasty_transition_year && dynasty_transition_year > season + 5 ->
        {:error, "Dynasty transition year cannot be more than 5 years in the future"}
        
      true -> 
        :ok
    end
  end
end