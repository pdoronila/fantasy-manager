# Quickstart Guide: Fantasy Football Management System

**Phase 1 Output** | **Date**: 2025-09-07

## Prerequisites

### System Requirements
- Elixir 1.15+ with OTP 25+
- Phoenix 1.8.1
- PostgreSQL 14+
- Node.js 18+ (for frontend assets)
- Claude Code CLI installed

### External Services
- Sleeper API access (public endpoints)
- Claude API key (for AI features)
- Optional: API Sports NFL API key

## Quick Setup

### 1. Clone and Setup Project
```bash
# Clone repository
git clone <repository-url>
cd fantasy_manager

# Install dependencies
mix deps.get
mix deps.compile

# Setup database
mix ecto.setup

# Install frontend dependencies (if applicable)
cd assets && npm install && cd ..
```

### 2. Configuration
```bash
# Copy environment template
cp config/dev.exs.template config/dev.exs

# Configure required environment variables
export CLAUDE_API_KEY="your-claude-api-key"
export SLEEPER_API_BASE_URL="https://api.sleeper.com/v1"
export DATABASE_URL="ecto://username:password@localhost/fantasy_manager_dev"
```

### 3. Start Development Server
```bash
# Start Phoenix server
mix phx.server

# Or start with IEx for debugging
iex -S mix phx.server
```

Server will start at `http://localhost:4000`

## Core User Journeys

### Journey 1: Setup Fantasy League

**Goal**: Connect and sync a Sleeper league

```bash
# 1. Create league from Sleeper ID
curl -X POST http://localhost:4000/api/v1/leagues \
  -H "Content-Type: application/vnd.api+json" \
  -d '{
    "data": {
      "type": "league",
      "attributes": {
        "sleeper_id": "987654321",
        "sync_historical": true
      }
    }
  }'

# Expected response: League created with teams and basic roster data
```

**Validation Steps**:
1. ✅ League appears in GET /api/v1/leagues
2. ✅ Teams are created and linked to league
3. ✅ Current rosters are populated
4. ✅ Basic player data is synced

### Journey 2: Get Lineup Recommendations

**Goal**: AI-powered weekly lineup optimization

```bash
# 1. Get team ID from leagues endpoint
TEAM_ID=$(curl http://localhost:4000/api/v1/leagues/{league_id}?include=teams | jq -r '.included[0].id')

# 2. Request lineup optimization for current week
curl -X POST http://localhost:4000/api/v1/lineups/optimize \
  -H "Content-Type: application/json" \
  -d '{
    "fantasy_team_id": "'$TEAM_ID'",
    "week": 1,
    "season": 2024,
    "risk_tolerance": "Balanced"
  }'

# Expected response: Optimized lineup with projections and reasoning
```

**Validation Steps**:
1. ✅ Returns valid lineup for all required positions
2. ✅ Includes projected points for each player
3. ✅ Provides AI reasoning for recommendations
4. ✅ Confidence scores are between 0-1

### Journey 3: Analyze Trade Proposal

**Goal**: Evaluate incoming trade offers

```bash
# 1. Simulate incoming trade proposal
curl -X POST http://localhost:4000/api/v1/trades/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "fantasy_team_id": "'$TEAM_ID'",
    "offered_players": ["player-uuid-1"],
    "requested_players": ["player-uuid-2", "player-uuid-3"],
    "competitive_window": "Contending"
  }'

# Expected response: Trade analysis with recommendation
```

**Validation Steps**:
1. ✅ Returns Accept/Decline/Counter recommendation
2. ✅ Provides value analysis (immediate vs dynasty)
3. ✅ Includes player-by-player breakdown
4. ✅ Suggests counter-offers if applicable

### Journey 4: Dynasty Planning

**Goal**: Long-term roster construction guidance

```bash
# 1. Generate dynasty transition plan
curl -X POST http://localhost:4000/api/v1/dynasty/plan \
  -H "Content-Type: application/json" \
  -d '{
    "fantasy_team_id": "'$TEAM_ID'",
    "transition_timeline": "Next_Season",
    "current_strategy": "Neutral",
    "risk_tolerance": "Balanced"
  }'

# Expected response: Multi-phase dynasty plan
```

**Validation Steps**:
1. ✅ Returns phased transition strategy
2. ✅ Identifies trade targets and assets to move
3. ✅ Provides draft strategy recommendations
4. ✅ Sets measurable success metrics

### Journey 5: Keeper Selection

**Goal**: Optimize keeper selections for next season

