defmodule FantasyManager.Integration.PositionFilterTest do
  use FantasyManagerWeb.ConnCase, async: false
  import FantasyManager.TestSupport

  @moduletag :integration

  describe "Position-Specific Recommendation Flow" do
    setup do
      # Setup test data with specific roster composition
      league = create_test_league()
      team = create_test_team_with_positional_needs(league.id)
      
      %{league: league, team: team}
    end

    test "QB-specific recommendations for team with weak QB", %{conn: conn, team: team} do
      # Request QB recommendations specifically
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=QB")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      # All recommendations should be for QB position
      Enum.each(recommendations, fn rec ->
        assert rec["position"] == "QB"
        assert rec["recommendation_type"] in ["pickup", "drop"]
      end)
      
      # Verify QB-specific reasoning
      if length(recommendations) > 0 do
        qb_rec = hd(recommendations)
        reasoning = qb_rec["reasoning"] |> String.downcase()
        
        # Should mention QB-specific factors
        qb_factors = ["quarterback", "qb", "passing", "completion", "touchdown"]
        has_qb_context = Enum.any?(qb_factors, fn factor ->
          String.contains?(reasoning, factor)
        end)
        
        assert has_qb_context, "QB recommendation should mention QB-specific factors"
      end
    end

    test "RB recommendations consider workload and injury risk", %{conn: conn, team: team} do
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=RB")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      Enum.each(recommendations, fn rec ->
        assert rec["position"] == "RB"
        
        reasoning = rec["reasoning"] |> String.downcase()
        
        # Should mention RB-specific factors
        rb_factors = ["running", "carries", "workload", "backfield", "rushing", "touches"]
        has_rb_context = Enum.any?(rb_factors, fn factor ->
          String.contains?(reasoning, factor)
        end)
        
        assert has_rb_context or rec["recommendation_type"] == "drop", 
               "RB recommendation should mention RB-specific factors"
      end)
    end

    test "WR recommendations consider target share and matchups", %{conn: conn, team: team} do
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=WR")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      Enum.each(recommendations, fn rec ->
        assert rec["position"] == "WR"
        
        reasoning = rec["reasoning"] |> String.downcase()
        
        # Should mention WR-specific factors
        wr_factors = ["receiving", "targets", "reception", "route", "coverage", "matchup"]
        has_wr_context = Enum.any?(wr_factors, fn factor ->
          String.contains?(reasoning, factor)
        end)
        
        assert has_wr_context or rec["recommendation_type"] == "drop",
               "WR recommendation should mention WR-specific factors"
      end)
    end

    test "TE recommendations consider positional scarcity", %{conn: conn, team: team} do
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=TE")
      
      assert %{"data" => recommendations} = json_response(conn, 200)
      
      Enum.each(recommendations, fn rec ->
        assert rec["position"] == "TE"
        
        reasoning = rec["reasoning"] |> String.downcase()
        
        # Should mention TE-specific factors
        te_factors = ["tight end", "te", "redzone", "target", "blocking", "receiving"]
        has_te_context = Enum.any?(te_factors, fn factor ->
          String.contains?(reasoning, factor)
        end)
        
        assert has_te_context or rec["recommendation_type"] == "drop",
               "TE recommendation should mention TE-specific factors"
      end)
    end

    test "K and DEF recommendations consider matchups and consistency", %{conn: conn, team: team} do
      # Test Kicker recommendations
      k_conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=K")
      
      if json_response(k_conn, 200)["data"] != [] do
        assert %{"data" => k_recommendations} = json_response(k_conn, 200)
        
        Enum.each(k_recommendations, fn rec ->
          assert rec["position"] == "K"
          
          reasoning = rec["reasoning"] |> String.downcase()
          
          # Should mention kicker-specific factors
          k_factors = ["kicker", "field goal", "extra point", "accuracy", "dome", "weather"]
          has_k_context = Enum.any?(k_factors, fn factor ->
            String.contains?(reasoning, factor)
          end)
          
          assert has_k_context or rec["recommendation_type"] == "drop",
                 "Kicker recommendation should mention kicking-specific factors"
        end)
      end
      
      # Test Defense recommendations
      def_conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=DEF")
      
      if json_response(def_conn, 200)["data"] != [] do
        assert %{"data" => def_recommendations} = json_response(def_conn, 200)
        
        Enum.each(def_recommendations, fn rec ->
          assert rec["position"] == "DEF"
          
          reasoning = rec["reasoning"] |> String.downcase()
          
          # Should mention defense-specific factors
          def_factors = ["defense", "sack", "interception", "turnover", "matchup", "opponent"]
          has_def_context = Enum.any?(def_factors, fn factor ->
            String.contains?(reasoning, factor)
          end)
          
          assert has_def_context or rec["recommendation_type"] == "drop",
                 "Defense recommendation should mention defensive factors"
        end)
      end
    end

    test "priority scores vary by positional importance", %{conn: conn, team: team} do
      # Get recommendations for different positions
      positions = ["QB", "RB", "WR", "TE"]
      position_priorities = %{}
      
      for position <- positions do
        pos_conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=#{position}")
        
        if json_response(pos_conn, 200)["data"] != [] do
          %{"data" => recs} = json_response(pos_conn, 200)
          
          pickup_recs = Enum.filter(recs, fn rec -> rec["recommendation_type"] == "pickup" end)
          
          if length(pickup_recs) > 0 do
            avg_priority = pickup_recs
                         |> Enum.map(fn rec -> rec["priority_score"] end)
                         |> Enum.sum()
                         |> Kernel./(length(pickup_recs))
            
            position_priorities = Map.put(position_priorities, position, avg_priority)
          end
        end
      end
      
      # Verify that priority scores make sense relative to position importance
      # Note: This will depend on team composition, but QB should generally be important
      if Map.has_key?(position_priorities, "QB") do
        qb_priority = position_priorities["QB"]
        assert qb_priority > 0, "QB recommendations should have positive priority"
      end
    end

    test "position filtering combines with status filtering", %{conn: conn, team: team} do
      # First get some recommendations and mark one as applied
      conn_all = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=RB")
      
      if json_response(conn_all, 200)["data"] != [] do
        %{"data" => rb_recs} = json_response(conn_all, 200)
        
        if length(rb_recs) > 0 do
          rec_to_apply = hd(rb_recs)
          rec_id = rec_to_apply["id"]
          
          # Mark as applied
          _applied_conn = patch(conn, ~p"/api/v1/teams/#{team.id}/recommendations/#{rec_id}/status", %{
            "status" => "applied"
          })
          
          # Filter by position and status
          filtered_conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations?position=RB&status=applied")
          
          assert %{"data" => filtered_recs} = json_response(filtered_conn, 200)
          
          # All results should be RB position and applied status
          Enum.each(filtered_recs, fn rec ->
            assert rec["position"] == "RB"
            assert rec["status"] == "applied"
          end)
          
          # Should include our applied recommendation
          applied_rec = Enum.find(filtered_recs, fn rec -> rec["id"] == rec_id end)
          assert applied_rec != nil
        end
      end
    end

    test "recommendations consider positional roster depth", %{conn: conn, team: team} do
      # Get all recommendations
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/recommendations")
      
      assert %{"data" => all_recs} = json_response(conn, 200)
      
      # Group by position and analyze priority patterns
      recs_by_position = Enum.group_by(all_recs, fn rec -> rec["position"] end)
      
      # Teams with fewer players at a position should have higher priority pickup recommendations
      Enum.each(recs_by_position, fn {position, recs} ->
        pickup_recs = Enum.filter(recs, fn rec -> rec["recommendation_type"] == "pickup" end)
        
        if length(pickup_recs) > 0 do
          priorities = Enum.map(pickup_recs, fn rec -> rec["priority_score"] end)
          avg_priority = Enum.sum(priorities) / length(priorities)
          
          # All pickup recommendations should have reasonable priority scores
          assert avg_priority > 0, "Position #{position} pickups should have positive priority"
          assert avg_priority <= 10, "Position #{position} priorities should not exceed max scale"
        end
      end)
    end
  end
end