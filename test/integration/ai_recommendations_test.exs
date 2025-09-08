defmodule FantasyManager.Integration.AIRecommendationsTest do
  use ExUnit.Case
  import Mox
  alias FantasyManager.AI.RecommendationEngine
  alias FantasyManager.AI.FantasyTools
  alias FantasyManager.TestSupport.MockData

  @moduletag :integration

  setup :verify_on_exit!

  describe "RecommendationEngine.generate_lineup_recommendation/2" do
    test "generates lineup optimization with Claude integration" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{
        week: 1,
        season: 2024,
        injury_threshold: "Questionable",
        risk_tolerance: "Balanced"
      }

      assert {:ok, recommendation} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
      
      assert %{
        optimal_lineup: lineup,
        projected_total: total_points,
        confidence_score: confidence,
        reasoning: reasoning,
        alternatives: alternatives
      } = recommendation

      # Verify lineup structure
      assert %{
        qb: qb,
        rb1: rb1,
        rb2: rb2,
        wr1: wr1,
        wr2: wr2,
        te: te,
        flex: flex,
        k: k,
        def: def
      } = lineup

      # Verify all positions are filled
      lineup_players = [qb, rb1, rb2, wr1, wr2, te, flex, k, def]
      Enum.each(lineup_players, fn player ->
        assert %{
          player_id: _,
          name: _,
          position: _,
          projected_points: points,
          confidence: conf,
          matchup_analysis: _,
          injury_risk: risk
        } = player

        assert is_number(points) and points > 0
        assert is_number(conf) and conf >= 0 and conf <= 1.0
        assert risk in ["Low", "Medium", "High"]
      end)

      # Verify recommendation metadata
      assert is_number(total_points) and total_points > 0
      assert is_number(confidence) and confidence >= 0 and confidence <= 1.0
      assert is_binary(reasoning) and String.length(reasoning) > 20
      assert is_list(alternatives)
    end

    test "handles missing player data gracefully" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440001"
      context = %{week: 1, season: 2024}

      # Mock empty roster
      expect(MockData, :get_team_roster, fn ^fantasy_team_id ->
        {:ok, []}
      end)

      assert {:error, :insufficient_players} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
    end

    test "respects injury threshold settings" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{
        week: 1,
        season: 2024,
        injury_threshold: "Active"  # Only active players
      }

      assert {:ok, recommendation} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
      
      # Verify no questionable/doubtful players in lineup
      lineup_players = Map.values(recommendation.optimal_lineup)
      Enum.each(lineup_players, fn player ->
        assert player.injury_status in ["Active", nil]
      end)
    end

    test "adjusts recommendations based on risk tolerance" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      
      # Conservative approach
      conservative_context = %{week: 1, season: 2024, risk_tolerance: "Conservative"}
      assert {:ok, conservative_rec} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, conservative_context)
      
      # Aggressive approach  
      aggressive_context = %{week: 1, season: 2024, risk_tolerance: "Aggressive"}
      assert {:ok, aggressive_rec} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, aggressive_context)
      
      # Verify different approaches yield different reasoning
      refute conservative_rec.reasoning == aggressive_rec.reasoning
      
      # Conservative should generally have higher confidence
      assert conservative_rec.confidence >= aggressive_rec.confidence - 0.1
    end
  end

  describe "RecommendationEngine.generate_trade_analysis/2" do
    test "analyzes trade proposals with AI reasoning" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      trade_proposal = %{
        offered_players: ["player_1", "player_2"],
        requested_players: ["player_3"],
        offered_picks: [%{year: 2024, round: 2}],
        requested_picks: [],
        competitive_window: "Contending"
      }

      assert {:ok, analysis} = RecommendationEngine.generate_trade_analysis(fantasy_team_id, trade_proposal)
      
      assert %{
        recommendation: recommendation,
        confidence_score: confidence,
        value_analysis: value_analysis,
        player_analysis: player_analysis,
        counter_suggestions: counter_suggestions,
        reasoning: reasoning
      } = analysis

      assert recommendation in ["Accept", "Decline", "Counter"]
      assert is_number(confidence) and confidence >= 0 and confidence <= 1.0
      
      assert %{
        immediate_value: _,
        dynasty_value: _,
        positional_need: _,
        total_score: _
      } = value_analysis

      assert is_list(player_analysis)
      assert length(player_analysis) >= 3  # Should analyze all players in trade
      
      assert is_list(counter_suggestions)
      assert is_binary(reasoning) and String.length(reasoning) > 50
    end

    test "considers competitive window in trade analysis" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      
      # Trade for rebuilding team
      rebuilding_proposal = %{
        offered_players: ["veteran_player"],
        requested_players: ["young_player"],
        competitive_window: "Rebuilding"
      }
      
      # Trade for contending team
      contending_proposal = %{
        offered_players: ["young_player"],
        requested_players: ["veteran_player"],
        competitive_window: "Contending"
      }

      assert {:ok, rebuilding_analysis} = RecommendationEngine.generate_trade_analysis(fantasy_team_id, rebuilding_proposal)
      assert {:ok, contending_analysis} = RecommendationEngine.generate_trade_analysis(fantasy_team_id, contending_proposal)
      
      # Should provide different reasoning based on competitive window
      refute rebuilding_analysis.reasoning == contending_analysis.reasoning
    end

    test "handles complex multi-player trades" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      complex_trade = %{
        offered_players: ["player_1", "player_2", "player_3"],
        requested_players: ["player_4", "player_5"],
        offered_picks: [%{year: 2024, round: 3}, %{year: 2025, round: 1}],
        requested_picks: [%{year: 2024, round: 2}],
        competitive_window: "Neutral"
      }

      assert {:ok, analysis} = RecommendationEngine.generate_trade_analysis(fantasy_team_id, complex_trade)
      
      # Should analyze all players and picks
      assert length(analysis.player_analysis) >= 5
      
      # Should consider pick values
      assert String.contains?(analysis.reasoning, "pick") or String.contains?(analysis.reasoning, "draft")
    end
  end

  describe "RecommendationEngine.generate_pickup_suggestions/2" do
    test "suggests waiver wire pickups with AI analysis" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{
        week: 5,
        season: 2024,
        positions: ["RB", "WR"],
        budget_available: 50,
        max_suggestions: 5
      }

      assert {:ok, suggestions} = RecommendationEngine.generate_pickup_suggestions(fantasy_team_id, context)
      
      assert %{
        recommendations: recommendations,
        drops_to_consider: drops
      } = suggestions

      assert is_list(recommendations)
      assert length(recommendations) <= 5
      assert is_list(drops)

      # Verify pickup recommendations structure
      Enum.each(recommendations, fn pickup ->
        assert %{
          player_id: _,
          name: _,
          position: position,
          ownership_percentage: ownership,
          projected_points: _,
          dynasty_value: _,
          suggested_bid: bid,
          reasoning: reasoning,
          urgency: urgency
        } = pickup

        assert position in ["RB", "WR"]
        assert is_number(ownership) and ownership >= 0 and ownership <= 100
        assert is_integer(bid) and bid <= 50  # Respects budget
        assert is_binary(reasoning)
        assert urgency in ["Low", "Medium", "High", "Critical"]
      end)

      # Verify drop suggestions
      Enum.each(drops, fn drop ->
        assert %{
          player_id: _,
          name: _,
          reasoning: _
        } = drop
      end)
    end

    test "prioritizes urgent pickups appropriately" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{
        week: 1,
        season: 2024,
        positions: ["RB"],
        budget_available: 100
      }

      assert {:ok, suggestions} = RecommendationEngine.generate_pickup_suggestions(fantasy_team_id, context)
      
      # Should have at least some recommendations
      assert length(suggestions.recommendations) > 0
      
      # Critical/High urgency pickups should have higher suggested bids
      urgent_pickups = Enum.filter(suggestions.recommendations, &(&1.urgency in ["Critical", "High"]))
      low_urgency_pickups = Enum.filter(suggestions.recommendations, &(&1.urgency in ["Low", "Medium"]))
      
      if length(urgent_pickups) > 0 and length(low_urgency_pickups) > 0 do
        avg_urgent_bid = urgent_pickups |> Enum.map(&(&1.suggested_bid)) |> Enum.sum() |> div(length(urgent_pickups))
        avg_low_bid = low_urgency_pickups |> Enum.map(&(&1.suggested_bid)) |> Enum.sum() |> div(length(low_urgency_pickups))
        
        assert avg_urgent_bid >= avg_low_bid
      end
    end
  end

  describe "RecommendationEngine.generate_keeper_optimization/2" do
    test "optimizes keeper selections for dynasty leagues" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{
        keeper_deadline: ~D[2024-08-15],
        max_keepers: 3,
        competitive_window: "Rebuilding"
      }

      assert {:ok, optimization} = RecommendationEngine.generate_keeper_optimization(fantasy_team_id, context)
      
      assert %{
        recommended_keepers: keepers,
        alternatives: alternatives,
        non_keeper_recommendations: non_keepers
      } = optimization

      assert is_list(keepers)
      assert length(keepers) <= 3
      assert is_list(alternatives)
      assert is_list(non_keepers)

      # Verify keeper recommendations
      Enum.each(keepers, fn keeper ->
        assert %{
          player_id: _,
          name: _,
          position: _,
          keeper_cost: cost,
          value_over_cost: value,
          dynasty_potential: potential,
          reasoning: reasoning
        } = keeper

        assert is_integer(cost) and cost >= 1
        assert is_number(value)
        assert is_number(potential) and potential >= 0 and potential <= 100
        assert is_binary(reasoning)
      end)

      # Verify alternatives provide different scenarios
      Enum.each(alternatives, fn alt ->
        assert %{
          scenario: _,
          keepers: _,
          total_value: _,
          reasoning: _
        } = alt
      end)
    end

    test "adjusts keeper strategy based on competitive window" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      
      # Contending team should prioritize immediate value
      contending_context = %{
        keeper_deadline: ~D[2024-08-15],
        max_keepers: 2,
        competitive_window: "Contending"
      }
      
      # Rebuilding team should prioritize dynasty potential
      rebuilding_context = %{
        keeper_deadline: ~D[2024-08-15],
        max_keepers: 2,
        competitive_window: "Rebuilding"
      }

      assert {:ok, contending_opt} = RecommendationEngine.generate_keeper_optimization(fantasy_team_id, contending_context)
      assert {:ok, rebuilding_opt} = RecommendationEngine.generate_keeper_optimization(fantasy_team_id, rebuilding_context)
      
      # Should provide different reasoning based on strategy
      contending_reasoning = contending_opt.recommended_keepers |> Enum.map(&(&1.reasoning)) |> Enum.join(" ")
      rebuilding_reasoning = rebuilding_opt.recommended_keepers |> Enum.map(&(&1.reasoning)) |> Enum.join(" ")
      
      refute contending_reasoning == rebuilding_reasoning
    end
  end

  describe "FantasyTools integration" do
    test "AI can access player statistics through tools" do
      player_id = "550e8400-e29b-41d4-a716-446655440000"
      
      assert {:ok, stats} = FantasyTools.get_player_stats(player_id, 2024)
      
      assert %{
        season_stats: season_stats,
        recent_games: recent_games,
        projections: projections
      } = stats

      assert is_map(season_stats)
      assert is_list(recent_games)
      assert is_map(projections) or is_nil(projections)
    end

    test "AI can access league standings and matchups" do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      
      assert {:ok, league_data} = FantasyTools.get_league_context(league_id)
      
      assert %{
        standings: standings,
        current_week: week,
        playoff_picture: playoffs,
        waiver_order: waivers
      } = league_data

      assert is_list(standings)
      assert is_integer(week) and week >= 1 and week <= 18
      assert is_map(playoffs) or is_nil(playoffs)
      assert is_list(waivers)
    end

    test "AI can access team roster and needs analysis" do
      team_id = "550e8400-e29b-41d4-a716-446655440000"
      
      assert {:ok, team_analysis} = FantasyTools.analyze_team_needs(team_id)
      
      assert %{
        positional_strength: strengths,
        positional_needs: needs,
        competitive_window: window,
        roster_construction: construction
      } = team_analysis

      assert is_map(strengths)
      assert is_list(needs)
      assert window in ["Contending", "Rebuilding", "Neutral"]
      assert is_map(construction)
    end

    test "AI tools handle invalid inputs gracefully" do
      # Invalid player ID
      assert {:error, :player_not_found} = FantasyTools.get_player_stats("invalid", 2024)
      
      # Invalid league ID  
      assert {:error, :league_not_found} = FantasyTools.get_league_context("invalid")
      
      # Invalid team ID
      assert {:error, :team_not_found} = FantasyTools.analyze_team_needs("invalid")
    end
  end

  describe "Claude API integration" do
    test "handles Claude API connection errors" do
      # Mock Claude API failure
      expect(ClaudeMock, :messages, fn _params ->
        {:error, %{reason: :connection_error}}
      end)

      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{week: 1, season: 2024}

      assert {:error, :ai_service_unavailable} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
    end

    test "handles Claude API rate limiting" do
      expect(ClaudeMock, :messages, fn _params ->
        {:error, %{reason: :rate_limited, retry_after: 60}}
      end)

      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{week: 1, season: 2024}

      assert {:error, :rate_limited} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
    end

    test "validates and sanitizes AI responses" do
      # Mock malformed Claude response
      expect(ClaudeMock, :messages, fn _params ->
        {:ok, %{
          content: [%{
            type: "text",
            text: "Invalid JSON response without proper structure"
          }]
        }}
      end)

      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{week: 1, season: 2024}

      assert {:error, :invalid_ai_response} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
    end

    test "successfully parses structured AI responses" do
      # Mock well-formed Claude response
      mock_response = %{
        optimal_lineup: %{
          qb: %{player_id: "1", name: "Josh Allen", projected_points: 22.5, confidence: 0.85},
          rb1: %{player_id: "2", name: "Christian McCaffrey", projected_points: 18.3, confidence: 0.90}
          # ... etc
        },
        confidence_score: 0.87,
        reasoning: "Based on matchup analysis and recent performance trends..."
      }

      expect(ClaudeMock, :messages, fn _params ->
        {:ok, %{
          content: [%{
            type: "text", 
            text: Jason.encode!(mock_response)
          }]
        }}
      end)

      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{week: 1, season: 2024}

      assert {:ok, recommendation} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
      assert recommendation.confidence_score == 0.87
      assert String.contains?(recommendation.reasoning, "matchup analysis")
    end
  end

  describe "recommendation persistence" do
    test "saves generated recommendations to database" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{week: 1, season: 2024}

      assert {:ok, recommendation} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
      
      # Should create a Recommendation record
      assert %{id: rec_id} = recommendation
      assert is_binary(rec_id)
      
      # Should be retrievable
      assert {:ok, saved_rec} = RecommendationEngine.get_recommendation(rec_id)
      assert saved_rec.id == rec_id
      assert saved_rec.recommendation_type == "Lineup"
    end

    test "sets appropriate expiration times for recommendations" do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      context = %{week: 1, season: 2024}

      assert {:ok, recommendation} = RecommendationEngine.generate_lineup_recommendation(fantasy_team_id, context)
      
      # Lineup recommendations should expire relatively quickly
      assert recommendation.expires_at
      expires_in_hours = DateTime.diff(recommendation.expires_at, DateTime.utc_now(), :hour)
      assert expires_in_hours <= 48  # Should expire within 48 hours
    end
  end
end