```bash
# 1. Get keeper optimization recommendations
curl -X POST http://localhost:4000/api/v1/keepers/optimize \
  -H "Content-Type: application/json" \
  -d '{
    "fantasy_team_id": "'$TEAM_ID'",
    "keeper_deadline": "2024-08-15",
    "max_keepers": 3,
    "competitive_window": "Contending"
  }'

# Expected response: Optimal keeper combinations
```

**Validation Steps**:
1. ✅ Returns recommended keeper selections
2. ✅ Calculates value-over-cost for each option
3. ✅ Considers dynasty potential
4. ✅ Provides alternative scenarios

## CLI Integration Tests

### Test Sleeper API Connection
```bash
# Test basic API connectivity
mix run -e "FantasyManager.External.SleeperClient.get_all_players() |> IO.inspect()"

# Should return map of all NFL players
```

### Test AI Integration
```bash
# Test Claude API connection
mix run -e "FantasyManager.AI.RecommendationEngine.test_connection() |> IO.inspect()"

# Should return successful connection status
```

### Test Database Operations
```bash
# Run basic CRUD tests
mix test test/fantasy_manager/fantasy_test.exs

# Run integration tests
mix test test/integration/
```

## Troubleshooting

### Common Issues

**Issue**: Sleeper API rate limit errors
**Solution**: Check caching configuration in `config/dev.exs`
```elixir
config :fantasy_manager, :sleeper_cache,
  ttl: 60 * 60 * 24,  # 24 hours
  max_size: 10_000
```

**Issue**: Claude API connection failures
**Solution**: Verify API key and test connection
```bash
export CLAUDE_API_KEY="your-api-key"
mix run -e "FantasyManager.AI.test_claude_connection()"
```

**Issue**: Database connection errors
**Solution**: Check PostgreSQL service and credentials
```bash
# Test database connection
mix ecto.migrate
psql $DATABASE_URL -c "SELECT version();"
```

**Issue**: Missing player data
**Solution**: Force sync from Sleeper API
```bash
# Sync all players
mix run -e "FantasyManager.Tasks.SyncPlayers.run()"

# Sync specific league
mix run -e "FantasyManager.Tasks.SyncLeague.run(\"sleeper_league_id\")"
```

## Performance Validation

### Response Time Expectations
- Player queries: < 100ms
- Lineup optimization: < 2s
- Trade analysis: < 3s
- Dynasty planning: < 5s
- Free agent analysis: < 1s

### Load Testing
```bash
# Install wrk for load testing
# Test concurrent lineup requests
wrk -t12 -c400 -d30s --script=test/load/lineup_test.lua http://localhost:4000

# Expected: >90% of requests under 2s response time
```

### Memory Usage
```bash
# Monitor memory usage during operation
:observer.start()  # In IEx session

# Expected: < 200MB RAM usage under normal load
```

## Development Workflow

### Adding New Features
1. Write failing tests first (TDD approach)
2. Implement Ash resources and actions
3. Add API endpoints via JSON:API
4. Update OpenAPI documentation
5. Add integration tests
6. Test with real external APIs

### Testing Strategy
```bash
# Unit tests (fast, isolated)
mix test test/fantasy_manager/

# Integration tests (slower, real APIs)
mix test test/integration/ --include integration

# Contract tests (API compatibility)
mix test test/contracts/

# End-to-end tests (full user journeys)
mix test test/e2e/
```

### Code Quality
```bash
# Format code
mix format

# Run static analysis
mix credo

# Type checking (if using Dialyzer)
mix dialyzer

# Security audit
mix deps.audit
```

## Production Deployment

### Environment Configuration
```bash
# Required production environment variables
export SECRET_KEY_BASE="generated-secret-key"
export DATABASE_URL="production-database-url"
export CLAUDE_API_KEY="production-claude-key"
export SLEEPER_API_RATE_LIMIT="60"  # requests per minute
```

### Health Checks
```bash
# Application health endpoint
curl http://localhost:4000/health

# Database connectivity
curl http://localhost:4000/health/db

# External API connectivity
curl http://localhost:4000/health/apis
```

### Monitoring
- Application metrics via Phoenix LiveDashboard
- Custom business metrics (recommendation accuracy, API response times)
- Error tracking and alerting
- Performance monitoring for AI operations

This quickstart guide provides a comprehensive foundation for developing, testing, and deploying the fantasy football management system. Follow the user journeys to validate core functionality and use the troubleshooting section to resolve common issues during development.