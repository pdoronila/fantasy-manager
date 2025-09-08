defmodule FantasyManagerWeb.Integration.UserJourneyTest do
  use FantasyManagerWeb.ConnCase
  import Phoenix.LiveViewTest
  alias FantasyManager.TestSupport.MockData

  @moduletag :integration

  describe "Core User Journey: Create league → View players → Get recommendations" do
    test "complete user workflow through web interface", %{conn: conn} do
      # Step 1: Navigate to dashboard
      {:ok, dashboard_live, html} = live(conn, "/")
      
      assert html =~ "Fantasy Manager"
      assert html =~ "Dashboard"
      
      # Should show empty state initially
      assert has_element?(dashboard_live, "[data-testid='empty-leagues']")
      assert has_element?(dashboard_live, "button", "Add League")

      # Step 2: Create/Import League from Sleeper
      dashboard_live
      |> element("button", "Add League")
      |> render_click()

      # Should show league import form
      assert has_element?(dashboard_live, "[data-testid='league-import-form']")
      assert has_element?(dashboard_live, "input[name='sleeper_id']")

      # Submit Sleeper league ID
      dashboard_live
      |> form("[data-testid='league-import-form']", league: %{sleeper_id: "123456789"})
      |> render_submit()

      # Should show loading state then success
      assert render(dashboard_live) =~ "Importing league"
      
      # Wait for import to complete (mocked)
      :timer.sleep(100)
      
      # Should redirect to league details or show success
      assert_redirect(dashboard_live, "/leagues/#{MockData.sample_league_id()}")

      # Step 3: View League Details
      {:ok, league_live, html} = live(conn, "/leagues/#{MockData.sample_league_id()}")
      
      assert html =~ "Test Dynasty League"
      assert html =~ "Dynasty League"
      assert html =~ "2024 Season"
      
      # Should show teams
      assert has_element?(league_live, "[data-testid='team-list']")
      assert has_element?(league_live, "[data-testid='team-card']")
      
      # Should show navigation options
      assert has_element?(league_live, "a", "View Players")
      assert has_element?(league_live, "a", "Get Recommendations")

      # Step 4: Browse Players
      league_live
      |> element("a", "View Players")
      |> render_click()

      assert_redirected(league_live, "/players")

      {:ok, players_live, html} = live(conn, "/players")
      
      assert html =~ "Players"
      assert has_element?(players_live, "[data-testid='player-search']")
      assert has_element?(players_live, "[data-testid='position-filter']")
      assert has_element?(players_live, "[data-testid='player-list']")

      # Test player search functionality
      players_live
      |> form("[data-testid='player-search']", search: %{query: "Josh"})
      |> render_submit()

      # Should filter to Josh Allen and other Josh players
      assert render(players_live) =~ "Josh Allen"
      assert has_element?(players_live, "[data-testid='player-card']")

      # Test position filtering
      players_live
      |> element("[data-testid='position-filter'] option[value='QB']")
      |> render_click()

      # Should show only quarterbacks
      player_cards = players_live |> render() |> Floki.find("[data-testid='player-card']")
      assert length(player_cards) > 0

      # Verify QB players have correct position
      assert render(players_live) =~ "position-QB"

      # Step 5: View Player Details
      players_live
      |> element("[data-testid='player-card']:first-child")
      |> render_click()

      # Should show player detail modal or navigate to player page
      assert has_element?(players_live, "[data-testid='player-modal']") or
             assert_redirect(players_live, ~r"/players/.*")

      # If modal, verify player details are shown
      if has_element?(players_live, "[data-testid='player-modal']") do
        assert render(players_live) =~ "dynasty_value"
        assert render(players_live) =~ "injury_status"
        assert has_element?(players_live, "[data-testid='player-stats']")
        
        # Close modal
        players_live
        |> element("[data-testid='close-modal']")
        |> render_click()
      end

      # Step 6: Navigate to Recommendations
      {:ok, recommendations_live, html} = live(conn, "/recommendations")
      
      assert html =~ "AI Recommendations"
      assert has_element?(recommendations_live, "[data-testid='team-selector']")
      
      # Should show different recommendation types
      assert has_element?(recommendations_live, "button", "Lineup Optimization")
      assert has_element?(recommendations_live, "button", "Trade Analysis")
      assert has_element?(recommendations_live, "button", "Waiver Pickups")

      # Step 7: Generate Lineup Recommendation
      # First select a team
      recommendations_live
      |> form("[data-testid='team-selector']", team: %{id: MockData.sample_team_id()})
      |> render_submit()

      assert render(recommendations_live) =~ MockData.sample_team_name()

      # Click lineup optimization
      recommendations_live
      |> element("button", "Lineup Optimization")
      |> render_click()

      # Should show lineup optimization form
      assert has_element?(recommendations_live, "[data-testid='lineup-form']")
      assert has_element?(recommendations_live, "select[name='week']")
      assert has_element?(recommendations_live, "select[name='risk_tolerance']")

      # Submit lineup optimization request
      recommendations_live
      |> form("[data-testid='lineup-form']", lineup: %{
        week: "1",
        risk_tolerance: "Balanced",
        injury_threshold: "Questionable"
      })
      |> render_submit()

      # Should show loading state
      assert render(recommendations_live) =~ "Generating recommendations"
      assert has_element?(recommendations_live, "[data-testid='loading-spinner']")

      # Wait for AI processing (mocked)
      :timer.sleep(500)
      
      # Should show lineup recommendations
      assert render(recommendations_live) =~ "Optimal Lineup"
      assert has_element?(recommendations_live, "[data-testid='recommended-lineup']")
      
      # Verify lineup positions are filled
      positions = ["QB", "RB1", "RB2", "WR1", "WR2", "TE", "FLEX", "K", "DEF"]
      Enum.each(positions, fn position ->
        assert has_element?(recommendations_live, "[data-position='#{position}']")
      end)

      # Should show projected points and confidence
      assert render(recommendations_live) =~ "Projected Points"
      assert render(recommendations_live) =~ "Confidence"
      
      # Should show AI reasoning
      assert has_element?(recommendations_live, "[data-testid='ai-reasoning']")
      assert render(recommendations_live) =~ "Based on"

      # Should show alternative options
      assert has_element?(recommendations_live, "[data-testid='alternatives']")

      # Step 8: Test Trade Analysis
      recommendations_live
      |> element("button", "Trade Analysis")
      |> render_click()

      assert has_element?(recommendations_live, "[data-testid='trade-form']")
      
      # Should show player selection interface
      assert has_element?(recommendations_live, "[data-testid='offered-players']")
      assert has_element?(recommendations_live, "[data-testid='requested-players']")

      # Select players for trade analysis
      recommendations_live
      |> element("[data-testid='add-offered-player']")
      |> render_click()

      # Should show player picker
      assert has_element?(recommendations_live, "[data-testid='player-picker']")

      # Select a player (simplified for test)
      recommendations_live
      |> form("[data-testid='trade-form']", trade: %{
        offered_players: ["player_1"],
        requested_players: ["player_2"],
        competitive_window: "Contending"
      })
      |> render_submit()

      # Should show trade analysis loading
      assert render(recommendations_live) =~ "Analyzing trade"
      
      :timer.sleep(300)

      # Should show trade analysis results
      assert render(recommendations_live) =~ "Trade Recommendation"
      assert has_element?(recommendations_live, "[data-testid='trade-recommendation']")
      
      # Should show recommendation (Accept/Decline/Counter)
      trade_result = render(recommendations_live)
      assert trade_result =~ "Accept" or trade_result =~ "Decline" or trade_result =~ "Counter"
      
      # Should show value analysis
      assert has_element?(recommendations_live, "[data-testid='value-analysis']")
      assert render(recommendations_live) =~ "Dynasty Value"
      assert render(recommendations_live) =~ "Immediate Value"

      # Step 9: Test Waiver Wire Suggestions  
      recommendations_live
      |> element("button", "Waiver Pickups")
      |> render_click()

      assert has_element?(recommendations_live, "[data-testid='waiver-form']")
      
      recommendations_live
      |> form("[data-testid='waiver-form']", waiver: %{
        positions: ["RB", "WR"],
        budget: "50"
      })
      |> render_submit()

      # Should show waiver recommendations
      assert render(recommendations_live) =~ "Waiver Recommendations"
      assert has_element?(recommendations_live, "[data-testid='pickup-recommendations']")
      assert has_element?(recommendations_live, "[data-testid='drop-candidates']")

      # Should show pickup priorities
      assert render(recommendations_live) =~ "Suggested Bid"
      assert render(recommendations_live) =~ "Urgency"

      # Step 10: Test Error Handling
      # Navigate back to league import and test invalid league ID
      {:ok, dashboard_live, _} = live(conn, "/")
      
      dashboard_live
      |> element("button", "Add League")
      |> render_click()

      # Submit invalid Sleeper league ID
      dashboard_live
      |> form("[data-testid='league-import-form']", league: %{sleeper_id: "invalid"})
      |> render_submit()

      # Should show error message
      assert render(dashboard_live) =~ "League not found"
      assert has_element?(dashboard_live, "[data-testid='error-message']")

      # Step 11: Test Offline Mode (when external APIs unavailable)
      # This would test the mock data fallback
      {:ok, players_live, _} = live(conn, "/players?offline=true")
      
      # Should still show players using mock data
      assert render(players_live) =~ "Players"
      assert has_element?(players_live, "[data-testid='player-list']")
      assert render(players_live) =~ "Mock Player"  # Using mock data
    end

    test "mobile responsive behavior", %{conn: conn} do
      # Test mobile viewport
      conn = conn |> put_req_header("user-agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)")
      
      {:ok, dashboard_live, html} = live(conn, "/")
      
      # Should have mobile-friendly layout
      assert html =~ "viewport"
      assert has_element?(dashboard_live, "[data-testid='mobile-menu']")
      
      # Test mobile navigation
      dashboard_live
      |> element("[data-testid='mobile-menu-toggle']")
      |> render_click()
      
      assert has_element?(dashboard_live, "[data-testid='mobile-nav-open']")
    end

    test "keyboard navigation and accessibility", %{conn: conn} do
      {:ok, players_live, html} = live(conn, "/players")
      
      # Should have proper ARIA labels
      assert html =~ "aria-label"
      assert html =~ "role="
      
      # Test keyboard navigation on player search
      players_live
      |> element("[data-testid='player-search'] input")
      |> render_keydown(%{"key" => "Enter"})
      
      # Should trigger search
      assert_patched(players_live, "/players?search=")
    end

    test "real-time updates with Phoenix channels", %{conn: conn} do
      {:ok, recommendations_live, _} = live(conn, "/recommendations")
      
      # Subscribe to recommendation updates
      Phoenix.PubSub.subscribe(FantasyManager.PubSub, "recommendations:updates")
      
      # Simulate external recommendation update
      Phoenix.PubSub.broadcast(FantasyManager.PubSub, "recommendations:updates", %{
        event: "recommendation_complete",
        recommendation_id: "test_rec_id"
      })
      
      # Should update the UI
      :timer.sleep(100)
      assert render(recommendations_live) =~ "Recommendation updated"
    end

    test "handles slow network conditions gracefully", %{conn: conn} do
      # Simulate slow API responses
      Process.put(:simulate_slow_api, true)
      
      {:ok, recommendations_live, _} = live(conn, "/recommendations")
      
      recommendations_live
      |> element("button", "Lineup Optimization")
      |> render_click()

      recommendations_live
      |> form("[data-testid='lineup-form']", lineup: %{week: "1"})
      |> render_submit()

      # Should show extended loading state
      assert render(recommendations_live) =~ "This may take a moment"
      assert has_element?(recommendations_live, "[data-testid='loading-spinner']")
      
      # Should not timeout
      :timer.sleep(2000)
      assert render(recommendations_live) =~ "Generating recommendations"
    end

    test "data persistence across page refreshes", %{conn: conn} do
      # Create league and get recommendations
      {:ok, dashboard_live, _} = live(conn, "/")
      
      dashboard_live
      |> element("button", "Add League")
      |> render_click()

      dashboard_live
      |> form("[data-testid='league-import-form']", league: %{sleeper_id: "123456789"})
      |> render_submit()

      # Navigate away and back
      {:ok, new_dashboard_live, html} = live(conn, "/")
      
      # Should remember the imported league
      assert html =~ "Test Dynasty League"
      assert has_element?(new_dashboard_live, "[data-testid='league-card']")
    end
  end

  describe "Error scenarios and edge cases" do
    test "handles external API failures gracefully", %{conn: conn} do
      # Mock Sleeper API failure
      Process.put(:mock_sleeper_failure, true)
      
      {:ok, players_live, _} = live(conn, "/players")
      
      players_live
      |> form("[data-testid='player-search']", search: %{query: "test"})
      |> render_submit()
      
      # Should show fallback UI
      assert render(players_live) =~ "Using offline data"
      assert has_element?(players_live, "[data-testid='offline-indicator']")
    end

    test "handles AI service unavailability", %{conn: conn} do
      # Mock Claude API failure
      Process.put(:mock_claude_failure, true)
      
      {:ok, recommendations_live, _} = live(conn, "/recommendations")
      
      recommendations_live
      |> form("[data-testid='team-selector']", team: %{id: MockData.sample_team_id()})
      |> render_submit()

      recommendations_live
      |> element("button", "Lineup Optimization")
      |> render_click()

      recommendations_live
      |> form("[data-testid='lineup-form']", lineup: %{week: "1"})
      |> render_submit()
      
      # Should show error message with fallback options
      assert render(recommendations_live) =~ "AI service temporarily unavailable"
      assert has_element?(recommendations_live, "[data-testid='fallback-recommendations']")
    end

    test "validates user inputs thoroughly", %{conn: conn} do
      {:ok, recommendations_live, _} = live(conn, "/recommendations")
      
      # Test invalid week selection
      recommendations_live
      |> form("[data-testid='lineup-form']", lineup: %{week: "0"})
      |> render_submit()
      
      assert render(recommendations_live) =~ "Week must be between 1 and 18"
      
      # Test invalid budget in waiver form
      recommendations_live
      |> element("button", "Waiver Pickups")
      |> render_click()

      recommendations_live
      |> form("[data-testid='waiver-form']", waiver: %{budget: "-10"})
      |> render_submit()
      
      assert render(recommendations_live) =~ "Budget must be positive"
    end
  end

  describe "Performance and optimization" do
    test "loads large player lists efficiently", %{conn: conn} do
      {:ok, players_live, _} = live(conn, "/players")
      
      # Should use virtualization or pagination for large lists
      start_time = System.monotonic_time()
      
      # Scroll to load more players
      players_live
      |> element("[data-testid='load-more']")
      |> render_click()
      
      duration = System.monotonic_time() - start_time
      
      # Should load additional players quickly
      assert duration < 500_000_000  # 500ms
      assert has_element?(players_live, "[data-testid='player-card']")
    end

    test "caches recommendations appropriately", %{conn: conn} do
      {:ok, recommendations_live, _} = live(conn, "/recommendations")
      
      # Generate initial recommendation
      recommendations_live
      |> form("[data-testid='team-selector']", team: %{id: MockData.sample_team_id()})
      |> render_submit()

      recommendations_live
      |> element("button", "Lineup Optimization")
      |> render_click()

      recommendations_live
      |> form("[data-testid='lineup-form']", lineup: %{week: "1"})
      |> render_submit()
      
      :timer.sleep(100)
      
      # Make same request again
      start_time = System.monotonic_time()
      
      recommendations_live
      |> form("[data-testid='lineup-form']", lineup: %{week: "1"})
      |> render_submit()
      
      duration = System.monotonic_time() - start_time
      
      # Cached response should be much faster
      assert duration < 100_000_000  # 100ms
      assert render(recommendations_live) =~ "Optimal Lineup"
    end
  end
end