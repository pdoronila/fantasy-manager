defmodule FantasyManager.Fantasy.WeeklyProjection do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "weekly_projections"
    repo FantasyManager.Repo

    custom_indexes do
      index ["player_id", "season", "week"], unique: true
      index ["season", "week"]
      index ["projection_model"]
      index ["confidence_score"]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :season, :integer do
      allow_nil? false
      constraints [min: 2020, max: 2030]
    end

    attribute :week, :integer do
      allow_nil? false
      constraints [min: 1, max: 18]
    end

    attribute :projected_points, :decimal do
      allow_nil? false
      constraints [min: 0.0, max: 100.0]
    end

    attribute :confidence_score, :decimal do
      allow_nil? false
      default 0.5
      constraints [min: 0.0, max: 1.0]
    end

    attribute :projection_model, :string do
      allow_nil? false
      default "claude-3-5-sonnet"
      constraints [min_length: 1, max_length: 50]
    end

    attribute :factors_considered, :map do
      allow_nil? false
      default %{}
    end

    attribute :created_by, :string do
      allow_nil? false
      constraints [min_length: 1, max_length: 100]
    end

    attribute :player_id, :uuid do
      allow_nil? false
    end

    # Detailed projection breakdown
    attribute :passing_yards, :decimal do
      constraints [min: 0.0]
    end

    attribute :passing_tds, :decimal do
      constraints [min: 0.0]
    end

    attribute :passing_ints, :decimal do
      constraints [min: 0.0]
    end

    attribute :rushing_yards, :decimal do
      constraints [min: 0.0]
    end

    attribute :rushing_tds, :decimal do
      constraints [min: 0.0]
    end

    attribute :receiving_yards, :decimal do
      constraints [min: 0.0]
    end

    attribute :receiving_tds, :decimal do
      constraints [min: 0.0]
    end

    attribute :receptions, :decimal do
      constraints [min: 0.0]
    end

    attribute :targets, :decimal do
      constraints [min: 0.0]
    end

    # Contextual factors
    attribute :opponent, :string do
      constraints [max_length: 3]
    end

    attribute :game_environment, :atom do
      constraints [one_of: [:home, :away, :neutral]]
    end

    attribute :weather_impact, :decimal do
      constraints [min: -1.0, max: 1.0]
    end

    attribute :injury_risk_factor, :decimal do
      constraints [min: 0.0, max: 1.0]
    end

    attribute :matchup_difficulty, :atom do
      constraints [one_of: [:easy, :moderate, :difficult, :elite]]
    end

    timestamps()
  end

  relationships do
    belongs_to :player, FantasyManager.Fantasy.Player do
      source_attribute :player_id
      destination_attribute :id
    end
  end

  calculations do
    calculate :projection_accuracy, :decimal, expr(
      fragment("
        SELECT CASE 
          WHEN ps.fantasy_points IS NOT NULL THEN
            1.0 - ABS(? - ps.fantasy_points) / GREATEST(ps.fantasy_points, 1.0)
          ELSE NULL
        END
        FROM player_stats ps 
        WHERE ps.player_id = ? AND ps.season = ? AND ps.week = ?
      ", [projected_points, player_id, season, week])
    )

    calculate :is_stale, :boolean, expr(
      fragment("? < now() - INTERVAL '3 days'", [inserted_at])
    )

    calculate :days_until_game, :integer, expr(
      fragment("
        CASE 
          WHEN ? BETWEEN 1 AND 17 THEN
            EXTRACT(days FROM (
              date_trunc('week', now()) + INTERVAL '? weeks' + INTERVAL '4 days'
            ) - now())::int
          ELSE NULL
        END
      ", [week, week - 1])
    )

    calculate :adjusted_projection, :decimal, expr(
      projected_points * 
      (1.0 - (injury_risk_factor * 0.3)) *
      (1.0 + weather_impact * 0.1) *
      cond do
        matchup_difficulty == :easy -> 1.15
        matchup_difficulty == :moderate -> 1.0
        matchup_difficulty == :difficult -> 0.85
        matchup_difficulty == :elite -> 0.7
        true -> 1.0
      end
    )

    calculate :ceiling_projection, :decimal, expr(
      projected_points * (1.0 + confidence_score * 0.5)
    )

    calculate :floor_projection, :decimal, expr(
      projected_points * (1.0 - confidence_score * 0.4)
    )
  end

  validations do
    validate present([:season, :week, :projected_points, :player_id, :created_by])

    validate compare(:season, greater_than_or_equal_to: 2020, less_than_or_equal_to: 2030) do
      message "Season must be between 2020 and 2030"
    end

    validate compare(:week, greater_than_or_equal_to: 1, less_than_or_equal_to: 18) do
      message "Week must be between 1 and 18"
    end

    validate compare(:projected_points, greater_than_or_equal_to: 0.0) do
      message "Projected points must be non-negative"
    end

    validate compare(:confidence_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0) do
      message "Confidence score must be between 0 and 1"
    end

    validate FantasyManager.Fantasy.WeeklyProjection.Validations.projection_not_in_past()
    validate FantasyManager.Fantasy.WeeklyProjection.Validations.stat_projections_consistent()
  end

  changes do
    change before_action(:set_creation_metadata) do
      on [:create]
    end

    change before_action(:validate_projection_factors) do
      on [:create, :update]
    end

    change after_action(:cache_projection) do
      on [:create, :update]
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :generate_ai_projection do
      argument :player_id, :uuid, allow_nil?: false
      argument :season, :integer, allow_nil?: false
      argument :week, :integer, allow_nil?: false
      argument :context_factors, :map, default: %{}
      
      change fn changeset, context ->
        player_id = Ash.Changeset.get_argument(changeset, :player_id)
        season = Ash.Changeset.get_argument(changeset, :season)
        week = Ash.Changeset.get_argument(changeset, :week)
        context_factors = Ash.Changeset.get_argument(changeset, :context_factors)
        
        case generate_ai_projection_data(player_id, season, week, context_factors) do
          {:ok, projection_data} ->
            changeset
            |> Ash.Changeset.change_attribute(:player_id, player_id)
            |> Ash.Changeset.change_attribute(:season, season)
            |> Ash.Changeset.change_attribute(:week, week)
            |> Ash.Changeset.change_attribute(:projected_points, projection_data.projected_points)
            |> Ash.Changeset.change_attribute(:confidence_score, projection_data.confidence_score)
            |> Ash.Changeset.change_attribute(:factors_considered, projection_data.factors_considered)
            |> Ash.Changeset.change_attribute(:passing_yards, projection_data[:passing_yards])
            |> Ash.Changeset.change_attribute(:passing_tds, projection_data[:passing_tds])
            |> Ash.Changeset.change_attribute(:rushing_yards, projection_data[:rushing_yards])
            |> Ash.Changeset.change_attribute(:receiving_yards, projection_data[:receiving_yards])
            |> Ash.Changeset.change_attribute(:opponent, context_factors[:opponent])
            |> Ash.Changeset.change_attribute(:matchup_difficulty, context_factors[:matchup_difficulty])
            
          {:error, reason} ->
            Ash.Changeset.add_error(changeset, field: :projected_points, message: "Failed to generate AI projection: #{reason}")
        end
      end
    end

    update :adjust_projection do
      argument :adjustment_factor, :decimal, allow_nil?: false
      argument :reason, :string, allow_nil?: false

      validate compare(:adjustment_factor, greater_than: 0.0, less_than: 3.0) do
        message "Adjustment factor must be between 0 and 3"
      end

      change fn changeset, context ->
        current_projection = Ash.Changeset.get_data(changeset).projected_points
        adjustment_factor = Ash.Changeset.get_argument(changeset, :adjustment_factor)
        reason = Ash.Changeset.get_argument(changeset, :reason)
        
        new_projection = Decimal.mult(current_projection, Decimal.new(adjustment_factor))
        
        # Add adjustment to factors considered
        current_factors = Ash.Changeset.get_data(changeset).factors_considered || %{}
        updated_factors = Map.put(current_factors, "manual_adjustment", %{
          factor: adjustment_factor,
          reason: reason,
          timestamp: DateTime.utc_now()
        })
        
        changeset
        |> Ash.Changeset.change_attribute(:projected_points, new_projection)
        |> Ash.Changeset.change_attribute(:factors_considered, updated_factors)
      end
    end

    read :for_player_and_week do
      argument :player_id, :uuid, allow_nil?: false
      argument :season, :integer, allow_nil?: false
      argument :week, :integer, allow_nil?: false

      filter expr(player_id == ^arg(:player_id) and season == ^arg(:season) and week == ^arg(:week))
    end

    read :for_week do
      argument :season, :integer, allow_nil?: false
      argument :week, :integer, allow_nil?: false

      filter expr(season == ^arg(:season) and week == ^arg(:week))
    end

    read :for_season do
      argument :season, :integer, allow_nil?: false

      filter expr(season == ^arg(:season))
    end

    read :high_confidence do
      argument :min_confidence, :decimal, default: 0.7

      filter expr(confidence_score >= ^arg(:min_confidence))
    end

    read :recent_projections do
      argument :days, :integer, default: 7

      filter expr(inserted_at >= ago(^arg(:days), :day))
    end

    read :by_model do
      argument :model, :string, allow_nil?: false

      filter expr(projection_model == ^arg(:model))
    end

    read :stale_projections do
      filter expr(inserted_at < ago(3, :day))
    end

    read :top_projections do
      argument :season, :integer, allow_nil?: false
      argument :week, :integer, allow_nil?: false
      argument :position, :atom
      argument :limit, :integer, default: 20

      filter expr(season == ^arg(:season) and week == ^arg(:week))
      
      filter expr(
        if is_nil(arg(:position)) do
          true
        else
          exists(player, player.position == ^arg(:position))
        end
      )

      prepare build(sort: [projected_points: :desc], limit: expr(arg(:limit)))
    end

    action :batch_generate_projections, :map do
      argument :player_ids, {:array, :uuid}, allow_nil?: false
      argument :season, :integer, allow_nil?: false
      argument :week, :integer, allow_nil?: false
      
      run fn input, context ->
        player_ids = input.arguments.player_ids
        season = input.arguments.season
        week = input.arguments.week
        
        results = Enum.map(player_ids, fn player_id ->
          case __MODULE__.generate_ai_projection!(
            player_id: player_id,
            season: season,
            week: week,
            authorize?: false
          ) do
            {:ok, projection} -> {:ok, projection.id}
            {:error, error} -> {:error, player_id, error}
          end
        end)
        
        successes = Enum.count(results, &match?({:ok, _}, &1))
        failures = Enum.count(results, &match?({:error, _, _}, &1))
        
        {:ok, %{
          total: length(player_ids),
          successful: successes,
          failed: failures,
          results: results
        }}
      end
    end

    action :evaluate_accuracy, :map do
      argument :season, :integer, allow_nil?: false
      argument :weeks, {:array, :integer}, default: []
      
      run fn input, context ->
        season = input.arguments.season
        weeks = input.arguments.weeks
        
        accuracy_data = calculate_model_accuracy(season, weeks)
        
        {:ok, accuracy_data}
      end
    end
  end

  code_interface do
    domain FantasyManager.Fantasy

    define :create
    define :read
    define :update
    define :destroy
    define :generate_ai_projection, args: [:player_id, :season, :week, :context_factors]
    define :adjust_projection, args: [:adjustment_factor, :reason]
    define :for_player_and_week, args: [:player_id, :season, :week]
    define :for_week, args: [:season, :week]
    define :for_season, args: [:season]
    define :high_confidence, args: [:min_confidence]
    define :recent_projections, args: [:days]
    define :by_model, args: [:model]
    define :stale_projections
    define :top_projections, args: [:season, :week, :position, :limit]
    define :batch_generate_projections, args: [:player_ids, :season, :week]
    define :evaluate_accuracy, args: [:season, :weeks]

    define :generate_ai_projection!, args: [:player_id, :season, :week, :context_factors]
    define :get_by_player_season_week, get_by: [:player_id, :season, :week]
  end

  identities do
    identity :unique_player_season_week, [:player_id, :season, :week]
  end

  # Helper functions
  defp set_creation_metadata(changeset) do
    changeset
    |> Ash.Changeset.change_attribute(:created_by, "fantasy_manager_ai")
    |> Ash.Changeset.change_attribute(:projection_model, "claude-3-5-sonnet")
  end

  defp validate_projection_factors(changeset) do
    factors = Ash.Changeset.get_attribute(changeset, :factors_considered) || %{}
    
    # Ensure factors considered has required structure
    required_factors = ["recent_performance", "matchup_analysis", "injury_status", "game_environment"]
    missing_factors = required_factors -- Map.keys(factors)
    
    if length(missing_factors) > 0 do
      Ash.Changeset.add_error(changeset, 
        field: :factors_considered, 
        message: "Missing required projection factors: #{Enum.join(missing_factors, ", ")}"
      )
    else
      changeset
    end
  end

  defp cache_projection(changeset, projection) do
    # Cache the projection for quick lookup
    cache_key = "projection:#{projection.player_id}:#{projection.season}:#{projection.week}"
    Cachex.put(:projections_cache, cache_key, projection, ttl: :timer.hours(12))
    changeset
  end

  defp generate_ai_projection_data(player_id, season, week, context_factors) do
    # This would integrate with the AI recommendation engine
    # For now, return mock projection data
    {:ok, %{
      projected_points: Decimal.new("15.7"),
      confidence_score: Decimal.new("0.72"),
      factors_considered: %{
        "recent_performance" => %{"avg_points" => 14.2, "trend" => "stable"},
        "matchup_analysis" => %{"opponent_rank" => 15, "difficulty" => "moderate"},
        "injury_status" => %{"status" => "healthy", "risk" => 0.1},
        "game_environment" => %{"location" => "home", "weather" => "clear"}
      },
      passing_yards: context_factors[:position] == :QB && Decimal.new("245.5"),
      passing_tds: context_factors[:position] == :QB && Decimal.new("1.8"),
      rushing_yards: context_factors[:position] in [:RB, :QB] && Decimal.new("67.2"),
      receiving_yards: context_factors[:position] in [:WR, :TE, :RB] && Decimal.new("78.9")
    }}
  end

  defp calculate_model_accuracy(season, weeks) do
    # This would calculate actual vs projected accuracy
    # For now, return mock accuracy data
    %{
      overall_accuracy: 0.78,
      position_accuracy: %{
        QB: 0.82,
        RB: 0.75,
        WR: 0.74,
        TE: 0.71
      },
      weekly_accuracy: %{},
      confidence_calibration: 0.73,
      total_projections: 1250,
      evaluatable_projections: 1180
    }
  end
end

defmodule FantasyManager.Fantasy.WeeklyProjection.Validations do
  def projection_not_in_past(changeset) do
    season = Ash.Changeset.get_attribute(changeset, :season)
    week = Ash.Changeset.get_attribute(changeset, :week)
    
    if season && week do
      current_date = Date.utc_today()
      current_year = current_date.year
      
      # Rough estimation: NFL season starts around week 36 of the year
      nfl_season_start_week = 36
      projection_calendar_week = nfl_season_start_week + week - 1
      
      cond do
        season < current_year ->
          {:error, "Cannot create projections for past seasons"}
          
        season == current_year ->
          current_week_of_year = Date.beginning_of_week(current_date) |> Date.day_of_year() |> div(7)
          if projection_calendar_week < current_week_of_year - 1 do
            {:error, "Cannot create projections for weeks that have already passed"}
          else
            :ok
          end
          
        true -> 
          :ok
      end
    else
      :ok
    end
  end

  def stat_projections_consistent(changeset) do
    projected_points = Ash.Changeset.get_attribute(changeset, :projected_points)
    passing_yards = Ash.Changeset.get_attribute(changeset, :passing_yards)
    rushing_yards = Ash.Changeset.get_attribute(changeset, :rushing_yards)
    receiving_yards = Ash.Changeset.get_attribute(changeset, :receiving_yards)
    
    if projected_points && (passing_yards || rushing_yards || receiving_yards) do
      # Rough validation that component stats could reasonably produce the total points
      estimated_points = 
        (passing_yards && Decimal.to_float(passing_yards) * 0.04 || 0) +
        (rushing_yards && Decimal.to_float(rushing_yards) * 0.1 || 0) +
        (receiving_yards && Decimal.to_float(receiving_yards) * 0.1 || 0)
      
      actual_points = Decimal.to_float(projected_points)
      
      # Allow for reasonable variance (touchdowns, bonuses, etc.)
      if abs(estimated_points - actual_points) > actual_points * 0.5 do
        {:error, "Component stat projections are inconsistent with total projected points"}
      else
        :ok
      end
    else
      :ok
    end
  end
end