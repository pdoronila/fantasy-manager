defmodule FantasyManager.Fantasy.Player do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "players"
    repo FantasyManager.Repo

    references do
      reference :player_stats, on_delete: :delete
      reference :fantasy_team_players, on_delete: :delete
      reference :projections, on_delete: :delete
      reference :keeper_contracts, on_delete: :delete
    end
  end

  state_machine do
    initial_state :active
    default_initial_state :active

    states do
      state :active
      state :injured
      state :retired
    end

    transitions do
      transition :injure, from: :active, to: :injured
      transition :recover, from: :injured, to: :active
      transition :retire, from: [:active, :injured], to: :retired
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sleeper_id, :string do
      allow_nil? false
      constraints [match: ~r/^[a-zA-Z0-9_]+$/]
    end

    attribute :name, :string do
      allow_nil? false
      constraints [min_length: 2, max_length: 100]
    end

    attribute :position, :atom do
      allow_nil? false
      constraints [one_of: [:QB, :RB, :WR, :TE, :K, :DEF]]
    end

    attribute :nfl_team, :string do
      constraints [max_length: 3]
    end

    attribute :injury_status, :atom do
      allow_nil? false
      default :Active
      constraints [one_of: [:Active, :Questionable, :Doubtful, :Out, :IR, :PUP]]
    end

    attribute :years_pro, :integer do
      allow_nil? false
      default 0
      constraints [min: 0, max: 30]
    end

    attribute :age, :integer do
      constraints [min: 18, max: 50]
    end

    attribute :rookie_year, :integer do
      constraints [min: 1950, max: 2030]
    end

    attribute :dynasty_value, :decimal do
      allow_nil? false
      default 0.0
      constraints [min: 0.0, max: 100.0]
    end

    attribute :keeper_eligible, :boolean do
      allow_nil? false
      default true
    end

    timestamps()
  end

  relationships do
    has_many :player_stats, FantasyManager.Fantasy.PlayerStat do
      destination_attribute :player_id
    end

    has_many :fantasy_team_players, FantasyManager.Fantasy.FantasyTeamPlayer do
      destination_attribute :player_id
    end

    has_many :projections, FantasyManager.Fantasy.WeeklyProjection do
      destination_attribute :player_id
    end

    has_many :keeper_contracts, FantasyManager.Fantasy.KeeperContract do
      destination_attribute :player_id
    end
  end

  calculations do
    calculate :current_season_stats, {:array, :map}, expr(
      fragment("
        SELECT 
          COALESCE(SUM(passing_yards), 0) as passing_yards,
          COALESCE(SUM(passing_tds), 0) as passing_tds,
          COALESCE(SUM(rushing_yards), 0) as rushing_yards,
          COALESCE(SUM(receiving_yards), 0) as receiving_yards,
          COALESCE(SUM(fantasy_points), 0) as fantasy_points
        FROM player_stats 
        WHERE player_id = ? AND season = EXTRACT(year FROM now())
      ", [id])
    )

    calculate :average_fantasy_points, :decimal, expr(
      fragment("
        SELECT COALESCE(AVG(fantasy_points), 0) 
        FROM player_stats 
        WHERE player_id = ? AND season >= EXTRACT(year FROM now()) - 2
      ", [id])
    )

    calculate :injury_risk_score, :decimal, expr(
      case injury_status do
        :Active -> 0.1
        :Questionable -> 0.4
        :Doubtful -> 0.7
        :Out -> 1.0
        :IR -> 1.0
        :PUP -> 1.0
      end
    )

    calculate :age_adjusted_dynasty_value, :decimal, expr(
      case do
        age <= 24 -> dynasty_value * 1.2
        age <= 27 -> dynasty_value
        age <= 30 -> dynasty_value * 0.8
        age > 30 -> dynasty_value * 0.6
      end
    )
  end

  validations do
    validate compare(:dynasty_value, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
    validate compare(:years_pro, greater_than_or_equal_to: 0)
    
    validate match(:name, ~r/.{2,}/) do
      message "Name must be at least 2 characters long"
    end

    validate present([:name, :position, :sleeper_id]) do
      message "Required fields must be present"
    end

    validate attribute_does_not_equal(:position, nil) do
      message "Position must be specified"
    end
  end

  changes do
    change before_action(:update_injury_status_from_state) do
      on [:update]
    end

    change after_action(:sync_with_sleeper) do
      on [:create, :update]
      only_when_attribute_changes [:sleeper_id]
    end

    change before_action(:calculate_dynasty_value) do
      on [:create, :update]
      only_when_attribute_changes [:age, :position, :years_pro]
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_from_sleeper do
      argument :sleeper_data, :map, allow_nil?: false
      
      change fn changeset, context ->
        sleeper_data = Ash.Changeset.get_argument(changeset, :sleeper_data)
        
        changeset
        |> Ash.Changeset.change_attribute(:sleeper_id, sleeper_data["player_id"])
        |> Ash.Changeset.change_attribute(:name, sleeper_data["full_name"])
        |> Ash.Changeset.change_attribute(:position, normalize_position(sleeper_data["position"]))
        |> Ash.Changeset.change_attribute(:nfl_team, sleeper_data["team"])
        |> Ash.Changeset.change_attribute(:years_pro, sleeper_data["years_exp"] || 0)
        |> Ash.Changeset.change_attribute(:age, calculate_age(sleeper_data))
        |> Ash.Changeset.change_attribute(:injury_status, normalize_injury_status(sleeper_data["injury_status"]))
      end
    end

    update :update_dynasty_value do
      argument :new_value, :decimal, allow_nil?: false

      validate compare(:new_value, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)

      change set_attribute(:dynasty_value, arg(:new_value))
    end

    update :update_injury_status do
      argument :status, :atom, allow_nil?: false
      argument :injury_details, :string

      change set_attribute(:injury_status, arg(:status))
      
      change fn changeset, context ->
        case Ash.Changeset.get_argument(changeset, :status) do
          status when status in [:Questionable, :Doubtful, :Out, :IR, :PUP] ->
            transition_state(changeset, :injured)
          :Active ->
            transition_state(changeset, :active)
          _ ->
            changeset
        end
      end
    end

    read :by_position do
      argument :position, :atom, allow_nil?: false

      filter expr(position == ^arg(:position))
    end

    read :by_nfl_team do
      argument :team, :string, allow_nil?: false

      filter expr(nfl_team == ^arg(:team))
    end

    read :dynasty_prospects do
      argument :min_value, :decimal, default: 50.0
      argument :max_age, :integer, default: 26

      filter expr(dynasty_value >= ^arg(:min_value) and (is_nil(age) or age <= ^arg(:max_age)))
    end

    read :available_for_keeper do
      filter expr(keeper_eligible == true)
    end

    read :search do
      argument :query, :string, allow_nil?: false

      filter expr(ilike(name, ^("%#{arg(:query)}%")))
    end

    read :injury_report do
      filter expr(injury_status != :Active)
    end

    action :sync_from_sleeper, :map do
      argument :sleeper_id, :string, allow_nil?: false

      run fn input, context ->
        sleeper_id = input.arguments.sleeper_id
        
        case FantasyManager.External.SleeperClient.get_player(sleeper_id) do
          {:ok, player_data} ->
            case __MODULE__.get_by_sleeper_id(sleeper_id, authorize?: false) do
              {:ok, player} ->
                __MODULE__.update_from_sleeper!(player, player_data, authorize?: false)
                {:ok, %{status: "updated", player_id: player.id}}
              {:error, _} ->
                {:ok, player} = __MODULE__.create_from_sleeper!(player_data, authorize?: false)
                {:ok, %{status: "created", player_id: player.id}}
            end
          {:error, reason} ->
            {:error, %{error: "Failed to sync from Sleeper", reason: reason}}
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
    define :create_from_sleeper, args: [:sleeper_data]
    define :update_dynasty_value, args: [:new_value]
    define :update_injury_status, args: [:status, :injury_details]
    define :by_position, args: [:position]
    define :by_nfl_team, args: [:team]
    define :dynasty_prospects, args: [:min_value, :max_age]
    define :available_for_keeper
    define :search, args: [:query]
    define :injury_report
    define :sync_from_sleeper, args: [:sleeper_id]

    define :get_by_sleeper_id, get_by: [:sleeper_id]
    define :update_from_sleeper, action: :create_from_sleeper
    define :update_from_sleeper!, action: :create_from_sleeper
  end

  identities do
    identity :unique_sleeper_id, [:sleeper_id]
  end

  # Private helper functions
  defp normalize_position(nil), do: nil
  defp normalize_position(position) when is_binary(position) do
    case String.upcase(position) do
      "QB" -> :QB
      "RB" -> :RB
      "WR" -> :WR
      "TE" -> :TE
      "K" -> :K
      "DEF" -> :DEF
      _ -> nil
    end
  end

  defp normalize_injury_status(nil), do: :Active
  defp normalize_injury_status(status) when is_binary(status) do
    case String.downcase(status) do
      "active" -> :Active
      "questionable" -> :Questionable
      "doubtful" -> :Doubtful
      "out" -> :Out
      "ir" -> :IR
      "pup" -> :PUP
      _ -> :Active
    end
  end

  defp calculate_age(%{"birth_date" => birth_date}) when is_binary(birth_date) do
    case Date.from_iso8601(birth_date) do
      {:ok, date} ->
        today = Date.utc_today()
        Date.diff(today, date) |> div(365)
      _ ->
        nil
    end
  end
  defp calculate_age(_), do: nil

  defp update_injury_status_from_state(changeset) do
    case Ash.Changeset.get_data(changeset) do
      %{state: :injured} -> Ash.Changeset.change_attribute(changeset, :injury_status, :Questionable)
      %{state: :active} -> Ash.Changeset.change_attribute(changeset, :injury_status, :Active)
      _ -> changeset
    end
  end

  defp sync_with_sleeper(changeset, _result) do
    # Background job to sync with Sleeper API
    sleeper_id = Ash.Changeset.get_attribute(changeset, :sleeper_id)
    if sleeper_id do
      # This would trigger a background job in a real implementation
      # Oban.insert(FantasyManager.Workers.SyncPlayerWorker.new(%{sleeper_id: sleeper_id}))
    end
    changeset
  end

  defp calculate_dynasty_value(changeset) do
    position = Ash.Changeset.get_attribute(changeset, :position)
    age = Ash.Changeset.get_attribute(changeset, :age)
    years_pro = Ash.Changeset.get_attribute(changeset, :years_pro)

    if position && age && years_pro do
      base_value = case position do
        :QB -> 75.0
        :RB -> 65.0
        :WR -> 70.0
        :TE -> 60.0
        :K -> 20.0
        :DEF -> 25.0
      end

      # Adjust for age
      age_modifier = cond do
        age <= 23 -> 1.3
        age <= 26 -> 1.1
        age <= 29 -> 1.0
        age <= 32 -> 0.7
        true -> 0.4
      end

      # Adjust for experience
      exp_modifier = cond do
        years_pro == 0 -> 0.8  # Rookie discount
        years_pro <= 3 -> 1.0
        years_pro <= 6 -> 1.1
        years_pro <= 10 -> 0.9
        true -> 0.6
      end

      calculated_value = base_value * age_modifier * exp_modifier
      clamped_value = max(0.0, min(100.0, calculated_value))

      Ash.Changeset.change_attribute(changeset, :dynasty_value, Decimal.new(clamped_value))
    else
      changeset
    end
  end

  defp transition_state(changeset, new_state) do
    case new_state do
      :injured -> AshStateMachine.transition_state(changeset, :injure)
      :active -> AshStateMachine.transition_state(changeset, :recover)
      _ -> changeset
    end
  end
end