# Tasks: AI-Powered Free Agent Pickup Recommendations

**Input**: Design documents from `/specs/002-lets-focus-on/`
**Prerequisites**: plan.md, research.md, data-model.md, contracts/, quickstart.md

## Execution Flow (main)
```
1. Load plan.md from feature directory
   → Tech stack: Elixir 1.15+ with Phoenix v1.8.1, Ash Framework
   → Libraries: Ash.ai, Tesla/Finch, Cachex, PostgreSQL
   → Structure: Phoenix web application with backend and LiveView frontend
2. Load design documents:
   → data-model.md: TrendingPlayerData, WaiverRecommendation entities
   → contracts/: recommendations-api.yaml, trending-api.yaml
   → quickstart.md: 3 user journey scenarios with integration tests
3. Generate tasks by category:
   → Setup: database migrations, Ash resources
   → Tests: API contract tests, integration tests for user journeys
   → Core: SleeperClient extension, AI recommendation engine, controllers
   → Integration: caching, background jobs, LiveView components
   → Polish: performance tests, error handling, documentation
4. Apply task rules:
   → Database/model tasks marked [P] (independent tables/resources)
   → API contract tests marked [P] (different endpoints)
   → Integration tests marked [P] (independent scenarios)
   → Controller implementations sequential (shared routing)
5. Number tasks T001-T034
6. TDD ordering: All tests before any implementation
7. Parallel execution examples provided
```

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- All file paths are absolute from repository root

---

## Phase 3.1: Setup & Database
- [x] **T001** [P] Create database migration for trending_player_data table in `priv/repo/migrations/002_create_trending_player_data.exs`
- [x] **T002** [P] Create database migration for waiver_recommendations table in `priv/repo/migrations/003_create_waiver_recommendations.exs`
- [x] **T003** Run database migrations to create new tables

## Phase 3.2: Tests First (TDD) ⚠️ MUST COMPLETE BEFORE 3.3
**CRITICAL: These tests MUST be written and MUST FAIL before ANY implementation**

### Contract Tests [P] - Different endpoints, can run in parallel
- [x] **T004** [P] Contract test GET /api/v1/teams/{team_id}/recommendations in `test/fantasy_manager_web/controllers/recommendations_api_test.exs`
- [x] **T005** [P] Contract test PATCH /api/v1/teams/{team_id}/recommendations/{recommendation_id}/status in `test/fantasy_manager_web/controllers/recommendations_api_test.exs`
- [x] **T006** [P] Contract test GET /api/v1/trending/players in `test/fantasy_manager_web/controllers/trending_api_test.exs`
- [x] **T007** [P] Contract test GET /api/v1/trending/players/{player_id}/history in `test/fantasy_manager_web/controllers/trending_api_test.exs`
- [x] **T008** [P] Contract test POST /api/v1/trending/sync in `test/fantasy_manager_web/controllers/trending_api_test.exs`

### Integration Tests [P] - Different scenarios, can run in parallel
- [x] **T009** [P] Integration test basic recommendation request in `test/integration/recommendation_flow_test.exs`
- [x] **T010** [P] Integration test position-specific recommendations in `test/integration/position_filter_test.exs`
- [x] **T011** [P] Integration test trending players discovery in `test/integration/trending_discovery_test.exs`

### Core Service Tests [P] - Different modules, can run in parallel
- [x] **T012** [P] Unit tests for TrendingPlayerData Ash resource in `test/fantasy_manager/fantasy/trending_player_data_test.exs`
- [x] **T013** [P] Unit tests for WaiverRecommendation Ash resource in `test/fantasy_manager/fantasy/waiver_recommendation_test.exs`
- [x] **T014** [P] Unit tests for SleeperClient.get_trending_players in `test/integration/sleeper_client_test.exs`

## Phase 3.3: Core Implementation (ONLY after tests are failing)

### Database Resources [P] - Independent Ash resources
- [x] **T015** [P] Create TrendingPlayerData Ash resource in `lib/fantasy_manager/fantasy/trending_player_data.ex`
- [x] **T016** [P] Create WaiverRecommendation Ash resource in `lib/fantasy_manager/fantasy/waiver_recommendation.ex`

### External API Integration
- [x] **T017** Add get_trending_players function to SleeperClient in `lib/fantasy_manager/external/sleeper_client.ex`
- [x] **T018** Add trending data caching layer with 15-minute TTL in `lib/fantasy_manager/external/sleeper_client.ex`

### AI Recommendation Engine
- [x] **T019** Create waiver-specific AI tools in `lib/fantasy_manager/ai/fantasy_tools.ex`
- [x] **T020** Extend RecommendationEngine.get_waiver_recommendations in `lib/fantasy_manager/ai/recommendation_engine.ex`
- [x] **T021** Add roster analysis service for positional weakness detection in `lib/fantasy_manager/ai/recommendation_engine.ex`
- [x] **T022** Create waiver pickup prompt builder in `lib/fantasy_manager/ai/recommendation_engine.ex`

### API Controllers
- [x] **T023** Create RecommendationsController for recommendations API in `lib/fantasy_manager_web/controllers/api/recommendations_controller.ex`
- [x] **T024** Create TrendingController for trending players API in `lib/fantasy_manager_web/controllers/api/trending_controller.ex`
- [x] **T025** Add API routes for recommendations and trending endpoints in `lib/fantasy_manager_web/router.ex`

## Phase 3.4: Frontend Integration
- [x] **T026** Create recommendations LiveView page in `lib/fantasy_manager_web/live/recommendations_live.ex`
- [x] **T027** Add recommendation cards component in `lib/fantasy_manager_web/components/recommendation_components.ex`
- [x] **T028** Add team selection interface in `lib/fantasy_manager_web/live/recommendations_live.ex`

