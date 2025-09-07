how# Tasks: Sleeper Keeper/Dynasty Fantasy Football Management Assistant MVP

**Input**: Design documents from `/specs/001-build-an-application/`
**Prerequisites**: plan.md, research.md, data-model.md, contracts/, quickstart.md
**Context**: Create an MVP version that can be tested locally in the browser

## MVP Scope
Focus on core functionality for browser testing:
- Basic Phoenix web application with Ash framework
- Player management with Sleeper API integration
- Simple league and team management
- Basic AI recommendations (lineup optimization)
- Web interface for testing core features
- Mock data for offline testing

## Phase 3.1: Project Setup

- [x] **T001** Create Phoenix project structure with Ash framework
  - Path: Create `mix.exs`, `config/`, `lib/`, `test/` directories
  - Dependencies: Phoenix 1.8.1, Ash ~> 3.0, Ash.PostgreSQL, Ash.Phoenix
  - Command: `mix phx.new fantasy_manager --umbrella=false --ecto --html`

- [x] **T002** Configure dependencies and basic Phoenix setup
  - Path: Update `mix.exs` with all required dependencies from plan.md
  - Add Ash framework, Ash.ai, Tesla, Cachex, LangChain dependencies
  - Configure basic Phoenix generators and routes

- [x] **T003** [P] Setup development configuration files
  - Path: `config/dev.exs`, `config/config.exs`, `config/test.exs`
  - Include database config, cache config, external API settings
  - Add environment variable templates

- [x] **T004** [P] Setup database and migrations structure
  - Path: `priv/repo/migrations/`
  - Create PostgreSQL database configuration
  - Setup Ecto repo with Ash extensions

## Phase 3.2: Tests First (TDD) ⚠️ MUST COMPLETE BEFORE 3.3

**CRITICAL: These tests MUST be written and MUST FAIL before ANY implementation**

- [x] **T005** [P] Contract test for GET /api/v1/players
  - Path: `test/fantasy_manager_web/controllers/players_api_test.exs`
  - Test JSON:API format, filtering, pagination from players-api.yaml
  - Must fail initially (no implementation exists)

- [x] **T006** [P] Contract test for POST /api/v1/lineups/optimize
  - Path: `test/fantasy_manager_web/controllers/recommendations_api_test.exs`
  - Test lineup optimization endpoint from recommendations-api.yaml
  - Must fail initially (no implementation exists)

- [x] **T007** [P] Contract test for GET /api/v1/leagues/{id}
  - Path: `test/fantasy_manager_web/controllers/leagues_api_test.exs`
  - Test league details endpoint from leagues-api.yaml
  - Must fail initially (no implementation exists)

- [x] **T008** [P] Integration test for Sleeper API client
  - Path: `test/integration/sleeper_client_test.exs`
  - Test external API connection, caching, error handling
  - Use mock responses for predictable testing

- [x] **T009** [P] Integration test for AI recommendation flow
  - Path: `test/integration/ai_recommendations_test.exs`
  - Test Claude API integration, tool calling, response formatting
  - Mock LangChain responses for deterministic tests

- [x] **T010** [P] Browser integration test for core user journey
  - Path: `test/fantasy_manager_web/integration/user_journey_test.exs`
  - Test: Create league → View players → Get recommendations
  - Use Phoenix LiveView testing capabilities

## Phase 3.3: Core Domain Models (ONLY after tests are failing)

- [x] **T011** [P] Player Ash resource
  - Path: `lib/fantasy_manager/fantasy/player.ex`
  - Implement Player resource from data-model.md with Sleeper API integration
  - Include calculations, validations, and AI vectorization setup

- [x] **T012** [P] League Ash resource  
  - Path: `lib/fantasy_manager/fantasy/league.ex`
  - Implement League resource with keeper/dynasty settings
  - Include team relationships and validation rules

- [x] **T013** [P] FantasyTeam Ash resource
  - Path: `lib/fantasy_manager/fantasy/fantasy_team.ex`
  - Implement team resource with roster management
  - Include competitive window and roster relationships

