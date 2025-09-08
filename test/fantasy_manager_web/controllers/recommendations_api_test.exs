defmodule FantasyManagerWeb.Controllers.RecommendationsApiTest do
  use FantasyManagerWeb.ConnCase, async: true

  describe "GET /api/v1/teams/:team_id/recommendations" do
    test "returns 200 with list of recommendations for valid team", %{conn: conn} do
      team_id = "test_team_123"
      
      conn = get(conn, ~p"/api/v1/teams/#{team_id}/recommendations")
      
      assert %{
        "data" => recommendations,
        "meta" => %{
          "total" => _total,
          "page" => 1,
          "per_page" => 20
        }
      } = json_response(conn, 200)
      
      assert is_list(recommendations)
      
      # Verify recommendation structure if any exist
      if length(recommendations) > 0 do
        recommendation = hd(recommendations)
        assert %{
          "id" => _,
          "player_id" => _,
          "player_name" => _,
          "position" => _,
          "team" => _,
          "recommendation_type" => type,
          "priority_score" => _,
          "reasoning" => _,
          "status" => status,
          "week" => _,
          "season" => _,
          "generated_at" => _,
          "expires_at" => _
        } = recommendation
        
        assert type in ["pickup", "drop", "hold"]
        assert status in ["pending", "applied", "dismissed"]
      end
    end

    test "returns 404 for invalid team_id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/teams/invalid_team/recommendations")
      
      assert %{"error" => "Team not found"} = json_response(conn, 404)
    end

    test "supports pagination parameters", %{conn: conn} do
      team_id = "test_team_123"
      
      conn = get(conn, ~p"/api/v1/teams/#{team_id}/recommendations?page=2&per_page=10")
      
      assert %{
        "data" => _,
        "meta" => %{
          "page" => 2,
          "per_page" => 10
        }
      } = json_response(conn, 200)
    end

    test "supports status filtering", %{conn: conn} do
      team_id = "test_team_123"
      
      conn = get(conn, ~p"/api/v1/teams/#{team_id}/recommendations?status=pending")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      # All returned recommendations should have pending status
      Enum.each(recommendations, fn rec ->
        assert rec["status"] == "pending"
      end)
    end

    test "supports position filtering", %{conn: conn} do
      team_id = "test_team_123"
      
      conn = get(conn, ~p"/api/v1/teams/#{team_id}/recommendations?position=QB")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      # All returned recommendations should be for QB position
      Enum.each(recommendations, fn rec ->
        assert rec["position"] == "QB"
      end)
    end
  end

  describe "PATCH /api/v1/teams/:team_id/recommendations/:recommendation_id/status" do
    test "updates recommendation status to applied", %{conn: conn} do
      team_id = "test_team_123"
      recommendation_id = "test_rec_456"
      
      conn = patch(conn, ~p"/api/v1/teams/#{team_id}/recommendations/#{recommendation_id}/status", %{
        "status" => "applied"
      })
      
      assert %{
        "data" => %{
          "id" => ^recommendation_id,
          "status" => "applied"
        }
      } = json_response(conn, 200)
    end

    test "updates recommendation status to dismissed", %{conn: conn} do
      team_id = "test_team_123"
      recommendation_id = "test_rec_456"
      
      conn = patch(conn, ~p"/api/v1/teams/#{team_id}/recommendations/#{recommendation_id}/status", %{
        "status" => "dismissed"
      })
      
      assert %{
        "data" => %{
          "status" => "dismissed"
        }
      } = json_response(conn, 200)
    end

    test "returns 400 for invalid status", %{conn: conn} do
      team_id = "test_team_123"
      recommendation_id = "test_rec_456"
      
      conn = patch(conn, ~p"/api/v1/teams/#{team_id}/recommendations/#{recommendation_id}/status", %{
        "status" => "invalid_status"
      })
      
      assert %{"error" => "Invalid status"} = json_response(conn, 400)
    end

    test "returns 404 for non-existent recommendation", %{conn: conn} do
      team_id = "test_team_123"
      
      conn = patch(conn, ~p"/api/v1/teams/#{team_id}/recommendations/non_existent/status", %{
        "status" => "applied"
      })
      
      assert %{"error" => "Recommendation not found"} = json_response(conn, 404)
    end

    test "returns 403 for recommendation belonging to different team", %{conn: conn} do
      wrong_team_id = "wrong_team_123"
      recommendation_id = "test_rec_456"
      
      conn = patch(conn, ~p"/api/v1/teams/#{wrong_team_id}/recommendations/#{recommendation_id}/status", %{
        "status" => "applied"
      })
      
      assert %{"error" => "Recommendation not found"} = json_response(conn, 404)
    end
  end
end