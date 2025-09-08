defmodule FantasyManagerWeb.RecommendationsApiTest do
  use FantasyManagerWeb.ConnCase
  import FantasyManager.TestSupport

  @recommendations_endpoint "/api/v1/recommendations"
  @lineups_optimize_endpoint "/api/v1/lineups/optimize"
  @trades_analyze_endpoint "/api/v1/trades/analyze"
  @trades_suggest_endpoint "/api/v1/trades/suggest"
  @pickups_analyze_endpoint "/api/v1/pickups/analyze"
  @keepers_optimize_endpoint "/api/v1/keepers/optimize"
  @dynasty_plan_endpoint "/api/v1/dynasty/plan"

  describe "GET /api/v1/recommendations" do
    test "returns list of recommendations for a team", %{conn: conn} do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, @recommendations_endpoint, %{"fantasy_team_id" => fantasy_team_id})
      
      response = json_response(conn, 200)
      assert %{"data" => recommendations} = response
      assert is_list(recommendations)

      Enum.each(recommendations, fn rec ->
        assert %{
          "type" => "recommendation",
          "id" => _,
          "attributes" => %{
            "recommendation_type" => type,
            "context" => _,
            "recommendation_data" => _,
            "confidence_score" => score,
            "reasoning" => _,
            "time_horizon" => horizon,
            "ai_model" => _,
            "expires_at" => _,
            "inserted_at" => _
          }
        } = rec

        assert type in ["Lineup", "Trade", "Pickup", "Keeper", "Dynasty"]
        assert is_number(score) and score >= 0 and score <= 1
        assert horizon in ["Short", "Medium", "Long"]
      end)
    end

    test "filters recommendations by type", %{conn: conn} do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, @recommendations_endpoint, %{
        "fantasy_team_id" => fantasy_team_id,
        "recommendation_type" => "Lineup"
      })
      
      response = json_response(conn, 200)
      assert %{"data" => recommendations} = response

      Enum.each(recommendations, fn rec ->
        assert %{
          "attributes" => %{"recommendation_type" => "Lineup"}
        } = rec
      end)
    end

    test "filters recommendations by time horizon", %{conn: conn} do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, @recommendations_endpoint, %{
        "fantasy_team_id" => fantasy_team_id,
        "time_horizon" => "Short"
      })
      
      response = json_response(conn, 200)
      assert %{"data" => recommendations} = response

      Enum.each(recommendations, fn rec ->
        assert %{
          "attributes" => %{"time_horizon" => "Short"}
        } = rec
      end)
    end

    test "supports pagination", %{conn: conn} do
      fantasy_team_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, @recommendations_endpoint, %{
        "fantasy_team_id" => fantasy_team_id,
        "page[size]" => "5"
      })
      
      response = json_response(conn, 200)
      assert %{"data" => recommendations} = response
      assert length(recommendations) <= 5
    end
  end

  describe "POST /api/v1/recommendations" do
    test "generates new recommendation", %{conn: conn} do
      recommendation_data = %{
        "data" => %{
          "type" => "recommendation",
          "attributes" => %{
            "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
            "recommendation_type" => "Lineup",
            "context" => %{"week" => 1, "season" => 2024},
            "time_horizon" => "Short"
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(@recommendations_endpoint, recommendation_data)
      
      response = json_response(conn, 201)
      assert %{
        "data" => %{
          "type" => "recommendation",
          "id" => _,
          "attributes" => %{
            "recommendation_type" => "Lineup",
            "confidence_score" => _,
            "reasoning" => _
          }
        }
      } = response
    end

    test "returns 422 for invalid recommendation request", %{conn: conn} do
      invalid_data = %{
        "data" => %{
          "type" => "recommendation",
          "attributes" => %{
            "recommendation_type" => "Lineup"
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(@recommendations_endpoint, invalid_data)
      
      response = json_response(conn, 422)
      assert %{"errors" => [%{"status" => "422"}]} = response
    end

    test "returns 503 when AI service unavailable", %{conn: conn} do
      recommendation_data = %{
        "data" => %{
          "type" => "recommendation",
          "attributes" => %{
            "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
            "recommendation_type" => "Lineup",
            "context" => %{"week" => 1, "season" => 2024}
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(@recommendations_endpoint, recommendation_data)
      
      response = json_response(conn, 503)
      assert %{"errors" => [%{"status" => "503"}]} = response
    end
  end

  describe "GET /api/v1/recommendations/:recommendation_id" do
    test "returns recommendation details", %{conn: conn} do
      rec_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, "#{@recommendations_endpoint}/#{rec_id}")
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "recommendation",
          "id" => ^rec_id,
          "attributes" => %{
            "recommendation_type" => _,
            "confidence_score" => _,
            "reasoning" => _
          }
        }
      } = response
    end

    test "returns 404 for non-existent recommendation", %{conn: conn} do
      non_existent_id = "550e8400-e29b-41d4-a716-999999999999"
      conn = get(conn, "#{@recommendations_endpoint}/#{non_existent_id}")
      
      response = json_response(conn, 404)
      assert %{"errors" => [%{"status" => "404"}]} = response
    end
  end

  describe "POST /api/v1/lineups/optimize" do
    test "returns optimal lineup recommendations", %{conn: conn} do
      request_data = %{
        "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
        "week" => 1,
        "season" => 2024,
        "injury_threshold" => "Questionable",
        "risk_tolerance" => "Balanced"
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@lineups_optimize_endpoint, request_data)
      
      response = json_response(conn, 200)
      assert %{
        "optimal_lineup" => optimal_lineup,
        "projected_total" => projected_total,
        "confidence_score" => confidence,
        "alternatives" => alternatives,
        "reasoning" => reasoning
      } = response

      assert %{
        "qb" => qb,
        "rb1" => rb1,
        "rb2" => rb2,
        "wr1" => wr1,
        "wr2" => wr2,
        "te" => te,
        "flex" => flex,
        "k" => k,
        "def" => def
      } = optimal_lineup

      assert is_number(projected_total) and projected_total >= 0
      assert is_number(confidence) and confidence >= 0 and confidence <= 1
      assert is_list(alternatives)
      assert is_binary(reasoning)

      # Verify lineup player structure
      Enum.each([qb, rb1, rb2, wr1, wr2, te, flex, k, def], fn player ->
        assert %{
          "player_id" => _,
          "name" => _,
          "position" => _,
          "projected_points" => points,
          "confidence" => conf,
          "matchup_analysis" => _,
          "injury_risk" => risk
        } = player

        assert is_number(points)
        assert is_number(conf) and conf >= 0 and conf <= 1
        assert risk in ["Low", "Medium", "High"]
      end)
    end

    test "returns 422 for invalid lineup optimization request", %{conn: conn} do
      invalid_data = %{
        "week" => 1
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@lineups_optimize_endpoint, invalid_data)
      
      response = json_response(conn, 422)
      assert %{"errors" => _} = response
    end
  end

  describe "POST /api/v1/trades/analyze" do
    test "analyzes trade proposal", %{conn: conn} do
      request_data = %{
        "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
        "offered_players" => ["550e8400-e29b-41d4-a716-446655440001"],
        "requested_players" => ["550e8400-e29b-41d4-a716-446655440002"],
        "competitive_window" => "Contending"
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@trades_analyze_endpoint, request_data)
      
      response = json_response(conn, 200)
      assert %{
        "recommendation" => recommendation,
        "confidence_score" => confidence,
        "value_analysis" => value_analysis,
        "player_analysis" => player_analysis,
        "counter_suggestions" => counter_suggestions,
        "reasoning" => reasoning
      } = response

      assert recommendation in ["Accept", "Decline", "Counter"]
      assert is_number(confidence) and confidence >= 0 and confidence <= 1
      assert %{
        "immediate_value" => _,
        "dynasty_value" => _,
        "positional_need" => _,
        "total_score" => _
      } = value_analysis
      assert is_list(player_analysis)
      assert is_list(counter_suggestions)
      assert is_binary(reasoning)
    end

    test "returns 422 for invalid trade analysis request", %{conn: conn} do
      invalid_data = %{
        "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000"
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@trades_analyze_endpoint, invalid_data)
      
      response = json_response(conn, 422)
      assert %{"errors" => _} = response
    end
  end

  describe "POST /api/v1/trades/suggest" do
    test "generates trade suggestions", %{conn: conn} do
      request_data = %{
        "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
        "needs" => ["RB", "WR"],
        "surplus" => ["QB", "TE"],
        "max_suggestions" => 3
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@trades_suggest_endpoint, request_data)
      
      response = json_response(conn, 200)
      assert %{"suggestions" => suggestions} = response
      assert is_list(suggestions)
      assert length(suggestions) <= 3

      Enum.each(suggestions, fn suggestion ->
        assert %{
          "target_team_id" => _,
          "target_team_name" => _,
          "offered_players" => offered,
          "requested_players" => requested,
          "fairness_score" => fairness,
          "mutual_benefit" => _,
          "reasoning" => _
        } = suggestion

        assert is_list(offered)
        assert is_list(requested)
        assert is_number(fairness) and fairness >= 0 and fairness <= 1
      end)
    end
  end

  describe "POST /api/v1/pickups/analyze" do
    test "analyzes available free agents", %{conn: conn} do
      request_data = %{
        "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
        "week" => 1,
        "season" => 2024,
        "positions" => ["RB", "WR"],
        "budget_available" => 100,
        "max_suggestions" => 10
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@pickups_analyze_endpoint, request_data)
      
      response = json_response(conn, 200)
      assert %{
        "recommendations" => recommendations,
        "drops_to_consider" => drops
      } = response

      assert is_list(recommendations)
      assert is_list(drops)
      assert length(recommendations) <= 10

      Enum.each(recommendations, fn rec ->
        assert %{
          "player_id" => _,
          "name" => _,
          "position" => pos,
          "ownership_percentage" => ownership,
          "projected_points" => _,
          "dynasty_value" => _,
          "suggested_bid" => _,
          "reasoning" => _,
          "urgency" => urgency
        } = rec

        assert pos in ["RB", "WR"]
        assert is_number(ownership) and ownership >= 0 and ownership <= 100
        assert urgency in ["Low", "Medium", "High", "Critical"]
      end)
    end
  end

  describe "POST /api/v1/keepers/optimize" do
    test "optimizes keeper selections", %{conn: conn} do
      request_data = %{
        "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
        "keeper_deadline" => "2024-08-15",
        "max_keepers" => 3,
        "competitive_window" => "Contending"
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@keepers_optimize_endpoint, request_data)
      
      response = json_response(conn, 200)
      assert %{
        "recommended_keepers" => keepers,
        "alternatives" => alternatives,
        "non_keeper_recommendations" => non_keepers
      } = response

      assert is_list(keepers)
      assert is_list(alternatives)
      assert is_list(non_keepers)
      assert length(keepers) <= 3

      Enum.each(keepers, fn keeper ->
        assert %{
          "player_id" => _,
          "name" => _,
          "position" => _,
          "keeper_cost" => cost,
          "value_over_cost" => _,
          "dynasty_potential" => _,
          "reasoning" => _
        } = keeper

        assert is_integer(cost) and cost >= 1
      end)
    end
  end

  describe "POST /api/v1/dynasty/plan" do
    test "generates dynasty transition plan", %{conn: conn} do
      request_data = %{
        "fantasy_team_id" => "550e8400-e29b-41d4-a716-446655440000",
        "transition_timeline" => "Next_Season",
        "current_strategy" => "Rebuilding",
        "risk_tolerance" => "Balanced"
      }

      conn = conn
        |> put_req_header("content-type", "application/json")
        |> post(@dynasty_plan_endpoint, request_data)
      
      response = json_response(conn, 200)
      assert %{
        "recommended_strategy" => strategy,
        "timeline" => timeline,
        "trade_targets" => trade_targets,
        "draft_strategy" => draft_strategy,
        "success_metrics" => success_metrics,
        "reasoning" => reasoning
      } = response

      assert strategy in ["Win_Now", "Gradual_Rebuild", "Full_Rebuild", "Stay_Course"]
      assert %{
        "phase_1" => %{"duration" => _, "actions" => _, "targets" => _},
        "phase_2" => %{"duration" => _, "actions" => _}
      } = timeline
      assert is_list(trade_targets)
      assert %{
        "early_rounds" => _,
        "middle_rounds" => _,
        "late_rounds" => _
      } = draft_strategy
      assert is_list(success_metrics)
      assert is_binary(reasoning)
    end
  end
end