- [x] **T014** [P] WeeklyProjection Ash resource
  - Path: `lib/fantasy_manager/fantasy/weekly_projection.ex`
  - Implement AI projections resource for recommendations
  - Include confidence scoring and model versioning

- [x] **T015** Create database migrations for core entities
  - Path: `priv/repo/migrations/001_create_core_tables.exs`
  - Migrate Player, League, FantasyTeam, WeeklyProjection tables
  - Include indexes and constraints from data-model.md

## Phase 3.4: External API Integration

- [x] **T016** [P] Sleeper API client with caching
  - Path: `lib/fantasy_manager/external/sleeper_client.ex`
  - Implement Tesla client with Cachex integration
  - Handle rate limiting, error responses, data transformation

- [x] **T017** [P] Sleeper custom data layer for Ash
  - Path: `lib/fantasy_manager/external/sleeper_data_layer.ex`
  - Implement Ash.DataLayer behavior for external API
  - Include caching strategy and query optimization

- [x] **T018** [P] Mock data generators for offline testing
  - Path: `lib/fantasy_manager/test_support/mock_data.ex`
  - Generate realistic player, league, and team data
  - Support browser testing without external API dependencies

## Phase 3.5: AI Integration

- [x] **T019** [P] AI recommendation engine with Claude integration
  - Path: `lib/fantasy_manager/ai/recommendation_engine.ex`
  - Implement LangChain integration for lineup recommendations
  - Include tool calling and structured output parsing

- [x] **T020** [P] Ash.ai tools for fantasy data access
  - Path: `lib/fantasy_manager/ai/fantasy_tools.ex`
  - Implement tools for AI to access player stats, matchups, projections
  - Enable AI to query roster data and league settings

- [x] **T021** Claude API configuration and error handling
  - Path: `lib/fantasy_manager/ai/claude_config.ex`
  - Configure Claude API client with proper error handling
  - Include fallback responses when AI unavailable

## Phase 3.6: Web Interface and APIs

- [ ] **T022** JSON:API endpoints for players
  - Path: `lib/fantasy_manager_web/controllers/api/players_controller.ex`
  - Implement GET /api/v1/players with filtering and search
  - Connect to Player Ash resource with AshJsonApi

- [ ] **T023** JSON:API endpoints for leagues
  - Path: `lib/fantasy_manager_web/controllers/api/leagues_controller.ex` 
  - Implement league CRUD and Sleeper sync endpoints
  - Include team relationships and roster data

- [ ] **T024** AI recommendation endpoints
  - Path: `lib/fantasy_manager_web/controllers/api/recommendations_controller.ex`
  - Implement POST /api/v1/lineups/optimize and other AI endpoints
  - Connect to AI recommendation engine

- [ ] **T025** [P] Basic web interface for testing
  - Path: `lib/fantasy_manager_web/live/dashboard_live.ex`
  - Create simple Phoenix LiveView for interacting with API
  - Include forms for league setup, player search, recommendation requests

- [ ] **T026** [P] Web interface for AI recommendations
  - Path: `lib/fantasy_manager_web/live/recommendations_live.ex`
  - Create interface for lineup optimization and trade analysis
  - Display AI reasoning and confidence scores

## Phase 3.7: Integration and Polish

- [ ] **T027** Configure router and API versioning
  - Path: `lib/fantasy_manager_web/router.ex`
  - Setup API routes, web routes, and LiveView socket
  - Include proper error handling and request logging

- [ ] **T028** Application supervision and cache setup
  - Path: `lib/fantasy_manager/application.ex`
  - Configure Cachex, Oban (if needed), and other supervised processes
  - Include health check endpoints

- [ ] **T029** [P] Seed data for local testing
  - Path: `priv/repo/seeds.exs`
  - Create sample leagues, teams, players for browser testing
  - Include mock Sleeper data for offline development

