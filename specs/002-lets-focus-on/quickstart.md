# Quickstart: AI-Powered Free Agent Pickup Recommendations

**Feature**: 002-lets-focus-on  
**Date**: 2025-09-08  
**Prerequisites**: Fantasy Manager application running, user has a fantasy team in the system

## Overview

This quickstart guide walks through the complete user journey for getting AI-powered free agent pickup recommendations. It demonstrates the core feature functionality from team selection through recommendation generation and action tracking.

## User Journey Test Scenarios

### Scenario 1: Basic Recommendation Request
**Story**: User wants pickup recommendations for their underperforming team

**Steps**:
1. **Navigate to Recommendations Page**
   ```
   GET /recommendations
   → Should display team selection interface
   → Should show current week and available teams
   ```

2. **Select Fantasy Team**
   ```
   User clicks on "Team Name" or dropdown selection
   → Should highlight selected team
   → Should display "Get Pickup Recommendations" button
   → Should show basic team info (record, current roster preview)
   ```

3. **Request AI Recommendations**
   ```
   POST /api/v1/teams/{team_id}/recommendations
   Headers: Authorization: Bearer {jwt_token}
   Body: {
     "week": 8,
     "season": 2024,
     "limit": 10
   }
   
   → Should return HTTP 200
   → Should include recommendations array
   → Should include roster_analysis object
   → Should show loading state during AI processing (2-3 seconds)
   ```

4. **Display Recommendations**
   ```
   Response should include:
   - 5-10 pickup recommendations
   - Priority scores (1.0-10.0)
   - AI reasoning for each pickup
   - Drop candidates for each pickup
   - Roster weakness analysis
   - Confidence levels
   
   UI should display:
   - Cards/list of recommended players
   - Player photos and team logos
   - Clear reasoning text
   - Action buttons (Track, Dismiss)
   ```

5. **Interact with Recommendations**
   ```
   User clicks "Track Recommendation" or "Dismiss"
   
   PATCH /api/v1/teams/{team_id}/recommendations/{rec_id}/status
   Body: {"status": "executed"} or {"status": "dismissed"}
   
   → Should update recommendation status
   → Should provide user feedback
   → Should update UI state
   ```

**Expected Results**:
- User receives personalized pickup suggestions in 2-3 seconds
- Recommendations include clear reasoning and confidence levels
- User can easily act on recommendations
- System tracks user actions for improvement

### Scenario 2: Position-Specific Recommendations
**Story**: User's running back starter got injured, needs RB replacements

**Steps**:
1. **Request Position-Filtered Recommendations**
   ```
   GET /api/v1/teams/{team_id}/recommendations?position_filter=RB&limit=5
   
   → Should return only RB recommendations
   → Should prioritize available RBs
   → Should explain urgency due to positional need
   ```

2. **Review Trending RB Options**
   ```
   Recommendations should include:
   - Handcuff players (same NFL team as injured player)
   - Trending waiver wire RBs
   - Emerging players with opportunity
   - Clear fantasy point projections
   ```

3. **Compare Drop Candidates**
   ```
   Each RB recommendation should suggest:
   - Specific player to drop
   - Reasoning for drop (schedule, performance trend)
   - Net points gain estimate
   ```

**Expected Results**:
- Targeted RB recommendations address specific positional need
- Handcuff and opportunity-based suggestions prioritized
- Clear drop/add decision guidance provided

### Scenario 3: Trending Players Discovery
**Story**: User wants to see what players are hot on the waiver wire

**Steps**:
1. **View Trending Players Data**
   ```
   GET /api/v1/trending/players?type=add&lookback_hours=24&limit=20
   
   → Should return trending adds from last 24 hours
   → Should include player info and trend velocity
   → Should rank by activity level
   ```

2. **Cross-Reference Team Needs**
   ```
   System should:
   - Highlight trending players at weak positions
   - Show availability in user's league
   - Calculate fit score for user's team
   ```

3. **Generate Smart Recommendations**
   ```
   AI should:
   - Consider trending momentum + team fit
   - Factor in upcoming matchups
   - Provide pickup timing advice (waiver vs FA)
   ```

**Expected Results**:
- Discovery of emerging players before they become highly owned
- Smart filtering based on team needs
- Timing guidance for optimal pickup strategy

## Integration Test Scenarios

### API Contract Validation

**Test 1: Recommendations API Schema**
```bash
# Test valid recommendation request
curl -X GET "http://localhost:4000/api/v1/teams/123e4567-e89b-12d3-a456-426614174000/recommendations" \
  -H "Authorization: Bearer {jwt_token}" \
  -H "Content-Type: application/json"

# Expected: 200 response matching recommendations-api.yaml schema
```

**Test 2: Parameter Validation**
```bash
# Test invalid week parameter
curl -X GET "http://localhost:4000/api/v1/teams/123e4567-e89b-12d3-a456-426614174000/recommendations?week=25" \
  -H "Authorization: Bearer {jwt_token}"

# Expected: 400 error with validation message
```

**Test 3: Trending Data Integration**
```bash
# Test trending players endpoint
curl -X GET "http://localhost:4000/api/v1/trending/players?type=add&limit=10" \
  -H "Authorization: Bearer {jwt_token}"

# Expected: 200 response with trending players data
```

