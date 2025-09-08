defmodule FantasyManager.AI.FantasyTools do
  @moduledoc """
  AI tools for accessing fantasy football data for AI integration.
  
  Provides structured tools that AI models can use to query player stats,
  matchup data, league settings, and team rosters for making informed
  recommendations.
  """
  
  alias FantasyManager.Fantasy.Player
  alias FantasyManager.Fantasy.League
  
  require Ash.Query
  
  @doc """
  Get lineup optimization tools for AI to use during lineup recommendations.
  """
  def get_lineup_tools(_players) do
    [
      get_player_stats_tool(),
      get_matchup_data_tool(),
      get_league_scoring_tool(),
      get_injury_report_tool(),
      get_weather_data_tool(),
      get_vegas_lines_tool()
    ]
  end
  
  @doc """
  Get projection tools for AI to use during enhanced projection generation.
  """
  def get_projection_tools(_players) do
    [
      get_player_historical_tool(),
      get_opponent_defense_tool(),
      get_game_script_tool(),
      get_target_share_tool(),
      get_snap_count_tool()
    ]
  end
  
  @doc """
  Get trade analysis tools for AI to use during trade evaluation.
  """
  def get_trade_tools do
    [
      get_player_value_tool(),
      get_positional_scarcity_tool(),
      get_team_needs_tool(),
      get_playoff_schedule_tool(),
      get_age_curve_tool()
    ]
  end
  
  @doc """
  Get waiver wire analysis tools for AI to use during waiver recommendations.
  """
  def get_waiver_tools do
    [
      get_trending_players_tool(),
      get_availability_tool(),
      get_ownership_percentages_tool(),
      get_roster_needs_tool(),
      get_upcoming_schedule_tool(),
      get_waiver_priority_tool(),
      get_drop_candidates_tool()
    ]
  end
  
  # Tool definitions
  
  def get_player_stats_tool do
    %{
      name: "get_player_stats",
      description: "Retrieve detailed statistics for a player",
      parameters: %{
        player_id: %{type: "string", description: "UUID of the player"},
        season: %{type: "integer", description: "NFL season year"},
        weeks: %{type: "array", description: "Specific weeks to include"}
      }
    }
  end
  
  def get_matchup_data_tool do
    %{
      name: "get_matchup_data",
      description: "Get matchup information for a player's upcoming game",
      parameters: %{
        player_id: %{type: "string", description: "UUID of the player"},
        week: %{type: "integer", description: "NFL week number"},
        season: %{type: "integer", description: "NFL season year"}
      }
    }
  end
  
  def get_league_scoring_tool do
    %{
      name: "get_league_scoring",
      description: "Retrieve scoring settings for a league",
      parameters: %{
        league_id: %{type: "string", description: "UUID of the league"}
      }
    }
  end
  
  def get_injury_report_tool do
    %{
      name: "get_injury_report",
      description: "Get current injury status for players",
      parameters: %{
        player_ids: %{type: "array", description: "List of player UUIDs"}
      }
    }
  end
  
  def get_weather_data_tool do
    %{
      name: "get_weather_data",
      description: "Get weather conditions for NFL games",
      parameters: %{
        week: %{type: "integer", description: "NFL week number"},
        season: %{type: "integer", description: "NFL season year"}
      }
    }
  end
  
  def get_vegas_lines_tool do
    %{
      name: "get_vegas_lines",
      description: "Get betting lines and totals for NFL games",
      parameters: %{
        week: %{type: "integer", description: "NFL week number"},
        season: %{type: "integer", description: "NFL season year"}
      }
    }
  end
  
  def get_player_historical_tool do
    %{
      name: "get_player_historical",
      description: "Get historical performance trends for a player",
      parameters: %{
        player_id: %{type: "string", description: "UUID of the player"},
        lookback_weeks: %{type: "integer", description: "Number of weeks to look back"}
      }
    }
  end
  
  def get_opponent_defense_tool do
    %{
      name: "get_opponent_defense",
      description: "Get defensive rankings for opposing team",
      parameters: %{
        opponent_team: %{type: "string", description: "NFL team abbreviation"},
        position: %{type: "string", description: "Position to analyze"}
      }
    }
  end
  
  def get_game_script_tool do
    %{
      name: "get_game_script",
      description: "Analyze expected game script and pace factors",
      parameters: %{
        home_team: %{type: "string", description: "Home NFL team"},
        away_team: %{type: "string", description: "Away NFL team"},
        week: %{type: "integer", description: "NFL week number"}
      }
    }
  end
  
  def get_target_share_tool do
    %{
      name: "get_target_share",
      description: "Get target share and usage data for receivers",
      parameters: %{
        player_id: %{type: "string", description: "UUID of the player"},
        weeks: %{type: "integer", description: "Number of recent weeks"}
      }
    }
  end
  
  def get_snap_count_tool do
    %{
      name: "get_snap_count",
      description: "Get snap count percentages and usage",
      parameters: %{
        player_id: %{type: "string", description: "UUID of the player"},
        weeks: %{type: "integer", description: "Number of recent weeks"}
      }
    }
  end
  
  def get_player_value_tool do
    %{
      name: "get_player_value",
      description: "Get current trade value for players",
      parameters: %{
        player_ids: %{type: "array", description: "List of player UUIDs"}
      }
    }
  end
  
  def get_positional_scarcity_tool do
    %{
      name: "get_positional_scarcity",
      description: "Analyze scarcity at each position",
      parameters: %{
        league_id: %{type: "string", description: "UUID of the league"}
      }
    }
  end
  
  def get_team_needs_tool do
    %{
      name: "get_team_needs",
      description: "Analyze team positional needs",
      parameters: %{
        team_id: %{type: "string", description: "UUID of the fantasy team"}
      }
    }
  end
  
  def get_playoff_schedule_tool do
    %{
      name: "get_playoff_schedule",
      description: "Get playoff schedule strength for players",
      parameters: %{
        player_ids: %{type: "array", description: "List of player UUIDs"},
        playoff_weeks: %{type: "array", description: "Playoff week numbers"}
      }
    }
  end
  
  def get_age_curve_tool do
    %{
      name: "get_age_curve",
      description: "Analyze age-related performance trends",
      parameters: %{
        player_id: %{type: "string", description: "UUID of the player"},
        position: %{type: "string", description: "Player position"}
      }
    }
  end
  
  # Waiver-specific tool definitions
  
  def get_trending_players_tool do
    %{
      name: "get_trending_players",
      description: "Get trending players from waiver wire (most added/dropped)",
      parameters: %{
        trend_type: %{type: "string", description: "Type of trend: 'add' or 'drop'"},
        position: %{type: "string", description: "Filter by position (optional)"}
      }
    }
  end
  
  def get_availability_tool do
    %{
      name: "get_availability",
      description: "Check if players are available on waiver wire in specific league",
      parameters: %{
        player_ids: %{type: "array", description: "List of player UUIDs to check"},
        league_id: %{type: "string", description: "UUID of the league"}
      }
    }
  end
  
  def get_ownership_percentages_tool do
    %{
      name: "get_ownership_percentages",
      description: "Get ownership percentages for players across all leagues",
      parameters: %{
        player_ids: %{type: "array", description: "List of player UUIDs"}
      }
    }
  end
  
  def get_roster_needs_tool do
    %{
      name: "get_roster_needs",
      description: "Analyze current roster composition and identify needs",
      parameters: %{
        team_id: %{type: "string", description: "UUID of the fantasy team"}
      }
    }
  end
  
  def get_upcoming_schedule_tool do
    %{
      name: "get_upcoming_schedule",
      description: "Get upcoming NFL schedule and matchup difficulty",
      parameters: %{
        player_ids: %{type: "array", description: "List of player UUIDs"},
        weeks: %{type: "integer", description: "Number of weeks to look ahead"}
      }
    }
  end
  
  def get_waiver_priority_tool do
    %{
      name: "get_waiver_priority",
      description: "Get waiver priority order for a team",
      parameters: %{
        team_id: %{type: "string", description: "UUID of the fantasy team"},
        league_id: %{type: "string", description: "UUID of the league"}
      }
    }
  end
  
  def get_drop_candidates_tool do
    %{
      name: "get_drop_candidates",
      description: "Identify potential drop candidates from team roster",
      parameters: %{
        team_id: %{type: "string", description: "UUID of the fantasy team"},
        position: %{type: "string", description: "Focus on specific position (optional)"}
      }
    }
  end
  
  # Data access functions (these would be called by the AI tools)
  
  def execute_tool("get_player_stats", args) do
    case get_player_with_stats(args["player_id"], args["season"] || 2024, args["weeks"] || []) do
      {:ok, player_data} -> {:ok, format_player_stats(player_data)}
      {:error, reason} -> {:error, "Failed to retrieve player stats: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_matchup_data", args) do
    case get_player_matchup_info(args["player_id"], args["week"], args["season"] || 2024) do
      {:ok, matchup_data} -> {:ok, format_matchup_data(matchup_data)}
      {:error, reason} -> {:error, "Failed to retrieve matchup data: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_league_scoring", args) do
    case Ash.get(League, args["league_id"]) do
      {:ok, league} -> {:ok, format_league_scoring(league)}
      {:error, reason} -> {:error, "Failed to retrieve league scoring: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_injury_report", args) do
    case get_players_injury_status(args["player_ids"]) do
      {:ok, injury_data} -> {:ok, format_injury_report(injury_data)}
      {:error, reason} -> {:error, "Failed to retrieve injury report: #{inspect(reason)}"}
    end
  end
  
  # Waiver-specific tool implementations
  
  def execute_tool("get_trending_players", args) do
    alias FantasyManager.External.SleeperClient
    
    trend_type = args["trend_type"] || "add"
    position_filter = args["position"]
    
    case SleeperClient.get_trending_players(trend_type) do
      {:ok, trending_data} ->
        formatted_data = format_trending_data(trending_data, position_filter)
        {:ok, formatted_data}
      {:error, reason} ->
        {:error, "Failed to retrieve trending players: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_availability", args) do
    case check_player_availability(args["player_ids"], args["league_id"]) do
      {:ok, availability_data} -> {:ok, availability_data}
      {:error, reason} -> {:error, "Failed to check availability: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_ownership_percentages", args) do
    case get_ownership_data(args["player_ids"]) do
      {:ok, ownership_data} -> {:ok, ownership_data}
      {:error, reason} -> {:error, "Failed to retrieve ownership data: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_roster_needs", args) do
    case analyze_roster_needs(args["team_id"]) do
      {:ok, needs_analysis} -> {:ok, needs_analysis}
      {:error, reason} -> {:error, "Failed to analyze roster needs: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_upcoming_schedule", args) do
    case get_player_schedules(args["player_ids"], args["weeks"] || 4) do
      {:ok, schedule_data} -> {:ok, schedule_data}
      {:error, reason} -> {:error, "Failed to retrieve schedules: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_waiver_priority", args) do
    case get_team_waiver_priority(args["team_id"], args["league_id"]) do
      {:ok, priority_data} -> {:ok, priority_data}
      {:error, reason} -> {:error, "Failed to retrieve waiver priority: #{inspect(reason)}"}
    end
  end
  
  def execute_tool("get_drop_candidates", args) do
    case identify_drop_candidates(args["team_id"], args["position"]) do
      {:ok, drop_candidates} -> {:ok, drop_candidates}
      {:error, reason} -> {:error, "Failed to identify drop candidates: #{inspect(reason)}"}
    end
  end
  
  def execute_tool(tool_name, _args) do
    {:error, "Tool #{tool_name} not implemented yet"}
  end
  
  # Helper functions for waiver tools
  
  defp format_trending_data(trending_data, position_filter) do
    alias FantasyManager.External.SleeperClient
    
    # Get all players to cross-reference with trending data
    case SleeperClient.get_all_players() do
      {:ok, all_players} ->
        formatted_trends = trending_data
        |> Enum.map(fn {player_id, trend_count} ->
          player_info = Map.get(all_players, player_id, %{})
          player_name = Map.get(player_info, "full_name", "Unknown Player")
          player_position = Map.get(player_info, "position")
          player_team = Map.get(player_info, "team")
          
          %{
            player_id: player_id,
            player_name: player_name,
            position: player_position,
            team: player_team,
            trend_count: trend_count
          }
        end)
        |> then(fn trends ->
          if position_filter do
            Enum.filter(trends, fn trend -> trend.position == position_filter end)
          else
            trends
          end
        end)
        |> Enum.sort_by(fn trend -> trend.trend_count end, :desc)
        
        %{
          trending_players: formatted_trends,
          total_count: length(formatted_trends),
          position_filter: position_filter
        }
      
      {:error, _reason} ->
        # Fallback if we can't get player info
        %{
          trending_players: Enum.map(trending_data, fn {player_id, count} ->
            %{player_id: player_id, trend_count: count, player_name: "Unknown", position: nil, team: nil}
          end),
          total_count: map_size(trending_data),
          position_filter: position_filter
        }
    end
  end
  
  defp check_player_availability(player_ids, league_id) do
    # In a real implementation, we would check if players are rostered in the league
    # For now, we'll mock this data
    availability_data = Enum.map(player_ids, fn player_id ->
      %{
        player_id: player_id,
        available: true, # Mock: assume available for now
        rostered_by: nil,
        waiver_status: "available"
      }
    end)
    
    {:ok, %{
      league_id: league_id,
      player_availability: availability_data,
      checked_at: DateTime.utc_now()
    }}
  end
  
  defp get_ownership_data(player_ids) do
    # Mock ownership percentages - in real implementation would query across leagues
    ownership_data = Enum.map(player_ids, fn player_id ->
      # Generate realistic mock ownership percentage
      ownership_pct = :rand.uniform(100)
      
      %{
        player_id: player_id,
        ownership_percentage: ownership_pct,
        trend: if(ownership_pct > 50, do: "increasing", else: "stable")
      }
    end)
    
    {:ok, %{
      ownership_data: ownership_data,
      sample_date: Date.utc_today()
    }}
  end
  
  defp analyze_roster_needs(team_id) do
    alias FantasyManager.Fantasy.FantasyTeam
    
    case Ash.get(FantasyTeam, team_id) do
      {:ok, team} ->
        # Load team players with their associated player data
        case Ash.load(team, [fantasy_team_players: :player]) do
          {:ok, team_with_players} ->
            roster_analysis = analyze_positional_depth(team_with_players)
            {:ok, roster_analysis}
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_player_schedules(player_ids, weeks_ahead) do
    # Mock schedule data - in real implementation would get from NFL API
    schedule_data = Enum.map(player_ids, fn player_id ->
      upcoming_games = Enum.map(1..weeks_ahead, fn week ->
        %{
          week: week,
          opponent: ["DAL", "NYG", "PHI", "WAS"] |> Enum.random(),
          home_away: ["home", "away"] |> Enum.random(),
          difficulty_rating: :rand.uniform(10)
        }
      end)
      
      %{
        player_id: player_id,
        upcoming_schedule: upcoming_games,
        average_difficulty: upcoming_games |> Enum.map(&(&1.difficulty_rating)) |> Enum.sum() |> div(weeks_ahead)
      }
    end)
    
    {:ok, %{
      schedules: schedule_data,
      weeks_analyzed: weeks_ahead
    }}
  end
  
  defp get_team_waiver_priority(team_id, league_id) do
    alias FantasyManager.Fantasy.{FantasyTeam, League}
    
    with {:ok, team} <- Ash.get(FantasyTeam, team_id),
         {:ok, league} <- Ash.get(League, league_id) do
      
      # Mock waiver priority - in real implementation would get from league settings
      {:ok, %{
        team_id: team_id,
        league_id: league_id,
        current_priority: team.waiver_priority || 5,
        waiver_type: "rolling", # or "reset"
        next_claim_priority: calculate_next_priority(team.waiver_priority || 5)
      }}
    end
  end
  
  defp identify_drop_candidates(team_id, position_filter) do
    alias FantasyManager.Fantasy.FantasyTeam
    
    case Ash.get(FantasyTeam, team_id) do
      {:ok, team} ->
        case Ash.load(team, [:fantasy_team_players]) do
          {:ok, team_with_players} ->
            drop_candidates = analyze_drop_candidates(team_with_players, position_filter)
            {:ok, drop_candidates}
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp analyze_positional_depth(team_with_players) do
    # Group players by position and analyze depth
    position_groups = team_with_players.fantasy_team_players
    |> Enum.filter(fn team_player -> 
      # Only include players that have the player relationship loaded
      not is_struct(team_player.player, Ash.NotLoaded)
    end)
    |> Enum.group_by(fn team_player -> 
      # Access the position from the associated player
      team_player.player.position
    end)
    
    position_needs = Enum.map(position_groups, fn {position, players} ->
      player_count = length(players)
      # Convert position to string for consistent pattern matching
      position_str = to_string(position)
      
      depth_rating = case position_str do
        "QB" -> if player_count < 2, do: "need_backup", else: "adequate"
        "RB" -> cond do
          player_count < 2 -> "critical_need"
          player_count < 4 -> "need_depth"
          true -> "adequate"
        end
        "WR" -> cond do
          player_count < 3 -> "critical_need"
          player_count < 5 -> "need_depth"
          true -> "adequate"
        end
        "TE" -> if player_count < 2, do: "need_backup", else: "adequate"
        "K" -> if player_count < 1, do: "critical_need", else: "adequate"
        "DEF" -> if player_count < 1, do: "critical_need", else: "adequate"
        _ -> "adequate"
      end
      
      %{
        position: position_str,
        current_count: player_count,
        depth_rating: depth_rating,
        players: Enum.map(players, fn p -> %{name: p.player.name, id: p.player.id} end)
      }
    end)
    
    %{
      team_id: team_with_players.id,
      position_analysis: position_needs,
      overall_needs: identify_priority_needs(position_needs)
    }
  end
  
  defp analyze_drop_candidates(team_with_players, position_filter) do
    candidates = team_with_players.fantasy_team_players
    |> then(fn players ->
      if position_filter do
        Enum.filter(players, fn p -> p.position == position_filter end)
      else
        players
      end
    end)
    |> Enum.map(fn player ->
      drop_score = calculate_drop_score(player)
      
      %{
        player_id: player.id,
        player_name: player.name,
        position: player.position,
        drop_score: drop_score,
        drop_reasoning: generate_drop_reasoning(player, drop_score)
      }
    end)
    |> Enum.sort_by(fn candidate -> candidate.drop_score end, :desc)
    
    %{
      team_id: team_with_players.id,
      drop_candidates: candidates,
      position_filter: position_filter
    }
  end
  
  defp calculate_next_priority(current_priority) do
    # Simple logic: if you use a waiver claim, you go to the back
    max(current_priority - 1, 1)
  end
  
  defp identify_priority_needs(position_analysis) do
    critical_needs = Enum.filter(position_analysis, fn pos -> pos.depth_rating == "critical_need" end)
    depth_needs = Enum.filter(position_analysis, fn pos -> pos.depth_rating == "need_depth" end)
    
    %{
      critical_positions: Enum.map(critical_needs, fn pos -> pos.position end),
      depth_positions: Enum.map(depth_needs, fn pos -> pos.position end),
      priority_order: (Enum.map(critical_needs, fn pos -> pos.position end) ++ Enum.map(depth_needs, fn pos -> pos.position end))
    }
  end
  
  defp calculate_drop_score(player) do
    # Mock drop scoring - in real implementation would consider:
    # - Recent performance, injury status, upcoming schedule, etc.
    base_score = case player.position do
      "K" -> 7.0    # Kickers are typically most droppable
      "DEF" -> 6.0  # Defenses next
      "TE" -> 4.0   # TEs if you have multiple
      "QB" -> 3.0   # QBs if you have backup
      "WR" -> 2.0   # WRs depend on depth
      "RB" -> 1.0   # RBs typically kept
      _ -> 5.0
    end
    
    # Add some randomness for variety in mock data
    base_score + (:rand.uniform(20) - 10) / 10.0
  end
  
  defp generate_drop_reasoning(player, drop_score) do
    cond do
      drop_score > 7.0 -> "Low usage and replaceable at #{player.position} position"
      drop_score > 5.0 -> "Adequate performance but expendable for waiver pickup"
      drop_score > 3.0 -> "Roster flexibility option, consider if better pickup available"
      true -> "Valuable player, only drop for premium pickup"
    end
  end

  # Helper functions for data retrieval
  
  defp get_player_with_stats(player_id, _season, _weeks) do
    Player
    |> Ash.Query.filter(id == ^player_id)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :player_not_found}
      {:ok, player} -> 
        # For now, return player without stats since we don't have player_stats relation defined
        # In a real implementation, we would load related stats here
        {:ok, Map.put(player, :player_stats, [])}
      error -> error
    end
  end
  
  defp get_player_matchup_info(player_id, week, season) do
    with {:ok, player} <- Ash.get(Player, player_id) do
      {:ok, %{
        player: player,
        week: week,
        season: season,
        opponent: "TBD",
        home_away: "home",
        game_total: 45.5,
        spread: -3.0
      }}
    end
  end
  
  defp get_players_injury_status(player_ids) do
    injury_data = Enum.map(player_ids, fn player_id ->
      %{
        player_id: player_id,
        injury_status: "healthy",
        injury_details: nil,
        practice_status: "full",
        game_status: "active"
      }
    end)
    
    {:ok, injury_data}
  end
  
  # Formatting functions
  
  defp format_player_stats(player) do
    %{
      id: player.id,
      name: player.name,
      position: player.position,
      team: player.team,
      stats: Enum.map(player.player_stats || [], fn stat ->
        %{
          week: Map.get(stat, :week),
          season: Map.get(stat, :season),
          points: Map.get(stat, :fantasy_points),
          passing_yards: Map.get(stat, :passing_yards),
          rushing_yards: Map.get(stat, :rushing_yards),
          receiving_yards: Map.get(stat, :receiving_yards),
          touchdowns: Map.get(stat, :total_touchdowns),
          targets: Map.get(stat, :targets),
          carries: Map.get(stat, :carries)
        }
      end)
    }
  end
  
  defp format_matchup_data(matchup) do
    %{
      player_name: matchup.player.name,
      opponent: matchup.opponent,
      home_away: matchup.home_away,
      game_total: matchup.game_total,
      spread: matchup.spread,
      matchup_rating: calculate_matchup_rating(matchup)
    }
  end
  
  defp format_league_scoring(league) do
    %{
      league_id: league.id,
      league_name: league.name,
      scoring_type: league.scoring_settings,
      roster_settings: league.starting_lineup_requirements,
      trade_settings: %{
        trade_deadline: league.trade_deadline,
        trade_review_days: league.trade_review_days
      }
    }
  end
  
  defp format_injury_report(injuries) do
    %{
      report_date: Date.utc_today(),
      players: injuries
    }
  end
  
  # Helper functions
  
  defp calculate_matchup_rating(matchup) do
    base_rating = 5.0
    
    cond do
      matchup.spread > 7.0 -> base_rating + 1.0
      matchup.spread < -7.0 -> base_rating - 1.0
      true -> base_rating
    end
  end
end