- [ ] **T030** [P] Development configuration and README
  - Path: `README.md`, `config/dev.exs.template`
  - Document MVP setup process for browser testing
  - Include environment variables and API key setup

- [ ] **T031** Browser testing validation
  - Path: Run quickstart.md user journeys in browser
  - Verify: League creation, player search, recommendations work
  - Test both with and without external API access

## Dependencies

**Sequential Dependencies:**
- T001 → T002 → T003, T004 (project setup sequence)
- T005-T010 before T011-T031 (TDD: tests before implementation)
- T011-T015 → T016-T018 → T019-T021 → T022-T026 (models → APIs → AI → endpoints)
- T027-T028 before T031 (configuration before validation)

**Parallel Execution Groups:**
```bash
# Group 1: Initial setup (after T001-T002)
Task: "Setup development configuration files in config/"
Task: "Setup database and migrations structure in priv/repo/"

# Group 2: Contract tests (must all fail before implementation)
Task: "Contract test GET /api/v1/players in test/controllers/players_api_test.exs"
Task: "Contract test POST /api/v1/lineups/optimize in test/controllers/recommendations_api_test.exs" 
Task: "Contract test GET /api/v1/leagues/{id} in test/controllers/leagues_api_test.exs"
Task: "Integration test Sleeper API client in test/integration/sleeper_client_test.exs"
Task: "Integration test AI recommendation flow in test/integration/ai_recommendations_test.exs"

# Group 3: Core models (after tests are failing)
Task: "Create Player Ash resource in lib/fantasy_manager/fantasy/player.ex"
Task: "Create League Ash resource in lib/fantasy_manager/fantasy/league.ex"
Task: "Create FantasyTeam Ash resource in lib/fantasy_manager/fantasy/fantasy_team.ex"
Task: "Create WeeklyProjection Ash resource in lib/fantasy_manager/fantasy/weekly_projection.ex"

# Group 4: External integrations
Task: "Implement Sleeper API client with caching in lib/external/sleeper_client.ex"
Task: "Implement Sleeper custom data layer in lib/external/sleeper_data_layer.ex"
Task: "Create mock data generators in lib/test_support/mock_data.ex"

# Group 5: AI components
Task: "Implement AI recommendation engine in lib/ai/recommendation_engine.ex"
Task: "Implement Ash.ai fantasy tools in lib/ai/fantasy_tools.ex"

# Group 6: Web interface components  
Task: "Create basic web interface for testing in lib/web/live/dashboard_live.ex"
Task: "Create AI recommendations interface in lib/web/live/recommendations_live.ex"
Task: "Create seed data for testing in priv/repo/seeds.exs"
Task: "Create README and dev config template"
```

## MVP Success Criteria

**Browser Testing Checklist:**
1. ✅ Phoenix server starts at http://localhost:4000
2. ✅ Can create/sync a league from Sleeper ID
3. ✅ Can search and view player information
4. ✅ Can generate lineup recommendations with AI reasoning
5. ✅ Web interface displays data clearly and handles errors
6. ✅ Works offline with mock data when external APIs unavailable
7. ✅ All contract tests pass
8. ✅ All integration tests pass

**Technical Validation:**
- Response times < 2s for AI operations, < 500ms for data queries
- Proper error handling for external API failures
- Clean separation between Ash resources and web layer
- Caching working correctly (check logs)
- AI integration returning structured responses

## Notes for Implementation

- **TDD Enforcement**: All tests T005-T010 must fail before implementing T011+
- **MVP Focus**: Skip complex features (trades, keeper optimization) for initial version
- **Browser First**: Prioritize web interface over CLI tools for testing
- **Offline Capable**: Include mock data so testing doesn't depend on external APIs
- **Error Handling**: Graceful degradation when Sleeper API or Claude unavailable
- **Performance**: Cache aggressively, especially for player data that changes infrequently

This MVP provides a testable foundation with core functionality accessible through a browser, setting up the architecture for future enhancements.