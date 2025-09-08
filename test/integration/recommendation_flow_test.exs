defmodule FantasyManager.Integration.RecommendationFlowTest do
  use FantasyManagerWeb.ConnCase, async: false
  import FantasyManager.TestSupport

  @moduletag :integration

  describe "Basic Recommendation Request Flow" do
    setup do
      # Setup test data
      league = create_test_league()
      team = create_test_team(league.id, "Test Team")
      
      %{league: league, team: team}
    end

    test "complete waiver recommendation flow", %{conn: conn, team: team} do
      # Step 1: Request waiver recommendations for a team
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations")
      
      assert %{
        "data" => recommendations,
        "meta" => meta
      } = json_response(conn, 200)
      
      assert is_list(recommendations)
      assert %{"total" => total} = meta
      
      # Step 2: Verify recommendation structure and AI-generated content
      if length(recommendations) > 0 do
        recommendation = hd(recommendations)
        
        assert %{
          "id" => rec_id,
          "player_id" => player_id,
          "player_name" => player_name,
          "position" => position,
          "recommendation_type" => rec_type,
          "priority_score" => priority_score,
          "reasoning" => reasoning,
          "status" => "pending"
        } = recommendation
        
        # Verify AI-generated content structure
        assert is_binary(player_id) and player_id != ""
        assert is_binary(player_name) and player_name != ""
        assert position in ["QB", "RB", "WR", "TE", "K", "DEF"]
        assert rec_type in ["pickup", "drop", "hold"]
        assert is_number(priority_score) and priority_score >= 0 and priority_score <= 10
        assert is_binary(reasoning) and String.length(reasoning) > 10
        
        # Step 3: Update recommendation status to "applied"
        conn = patch(conn, ~p"/api/v1/teams/#{team.id}/recommendations/#{rec_id}/status", %{
          "status" => "applied"
        })
        
        assert %{
          "data" => %{
            "id" => ^rec_id,
            "status" => "applied"
          }
        } = json_response(conn, 200)
        
        # Step 4: Verify status was updated by fetching recommendations again
        conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?status=applied")
        
        assert %{"data" => applied_recs} = json_response(conn, 200)
        
        applied_rec = Enum.find(applied_recs, fn rec -> rec["id"] == rec_id end)
        assert applied_rec != nil
        assert applied_rec["status"] == "applied"
      end
    end

    test "recommendation generation integrates with trending data", %{conn: conn, team: team} do
      # Step 1: Sync trending data first
      sync_conn = post(conn, ~p"/api/v1/trending/sync", %{
        "trend_type" => "add",
        "week" => 8,
        "season" => 2024
      })
      
      assert %{
        "data" => %{
          "sync_status" => "completed",
          "players_synced" => synced_count
        }
      } = json_response(sync_conn, 200)
      
      # Step 2: Request recommendations (should incorporate trending data)
      rec_conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations")
      
      assert %{"data" => recommendations} = json_response(rec_conn, 200)
      
      # Step 3: Verify recommendations consider trending data
      if length(recommendations) > 0 do
        pickup_recs = Enum.filter(recommendations, fn rec ->
          rec["recommendation_type"] == "pickup"
        end)
        
        # At least some recommendations should reference trending players
        if length(pickup_recs) > 0 do
          # Check that reasoning mentions trending data or popularity
          trending_mentions = Enum.count(pickup_recs, fn rec ->
            reasoning = rec["reasoning"] |> String.downcase()
            String.contains?(reasoning, "trending") or 
            String.contains?(reasoning, "popular") or
            String.contains?(reasoning, "waiver")
          end)
          
          assert trending_mentions > 0, "Expected at least one recommendation to mention trending data"
        end
      end
    end

    test "recommendation request handles team with no roster", %{conn: conn} do
      # Create empty team
      league = create_test_league()
      empty_team = create_test_team(league.id, "Empty Team", [])  # No players
      
      conn = get(conn, ~p"/api/v1/teams/#{empty_team.id}/recommendations")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      # Should still generate recommendations, focusing on essential positions
      if length(recommendations) > 0 do
        positions = Enum.map(recommendations, fn rec -> rec["position"] end)
        
        # Should prioritize core positions like QB, RB, WR
        core_positions = Enum.filter(positions, fn pos -> pos in ["QB", "RB", "WR"] end)
        assert length(core_positions) > 0, "Expected recommendations for core positions"
      end
    end

    test "recommendation expiry and cleanup", %{conn: conn, team: team} do
      # Step 1: Generate recommendations
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      if length(recommendations) > 0 do
        recommendation = hd(recommendations)
        expires_at = recommendation["expires_at"]
        
        # Verify expiration date is set and in the future
        assert expires_at != nil
        assert is_binary(expires_at)
        
        {:ok, expiry_datetime, _} = DateTime.from_iso8601(expires_at)
        assert DateTime.compare(expiry_datetime, DateTime.utc_now()) == :gt
      end
    end

    test "error handling for invalid team", %{conn: conn} do
      invalid_team_id = "non-existent-team-id"
      
      conn = get(conn, ~p"/api/v1/teams/#{invalid_team_id}/recommendations")
      
      assert %{"error" => "Team not found"} = json_response(conn, 404)
    end

    test "recommendation pagination works correctly", %{conn: conn, team: team} do
      # Request with pagination
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?page=1&per_page=3")
      
      assert %{
        "data" => recommendations,
        "meta" => %{
          "page" => 1,
          "per_page" => 3,
          "total" => total
        }
      } = json_response(conn, 200)
      
      assert length(recommendations) <= 3
      assert is_integer(total)
      
      # If there are more than 3 total, test second page
      if total > 3 do
        conn2 = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?page=2&per_page=3")
        
        assert %{
          "data" => page2_recs,
          "meta" => %{"page" => 2}
        } = json_response(conn2, 200)
        
        # Verify no duplicate recommendations between pages
        page1_ids = Enum.map(recommendations, fn rec -> rec["id"] end)
        page2_ids = Enum.map(page2_recs, fn rec -> rec["id"] end)
        
        assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
      end
    end
  end
end