## Phase 3.5: Background Jobs & Automation
- [ ] **T029** [P] Create weekly player data sync job in `lib/fantasy_manager/jobs/weekly_sync_job.ex`
- [ ] **T030** [P] Add trending data cleanup job for expired records in `lib/fantasy_manager/jobs/cleanup_job.ex`

## Phase 3.6: Polish & Performance
### Performance & Error Handling [P] - Independent optimizations
- [ ] **T031** [P] Add comprehensive error handling for AI service failures in `lib/fantasy_manager/ai/recommendation_engine.ex`
- [ ] **T032** [P] Add rate limiting for recommendation API endpoints in `lib/fantasy_manager_web/controllers/api/recommendations_controller.ex`
- [ ] **T033** [P] Performance test: recommendation generation under 5 seconds in `test/performance/recommendation_performance_test.exs`

### Final Integration
- [ ] **T034** Run quickstart.md scenarios end-to-end validation

---

## Dependencies

**Setup Phase (T001-T003)**:
- T003 requires T001, T002 (migrations before running them)

**Tests First (T004-T014)**:
- All parallel - different files, no dependencies
- Must ALL be written and failing before Phase 3.3

**Core Implementation (T015-T025)**:
- T017-T018 can start after T014 passes (SleeperClient tests)
- T019-T022 can start after T012-T013 pass (resource tests)
- T023-T025 require T015-T022 complete (controllers need resources and services)

**Frontend (T026-T028)**:
- T026-T028 require T023-T025 (LiveView needs API endpoints)

**Jobs (T029-T030)**:
- T029-T030 can start after T017 (sync job needs SleeperClient extension)

**Polish (T031-T034)**:
- T031-T033 can run in parallel after core implementation
- T034 requires all other tasks complete

## Parallel Execution Examples

### Phase 3.1 - Database Setup [P]
```bash
# Launch T001-T002 together (different migration files):
Task: "Create database migration for trending_player_data table in priv/repo/migrations/002_create_trending_player_data.exs"
Task: "Create database migration for waiver_recommendations table in priv/repo/migrations/003_create_waiver_recommendations.exs"
```

### Phase 3.2 - Contract Tests [P]
```bash
# Launch T004-T008 together (different API endpoints):
Task: "Contract test GET /api/v1/teams/{team_id}/recommendations in test/fantasy_manager_web/controllers/recommendations_api_test.exs"
Task: "Contract test GET /api/v1/trending/players in test/fantasy_manager_web/controllers/trending_api_test.exs"
Task: "Contract test POST /api/v1/trending/sync in test/fantasy_manager_web/controllers/trending_api_test.exs"
```

### Phase 3.2 - Integration Tests [P]
```bash
# Launch T009-T011 together (different test scenarios):
Task: "Integration test basic recommendation request in test/integration/recommendation_flow_test.exs"
Task: "Integration test position-specific recommendations in test/integration/position_filter_test.exs"
Task: "Integration test trending players discovery in test/integration/trending_discovery_test.exs"
```

### Phase 3.3 - Core Resources [P]
```bash
# Launch T015-T016 together (independent Ash resources):
Task: "Create TrendingPlayerData Ash resource in lib/fantasy_manager/fantasy/trending_player_data.ex"
Task: "Create WaiverRecommendation Ash resource in lib/fantasy_manager/fantasy/waiver_recommendation.ex"
```

### Phase 3.6 - Polish Tasks [P]
```bash
# Launch T031-T033 together (independent improvements):
Task: "Add comprehensive error handling for AI service failures in lib/fantasy_manager/ai/recommendation_engine.ex"
Task: "Add rate limiting for recommendation API endpoints in lib/fantasy_manager_web/controllers/api/recommendations_controller.ex"
Task: "Performance test: recommendation generation under 5 seconds in test/performance/recommendation_performance_test.exs"
```

---

## Validation Checklist
*GATE: Verified before task execution*

- [x] All contracts have corresponding tests (T004-T008 cover both API contracts)
- [x] All entities have model tasks (T015-T016 for TrendingPlayerData, WaiverRecommendation)
- [x] All tests come before implementation (T004-T014 before T015-T034)
- [x] Parallel tasks truly independent (different files, no shared dependencies)
- [x] Each task specifies exact file path
- [x] No task modifies same file as another [P] task

## Notes

### TDD Enforcement
- **CRITICAL**: Tasks T004-T014 must ALL be completed and tests must be FAILING before starting T015
- Run `mix test` after each test task to verify failures
- Only proceed to implementation when you have comprehensive test failures

### Elixir/Phoenix Specific
- Use `ExUnit` for all testing
- Follow Ash Framework patterns for resource definitions
- Use Tesla client patterns established in existing SleeperClient
- Leverage existing Cachex setup for trending data caching
- Follow Phoenix controller and LiveView conventions

### File Organization
- All Ash resources in `lib/fantasy_manager/fantasy/`
- External integrations in `lib/fantasy_manager/external/`
- AI services in `lib/fantasy_manager/ai/`
- Controllers in `lib/fantasy_manager_web/controllers/api/`
- Tests mirror the lib structure

### Performance Targets
- Recommendation generation: < 5 seconds (T033)
- Trending data cache: 15-minute TTL (T018)
- Weekly data sync: Complete within 10 minutes (T029)
- API responses: < 3 seconds 95th percentile

---

**Task Count**: 34 tasks
**Estimated Parallel Tasks**: 15 tasks can run in parallel across different phases
**Critical Path**: Setup → Tests → SleeperClient → AI Engine → Controllers → Frontend → Validation
