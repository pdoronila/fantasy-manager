defmodule FantasyManager.Fantasy.League do
  use Ash.Resource,
    domain: FantasyManager.Fantasy,
    data_layer: AshPostgres.DataLayer

  require Ash.Query
  alias FantasyManager.Fantasy.FantasyTeam

  postgres do
    table "leagues"
    repo FantasyManager.Repo

    references do
      reference :fantasy_teams, on_delete: :delete
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

  end

  changes do
    change after_action(&sync_teams_from_sleeper/3) do
      on [:create]
    end

    change before_action(&set_default_scoring_settings/2),
      on: [:create]

    change before_action(&validate_keeper_settings/2),
      on: [:create, :update]
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_from_sleeper do
      argument :sleeper_data, :map, allow_nil?: false
      
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
        
        IO.puts("=== sync_from_sleeper called with sleeper_id: #{sleeper_id}, full_sync: #{full_sync} ===")
        
        case FantasyManager.External.SleeperClient.get_league(sleeper_id) do
          {:ok, league_data} ->
            season = String.to_integer(league_data["season"])
            
            # Check if league already exists
            case Ash.Query.filter(__MODULE__, sleeper_id == ^sleeper_id and season == ^season) |> Ash.read_one() do
              {:ok, existing_league} when not is_nil(existing_league) ->
                # League exists, just sync teams
                sync_result = if full_sync do
                  sync_teams_and_rosters(existing_league)
                else
                  sync_teams_only(existing_league)
                end
                {:ok, Map.merge(%{status: "updated", league_id: existing_league.id}, sync_result)}
                
              {:ok, nil} ->
                # League doesn't exist, create it
                {:ok, league} = __MODULE__.create_from_sleeper!(league_data, authorize?: false)
                sync_result = if full_sync do
                  sync_teams_and_rosters(league)
                else
                  sync_teams_only(league)
                end
                {:ok, Map.merge(%{status: "created", league_id: league.id}, sync_result)}
                
              {:error, reason} ->
                {:error, %{error: "Failed to check for existing league", reason: reason}}
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
    define :create_from_sleeper, args: [:sleeper_data]
    define :update_keeper_settings, args: [:keeper_count, :dynasty_transition_year]
    define :update_trade_deadline, args: [:deadline_week]
    define :by_season, args: [:season]
    define :by_league_type, args: [:type]
    define :keeper_leagues
    define :dynasty_leagues
    define :active_leagues, args: [:current_season]
    define :sync_from_sleeper, args: [:sleeper_id, :full_sync]
    define :generate_schedule, args: [:season]

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

  defp sync_teams_from_sleeper(changeset, league, _context) do
    # Always sync teams when creating from sleeper
    sync_teams_only(league)
    {:ok, league}
  end

  defp set_default_scoring_settings(changeset, _context) do
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

  defp validate_keeper_settings(changeset, _context) do
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
    IO.puts("=== Starting sync_teams_only for league: #{league.name} (#{league.sleeper_id}) ===")
    
    case FantasyManager.External.SleeperClient.get_league_users(league.sleeper_id) do
      {:ok, users} ->
        IO.puts("Successfully fetched #{length(users)} users from Sleeper")
        case FantasyManager.External.SleeperClient.get_league_rosters(league.sleeper_id) do
          {:ok, rosters} ->
            IO.puts("Successfully fetched #{length(rosters)} rosters from Sleeper")
            teams_synced = sync_fantasy_teams(league, users, rosters)
            result = %{teams_updated: teams_synced, players_updated: 0, rosters_synced: 0}
            IO.puts("Sync completed. Result: #{inspect(result)}")
            result
          {:error, error} ->
            IO.puts("Failed to fetch rosters: #{inspect(error)}")
            %{teams_updated: 0, players_updated: 0, rosters_synced: 0}
        end
      {:error, error} ->
        IO.puts("Failed to fetch users: #{inspect(error)}")
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
    # Create a map of user_id to user data for easy lookup
    user_map = users |> Enum.reduce(%{}, fn user, acc -> Map.put(acc, user["user_id"], user) end)
    
    # Sync each roster as a fantasy team
    teams_synced = Enum.reduce(rosters, 0, fn roster, acc ->
      user_id = roster["owner_id"]
      user_data = Map.get(user_map, user_id, %{})
      
      # Check if team already exists
      roster_id_string = to_string(roster["roster_id"])
      case Ash.Query.filter(FantasyTeam, sleeper_id == ^roster_id_string and league_id == ^league.id) 
           |> Ash.read_one() do
        {:ok, nil} ->
          # Team doesn't exist, create it
          case create_fantasy_team_from_sleeper(roster, user_data, league.id) do
            {:ok, _team} -> acc + 1
            {:error, _} -> acc
          end
        {:ok, _existing_team} ->
          # Team exists, could update it here in the future
          acc
        {:error, _} -> acc
      end
    end)
    
    teams_synced
  end
  
  defp create_fantasy_team_from_sleeper(roster_data, user_data, league_id) do
    # Debug logging
    IO.puts("Creating team from Sleeper data:")
    IO.inspect(roster_data, label: "Roster Data")
    IO.inspect(user_data, label: "User Data")
    IO.puts("League ID: #{league_id}")
    
    result = FantasyTeam.create_from_sleeper(
      roster_data,
      user_data,
      league_id,
      authorize?: false
    )
    
    case result do
      {:ok, team} -> 
        IO.puts("Successfully created team: #{team.name}")
        {:ok, team}
      {:error, error} -> 
        IO.puts("Failed to create team:")
        IO.inspect(error)
        {:error, error}
    end
  end

  defp sync_team_rosters(league, rosters) do
    # Load existing teams for this league
    {:ok, teams} = FantasyTeam.by_league(league.id)
    
    players_synced = 0
    rosters_synced = 0
    
    {players_synced, rosters_synced} = 
      Enum.reduce(rosters, {0, 0}, fn roster_data, {players_acc, rosters_acc} ->
        roster_id = to_string(roster_data["roster_id"])
        
        # Find the team with this sleeper_id
        case Enum.find(teams, &(&1.sleeper_id == roster_id)) do
          nil -> 
            {players_acc, rosters_acc}
          team ->
            case sync_single_team_roster(team, roster_data) do
              {:ok, %{players_added: added}} -> 
                {players_acc + added, rosters_acc + 1}
              {:error, _} -> 
                {players_acc, rosters_acc}
            end
        end
      end)
    
    {players_synced, rosters_synced}
  end
  
  defp sync_single_team_roster(team, roster_data) do
    alias FantasyManager.Fantasy.{Player, FantasyTeamPlayer}
    
    # Get player IDs from the roster
    player_ids = roster_data["players"] || []
    starters = roster_data["starters"] || []
    
    # Clear existing roster
    {:ok, existing_players} = FantasyTeamPlayer.by_team(team.id)
    for existing <- existing_players do
      FantasyTeamPlayer.destroy!(existing)
    end
    
    # Add current roster players
    players_added = 
      player_ids
      |> Enum.reduce(0, fn sleeper_player_id, acc ->
        case Player.by_sleeper_id(sleeper_player_id) do
          {:ok, []} -> 
            # Player doesn't exist in our system, skip for now
            acc
          {:ok, [player | _]} ->
            roster_position = if sleeper_player_id in starters do
              :Starter 
            else 
              :Bench
            end
            
            case FantasyTeamPlayer.create(%{
              fantasy_team_id: team.id,
              player_id: player.id,
              roster_position: roster_position,
              acquisition_date: Date.utc_today(),
              acquisition_type: :Draft
            }) do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          {:error, _} ->
            acc
        end
      end)
    
    {:ok, %{players_added: players_added, players_removed: length(existing_players)}}
  rescue 
    error ->
      {:error, error}
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