### Data Flow Validation

**Test 4: End-to-End Recommendation Pipeline**
```elixir
# Integration test covering complete flow
defmodule RecommendationPipelineTest do
  use FantasyManagerWeb.ConnCase
  
  test "complete recommendation pipeline", %{conn: conn} do
    # Setup: Create team with known weaknesses
    team = create_team_with_weak_rb_position()
    
    # Step 1: Request recommendations
    conn = get(conn, "/api/v1/teams/#{team.id}/recommendations")
    
    assert %{
      "recommendations" => recommendations,
      "roster_analysis" => %{"weakness_scores" => %{"RB" => rb_score}}
    } = json_response(conn, 200)
    
    # Verify RB weakness detected
    assert rb_score > 7.0
    
    # Verify RB recommendations provided
    rb_recommendations = Enum.filter(recommendations, fn r -> 
      r["player"]["position"] == "RB" 
    end)
    assert length(rb_recommendations) >= 2
    
    # Step 2: Update recommendation status
    rec_id = List.first(recommendations)["id"]
    conn = patch(conn, "/api/v1/teams/#{team.id}/recommendations/#{rec_id}/status", 
      %{"status" => "executed"})
    
    assert json_response(conn, 200)
  end
end
```

### Performance Validation

**Test 5: Response Time Requirements**
```elixir
test "recommendation generation performance" do
  team = create_test_team()
  
  {time_micro, _result} = :timer.tc(fn ->
    RecommendationEngine.get_waiver_recommendations(team.id, 8, 2024)
  end)
  
  # Should complete within 5 seconds
  assert time_micro < 5_000_000
end
```

**Test 6: Cache Effectiveness**
```elixir
test "caching reduces API calls" do
  team = create_test_team()
  
  # First request (cache miss)
  RecommendationEngine.get_waiver_recommendations(team.id, 8, 2024)
  initial_api_calls = get_sleeper_api_call_count()
  
  # Second request (cache hit)
  RecommendationEngine.get_waiver_recommendations(team.id, 8, 2024)
  cached_api_calls = get_sleeper_api_call_count()
  
  # Should not make additional API calls
  assert cached_api_calls == initial_api_calls
end
```

## Manual Testing Checklist

### UI/UX Validation

- [ ] Recommendations page loads within 2 seconds
- [ ] Team selection interface is intuitive  
- [ ] Loading states shown during AI processing
- [ ] Recommendations display clearly with player photos
- [ ] Reasoning text is human-readable and helpful
- [ ] Drop candidate suggestions make sense
- [ ] Action buttons (Track/Dismiss) work correctly
- [ ] Mobile responsive design functions properly

### Data Accuracy Validation

- [ ] Player information matches Sleeper API data
- [ ] Trending data reflects recent waiver activity
- [ ] Team roster analysis identifies actual weaknesses
- [ ] AI recommendations address identified needs
- [ ] Drop candidates are logical roster cuts
- [ ] Confidence levels align with recommendation quality

### Error Handling Validation

- [ ] Graceful handling when Sleeper API is unavailable
- [ ] Fallback responses when AI service fails
- [ ] Clear error messages for invalid requests
- [ ] Rate limiting prevents API abuse
- [ ] Timeout handling for slow AI responses

## Success Criteria

### Functional Success
- ✅ User can select their team and request recommendations
- ✅ AI generates relevant pickup suggestions within 5 seconds
- ✅ Recommendations include reasoning and confidence levels
- ✅ User can track recommendation outcomes
- ✅ Position-specific filtering works correctly

### Performance Success  
- ✅ API responses complete within 3 seconds (95th percentile)
- ✅ Caching reduces external API calls by 90%+
- ✅ Concurrent user recommendations don't impact response times
- ✅ Weekly data sync completes within 10 minutes

### Quality Success
- ✅ AI recommendations have >70% user satisfaction rating
- ✅ Trending data updates within 15 minutes of Sleeper changes
- ✅ Drop candidate suggestions are logical and helpful
- ✅ Error scenarios handled gracefully without user confusion

## Production Readiness Checklist

### Monitoring & Observability
- [ ] API endpoint metrics configured
- [ ] AI service latency monitoring
- [ ] Cache hit rate monitoring  
- [ ] Error rate alerting
- [ ] User action tracking for recommendation quality

### Security & Performance
- [ ] JWT authentication enforced
- [ ] Rate limiting configured appropriately
- [ ] Input validation comprehensive
- [ ] Cache TTL values optimized
- [ ] Database indexes created for query performance

### Operational Readiness
- [ ] Weekly data sync automation configured
- [ ] Manual sync procedures documented
- [ ] Fallback responses tested and acceptable
- [ ] Support team trained on feature functionality
- [ ] User documentation published

---

## Next Steps

After completing this quickstart validation:

1. **Performance Tuning**: Optimize query patterns and cache strategies
2. **User Feedback Integration**: Add rating system for recommendation quality
3. **Advanced Features**: Multi-week projections, trade impact analysis
4. **Mobile Optimization**: Ensure excellent mobile user experience
5. **Analytics Dashboard**: Admin view of recommendation effectiveness

This quickstart guide serves as both user acceptance criteria and integration test specification for the AI-powered free agent pickup recommendations feature.