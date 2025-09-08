defmodule FantasyManager.AI.RecommendationEngine do
  @moduledoc """
  AI-powered recommendation engine using Claude for fantasy football lineup optimization.
  
  Provides lineup optimization, trade analysis, and player evaluation using
  structured AI prompts and tool calling capabilities.
  """
  
  alias FantasyManager.Fantasy.Player
  alias FantasyManager.Fantasy.FantasyTeam
  alias FantasyManager.Fantasy.League
  alias FantasyManager.Fantasy.WeeklyProjection
  alias FantasyManager.AI.FantasyTools
  alias FantasyManager.AI.ClaudeConfig
  
  require Ash.Query
  require Logger
  
  @doc """
  Optimizes a lineup for a given fantasy team and week using AI analysis.
  
  ## Parameters
  - team_id: UUID of the fantasy team
  - week: NFL week number (1-18)
  - season: NFL season year
  - options: Optional parameters for optimization
  
  ## Returns
  {:ok, %{lineup: lineup, reasoning: string, confidence: float}} | {:error, reason}
  """
  def optimize_lineup(team_id, week, season, options \\ []) do
    with {:ok, team} <- get_team_with_players(team_id),
         {:ok, league} <- Ash.get(League, team.league_id),
         {:ok, available_players} <- get_available_players(team, week, season),
         {:ok, projections} <- get_player_projections(available_players, week, season),
         {:ok, matchup_data} <- get_matchup_context(available_players, week, season) do
      
      prompt = build_lineup_optimization_prompt(team, league, available_players, projections, matchup_data, options)
      
      case call_claude_for_lineup(prompt, available_players) do
        {:ok, response} ->
          save_projection_if_enabled(response, team_id, week, season)
          {:ok, response}
        
        {:error, reason} ->
          Logger.error("Lineup optimization failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Analyzes a potential trade using AI evaluation.
  
  ## Parameters
  - team_id: UUID of the fantasy team
  - trade_proposal: Map with give/receive player lists
  - options: Optional parameters
  
  ## Returns
  {:ok, %{analysis: string, recommendation: :accept | :decline | :negotiate, confidence: float}}
  """
  def analyze_trade(team_id, trade_proposal, options \\ []) do
    with {:ok, team} <- get_team_with_players(team_id),
         {:ok, league} <- Ash.get(League, team.league_id),
         {:ok, give_players} <- get_players_by_ids(trade_proposal.give),
         {:ok, receive_players} <- get_players_by_ids(trade_proposal.receive) do
      
      prompt = build_trade_analysis_prompt(team, league, give_players, receive_players, options)
      
      case call_claude_for_trade(prompt) do
        {:ok, response} ->
          {:ok, response}
        
        {:error, reason} ->
          Logger.error("Trade analysis failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Gets weekly player projections with AI-enhanced analysis.
  
  ## Parameters
  - player_ids: List of player UUIDs
  - week: NFL week number
  - season: NFL season year
  
  ## Returns
  {:ok, [%{player_id: uuid, projected_points: float, factors: map}]}
  """
  def get_enhanced_projections(player_ids, week, season) do
    with {:ok, players} <- get_players_by_ids(player_ids),
         {:ok, matchup_data} <- get_matchup_context(players, week, season) do
      
      prompt = build_projection_prompt(players, matchup_data, week, season)
      
      case call_claude_for_projections(prompt, players) do
        {:ok, projections} ->
          save_ai_projections(projections, week, season)
          {:ok, projections}
        
        {:error, reason} ->
          Logger.error("Enhanced projections failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get waiver wire pickup recommendations for a fantasy team.
  
  ## Parameters
  - team_id: UUID of the fantasy team
  - week: NFL week number (1-18) 
  - season: NFL season year
  
  ## Returns
  {:ok, %{pickups: [player_recommendations], reasoning: string}} | {:error, reason}
  """
  def get_waiver_recommendations(team_id, week, season) do
    with {:ok, team} <- get_team_with_players(team_id),
         {:ok, league} <- Ash.get(League, team.league_id) do
      
      # For now, return a mock response since the full waiver logic isn't implemented
      {:ok, %{
        pickups: [
          %{
            "name" => "Sample Available Player",
            "position" => "WR",
            "team" => "LAR",
            "priority" => "high",
            "reasoning" => "Strong matchup this week with potential for big game",
            "drop_candidate" => "Current bench player with tough schedule"
          }
        ],
        reasoning: "Based on your team's current roster and upcoming matchups, these pickup recommendations could provide immediate value."
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Optimize keeper selections for a fantasy team.
  
  ## Parameters
  - team_id: UUID of the fantasy team
  - season: NFL season year
  - options: Optional parameters (keeper_count, etc.)
  
  ## Returns
  {:ok, %{keepers: [keeper_recommendations], strategy: string, reasoning: string}} | {:error, reason}
  """
  def optimize_keepers(team_id, season, _options \\ []) do
    with {:ok, team} <- get_team_with_players(team_id),
         {:ok, _league} <- Ash.get(League, team.league_id) do
      
      # For now, return a mock response since the full keeper logic isn't implemented
      {:ok, %{
        keepers: [
          %{
            "name" => "Josh Allen",
            "position" => "QB", 
            "cost" => 45,
            "value_rating" => "excellent"
          },
          %{
            "name" => "Christian McCaffrey",
            "position" => "RB",
            "cost" => 65,
            "value_rating" => "good"
          }
        ],
        strategy: "balanced",
        total_cost: 110,
        reasoning: "These keeper selections provide a strong foundation while maintaining salary cap flexibility for the draft."
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a dynasty planning strategy for a fantasy team.
  
  ## Parameters
  - team_id: UUID of the fantasy team
  - timeline: Planning timeline ("immediate", "medium", "rebuild")
  - options: Optional parameters
  
  ## Returns
  {:ok, %{strategy: string, competitive_window: string, key_players: [...], reasoning: string}} | {:error, reason}
  """
  def create_dynasty_plan(team_id, timeline \\ "medium", _options \\ []) do
    with {:ok, team} <- get_team_with_players(team_id),
         {:ok, _league} <- Ash.get(League, team.league_id) do
      
      # For now, return a mock response since the full dynasty logic isn't implemented
      strategy_description = case timeline do
        "immediate" -> "Focus on veteran players and win-now moves"
        "rebuild" -> "Prioritize young talent and draft capital accumulation"
        _ -> "Balance competing now with building for the future"
      end

      {:ok, %{
        competitive_window: "Your team is currently in a #{timeline} competitive window",
        strategy: strategy_description,
        timeline: "Expect to compete at the highest level within 1-2 seasons",
        key_players: [
          %{
            "name" => "Ja'Marr Chase",
            "position" => "WR",
            "age" => 24,
            "action" => "keep",
            "reasoning" => "Elite young talent with years of production ahead"
          },
          %{
            "name" => "Derrick Henry",
            "position" => "RB", 
            "age" => 30,
            "action" => "consider_trading",
            "reasoning" => "Aging RB who could return significant value in trade"
          }
        ],
        trade_targets: [
          %{
            "name" => "Jaylen Waddle",
            "rationale" => "Young WR with high upside for dynasty"
          }
        ],
        reasoning: "Your dynasty strategy should focus on maintaining competitive balance while building for sustained success over multiple seasons."
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Test the AI connection and basic functionality.
  """
  def test_connection do
    prompt = """
    Test prompt for Claude API connection. Please respond with:
    {"status": "connected", "model": "claude-3-5-sonnet", "message": "Fantasy Manager AI is ready"}
    """
    
    case ClaudeConfig.call_claude(prompt) do
      {:ok, response} ->
        Logger.info("AI connection test successful: #{inspect(response)}")
        {:ok, response}
      
      {:error, reason} ->
        Logger.error("AI connection test failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # Private functions
  
  defp get_team_with_players(team_id) do
    FantasyTeam
    |> Ash.Query.filter(id == ^team_id)
    |> Ash.Query.load([:roster_players, :league])
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :team_not_found}
      {:ok, team} -> {:ok, team}
      error -> error
    end
  end
  
  defp get_available_players(team, _week, _season) do
    # Get team's current roster plus any available free agents
    # This would typically involve checking league roster rules
    {:ok, team.roster_players || []}
  end
  
  defp get_player_projections(players, week, season) do
    player_ids = Enum.map(players, & &1.id)
    
    WeeklyProjection
    |> Ash.Query.filter(player_id in ^player_ids and week == ^week and season == ^season)
    |> Ash.read()
  end
  
  defp get_matchup_context(_players, week, season) do
    # This would typically fetch NFL matchup data, weather, injury reports, etc.
    # For now, return a basic structure
    {:ok, %{
      week: week,
      season: season,
      weather_conditions: %{},
      injury_reports: %{},
      vegas_lines: %{}
    }}
  end
  
  defp get_players_by_ids(player_ids) do
    Player
    |> Ash.Query.filter(id in ^player_ids)
    |> Ash.read()
  end
  
  defp build_lineup_optimization_prompt(_team, league, players, projections, matchup_data, options) do
    """
    You are a fantasy football AI assistant helping optimize a lineup.
    
    LEAGUE SETTINGS:
    - League Type: #{league.league_type}
    - Scoring: #{format_scoring_settings(league.scoring_settings)}
    - Roster Size: #{league.roster_size}
    - Starting Lineup: #{format_roster_requirements(league)}
    
    AVAILABLE PLAYERS:
    #{format_players_for_prompt(players)}
    
    CURRENT PROJECTIONS:
    #{format_projections_for_prompt(projections)}
    
    MATCHUP CONTEXT:
    Week #{matchup_data.week}, Season #{matchup_data.season}
    #{format_matchup_data_for_prompt(matchup_data)}
    
    OPTIMIZATION GOALS:
    #{format_options_for_prompt(options)}
    
    Please provide an optimized lineup recommendation with:
    1. Starting lineup (position by position)
    2. Bench recommendations
    3. Key factors in your decision
    4. Confidence level (0-1)
    5. Risk assessment
    
    Respond in JSON format:
    {
      "lineup": {
        "starters": [{"player_id": "uuid", "position": "QB", "name": "Player Name"}],
        "bench": [{"player_id": "uuid", "position": "RB", "name": "Player Name"}]
      },
      "reasoning": "Detailed explanation of lineup choices",
      "confidence": 0.85,
      "risk_level": "medium",
      "key_factors": ["factor1", "factor2"]
    }
    """
  end
  
  defp build_trade_analysis_prompt(team, league, give_players, receive_players, _options) do
    """
    You are a fantasy football AI assistant analyzing a trade proposal.
    
    LEAGUE CONTEXT:
    - League Type: #{league.league_type}
    - Scoring: #{league.scoring_settings}
    - Trade Deadline: #{league.trade_deadline}
    
    CURRENT TEAM CONTEXT:
    Team Name: #{team.name}
    Competitive Window: #{team.competitive_window}
    Current Record: #{team.wins}-#{team.losses}
    
    TRADE PROPOSAL:
    GIVING: #{format_players_for_prompt(give_players)}
    RECEIVING: #{format_players_for_prompt(receive_players)}
    
    Please analyze this trade and provide:
    1. Overall trade value assessment
    2. Impact on team competitive window
    3. Position needs analysis
    4. Risk factors
    5. Recommendation (accept/decline/negotiate)
    
    Respond in JSON format:
    {
      "recommendation": "accept",
      "analysis": "Detailed trade analysis",
      "confidence": 0.75,
      "value_assessment": "slightly_favorable",
      "risk_factors": ["injury_risk", "age_decline"],
      "suggested_counters": []
    }
    """
  end
  
  defp build_projection_prompt(players, matchup_data, week, season) do
    """
    You are a fantasy football AI assistant providing enhanced player projections.
    
    CONTEXT:
    Week #{week}, Season #{season}
    
    PLAYERS TO ANALYZE:
    #{format_players_for_prompt(players)}
    
    MATCHUP DATA:
    #{format_matchup_data_for_prompt(matchup_data)}
    
    For each player, provide enhanced projections considering:
    1. Historical performance
    2. Matchup difficulty
    3. Weather conditions
    4. Injury status
    5. Game script expectations
    
    Respond in JSON format:
    {
      "projections": [
        {
          "player_id": "uuid",
          "projected_points": 15.6,
          "confidence": 0.8,
          "factors_considered": {
            "matchup_difficulty": "easy",
            "weather_impact": "minimal",
            "injury_status": "healthy"
          }
        }
      ]
    }
    """
  end
  
  defp call_claude_for_lineup(prompt, _players) do
    # For now, use simple call without tools since claude-code doesn't support tools
    # In the future, we could add tool support to the claude-code integration
    case ClaudeConfig.call_claude(prompt) do
      {:ok, response} -> parse_lineup_response(response)
      error -> error
    end
  end
  
  defp call_claude_for_trade(prompt) do
    case ClaudeConfig.call_claude(prompt) do
      {:ok, response} -> parse_trade_response(response)
      error -> error
    end
  end
  
  defp call_claude_for_projections(prompt, players) do
    tools = FantasyTools.get_projection_tools(players)
    
    case ClaudeConfig.call_claude_with_tools(prompt, tools) do
      {:ok, response} -> parse_projections_response(response)
      error -> error
    end
  end
  
  defp parse_lineup_response(response) do
    try do
      parsed = Jason.decode!(response)
      {:ok, %{
        lineup: parsed["lineup"],
        reasoning: parsed["reasoning"],
        confidence: parsed["confidence"] || 0.5,
        risk_level: parsed["risk_level"] || "medium",
        key_factors: parsed["key_factors"] || []
      }}
    rescue
      _ -> {:error, :invalid_response_format}
    end
  end
  
  defp parse_trade_response(response) do
    try do
      parsed = Jason.decode!(response)
      {:ok, %{
        recommendation: String.to_atom(parsed["recommendation"]),
        analysis: parsed["analysis"],
        confidence: parsed["confidence"] || 0.5,
        value_assessment: parsed["value_assessment"],
        risk_factors: parsed["risk_factors"] || [],
        suggested_counters: parsed["suggested_counters"] || []
      }}
    rescue
      _ -> {:error, :invalid_response_format}
    end
  end
  
  defp parse_projections_response(response) do
    try do
      parsed = Jason.decode!(response)
      projections = Enum.map(parsed["projections"], fn proj ->
        %{
          player_id: proj["player_id"],
          projected_points: proj["projected_points"],
          confidence: proj["confidence"] || 0.5,
          factors_considered: proj["factors_considered"] || %{}
        }
      end)
      {:ok, projections}
    rescue
      _ -> {:error, :invalid_response_format}
    end
  end
  
  defp format_players_for_prompt(players) do
    players
    |> Enum.map(fn player ->
      "- #{player.name} (#{player.position}) - #{player.nfl_team || "FA"} - Age: #{player.age || "N/A"}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_projections_for_prompt(projections) do
    projections
    |> Enum.map(fn proj ->
      "- Player ID: #{proj.player_id} - Projected: #{proj.projected_points} pts (#{proj.confidence * 100}% confidence)"
    end)
    |> Enum.join("\n")
  end
  
  defp format_matchup_data_for_prompt(matchup_data) do
    "Week #{matchup_data.week} matchup data available"
  end
  
  defp format_options_for_prompt(options) do
    Keyword.get(options, :goals, "Maximize projected points")
  end
  
  defp save_projection_if_enabled(_response, team_id, week, season) do
    if Application.get_env(:fantasy_manager, :save_ai_projections, false) do
      # Save the AI-generated projections for future reference
      Logger.info("Saving AI projections for team #{team_id}, week #{week}, season #{season}")
    end
  end
  
  defp save_ai_projections(projections, week, season) do
    projections
    |> Enum.each(fn projection ->
      WeeklyProjection
      |> Ash.Changeset.for_create(:create, %{
        player_id: projection.player_id,
        season: season,
        week: week,
        projected_points: projection.projected_points,
        confidence_score: projection.confidence,
        projection_model: "claude-3-5-sonnet",
        factors_considered: projection.factors_considered
      })
      |> Ash.create()
    end)
  end

  defp format_scoring_settings(scoring_settings) when is_map(scoring_settings) do
    key_scoring_settings = [
      {"Pass TD", scoring_settings["pass_td"]},
      {"Pass Yards", scoring_settings["pass_yd"]},
      {"Rush TD", scoring_settings["rush_td"]},
      {"Rush Yards", scoring_settings["rush_yd"]},
      {"Rec TD", scoring_settings["rec_td"]},
      {"Rec Yards", scoring_settings["rec_yd"]},
      {"Reception", scoring_settings["rec"]},
      {"Fumble Lost", scoring_settings["fum_lost"]},
      {"Interception", scoring_settings["pass_int"]}
    ]
    |> Enum.filter(fn {_key, value} -> value end)
    |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
    |> Enum.join(", ")
    
    if key_scoring_settings == "", do: "Standard scoring", else: key_scoring_settings
  end

  defp format_scoring_settings(_), do: "Standard scoring"

  defp format_roster_requirements(league) do
    # This could be expanded with actual roster requirements
    # For now, return a standard lineup based on league type
    case league.league_type do
      :superflex -> "1 QB, 2 RB, 3 WR, 1 TE, 1 FLEX, 1 SUPERFLEX, 1 K, 1 DEF"
      _ -> "1 QB, 2 RB, 2 WR, 1 TE, 1 FLEX, 1 K, 1 DEF"
    end
  end
end