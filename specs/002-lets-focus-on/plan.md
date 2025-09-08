# Implementation Plan: AI-Powered Free Agent Pickup Recommendations

**Branch**: `002-lets-focus-on` | **Date**: 2025-09-08 | **Spec**: [spec.md](/Users/doronila/git/fantasy-manager/specs/002-lets-focus-on/spec.md)
**Input**: Feature specification from `/specs/002-lets-focus-on/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
4. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
5. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, or `GEMINI.md` for Gemini CLI).
6. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
7. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
8. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary
Implement an AI-powered recommendation system that analyzes fantasy football team rosters, identifies positional weaknesses based on recent performance data, and suggests trending free agents for waiver pickups. The system leverages Sleeper API for player data, trending information, and league rosters, combined with Claude AI to generate intelligent recommendations based on team-specific needs and player availability.

## Technical Context
**Language/Version**: Elixir 1.15+ with Phoenix v1.8.1  
**Primary Dependencies**: Ash Framework, Ash.ai for Claude integration, Tesla/Finch HTTP clients, Cachex for caching  
**Storage**: PostgreSQL with Ecto for data persistence  
**Testing**: ExUnit for Elixir testing  
**Target Platform**: Web application with backend API and LiveView frontend
**Project Type**: web - Phoenix application with backend services and LiveView interface  
**Performance Goals**: Handle weekly player data updates, real-time recommendation generation  
**Constraints**: Weekly batch updates for player data (Tuesdays post-MNF), API rate limiting for Sleeper endpoints, cache TTL management  
**Scale/Scope**: Support multiple fantasy leagues, thousands of players, real-time AI recommendations

**External API Integration Requirements** (from user input):
- Sleeper API endpoints: trending players, all players, league matchups, league rosters  
- Focus on data collection and Claude prompt generation for recommendations
- Weekly player data sync schedule (Tuesday mornings after Monday Night Football)

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Simplicity**:
- Projects: 1 (existing Phoenix application)
- Using framework directly? ✅ Direct Ash resources, Phoenix controllers
- Single data model? ✅ Ash resources without unnecessary DTOs
- Avoiding patterns? ✅ Using Ash data layers instead of Repository pattern

**Architecture**:
- EVERY feature as library? ✅ Ash resources are declarative libraries
- Libraries listed: SleeperClient (API integration), RecommendationEngine (AI logic), TrendingData (caching layer)
- CLI per library: ✅ Mix tasks for data sync and testing
- Library docs: ✅ Using existing CLAUDE.md format

**Testing (NON-NEGOTIABLE)**:
- RED-GREEN-Refactor cycle enforced? ✅ Contract tests first, then implementation
- Git commits show tests before implementation? ✅ Will enforce TDD
- Order: Contract→Integration→E2E→Unit strictly followed? ✅ API contracts first
- Real dependencies used? ✅ Actual Sleeper API and Claude API in integration tests
- Integration tests for: ✅ Sleeper API integration, Claude AI integration, recommendation pipeline
- FORBIDDEN: Implementation before test, skipping RED phase ✅ Enforced

**Observability**:
- Structured logging included? ✅ Phoenix telemetry and structured logging
- Frontend logs → backend? ✅ LiveView error handling
- Error context sufficient? ✅ Error tracking for API failures and AI responses

**Versioning**:
- Version number assigned? ✅ Mix project version
- BUILD increments on every change? ✅ Will follow semantic versioning
- Breaking changes handled? ✅ API versioning strategy

## Project Structure

### Documentation (this feature)
```
specs/[###-feature]/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── contracts/           # Phase 1 output (/plan command)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
# Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure]
```

**Structure Decision**: [DEFAULT to Option 1 unless Technical Context indicates web/mobile app]

## Phase 0: Outline & Research
1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:
   ```
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

## Phase 1: Design & Contracts
*Prerequisites: research.md complete*

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Generate contract tests** from contracts:
   - One test file per endpoint
   - Assert request/response schemas
   - Tests must fail (no implementation yet)

4. **Extract test scenarios** from user stories:
   - Each story → integration test scenario
   - Quickstart test = story validation steps

5. **Update agent file incrementally** (O(1) operation):
   - Run `/scripts/update-agent-context.sh [claude|gemini|copilot]` for your AI assistant
   - If exists: Add only NEW tech from current plan
   - Preserve manual additions between markers
   - Update recent changes (keep last 3)
   - Keep under 150 lines for token efficiency
   - Output to repository root

**Output**: data-model.md, /contracts/*, failing tests, quickstart.md, agent-specific file

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `/templates/tasks-template.md` as base
- Generate tasks from Phase 1 design docs (contracts, data model, quickstart)
- Each contract endpoint → contract test task [P]
- Each entity → Ash resource creation task [P] 
- Each user story from quickstart → integration test task
- AI recommendation pipeline → service implementation tasks
- External API extension → client enhancement tasks

**Specific Task Categories**:
1. **Database & Models** [P]:
   - Migration for TrendingPlayerData
   - Migration for WaiverRecommendation
   - Ash resource for TrendingPlayerData
   - Ash resource for WaiverRecommendation
   - Extend Player resource with virtual fields
   
2. **External API Integration** [P]:
   - Add trending players endpoint to SleeperClient
   - Contract tests for trending API endpoints
   - Caching layer for trending data
   - Weekly sync job for player data updates

3. **AI Recommendation Engine**:
   - Extend RecommendationEngine with waiver logic
   - Create waiver-specific AI tools and prompts
   - Roster analysis service for weakness detection
   - Recommendation ranking and filtering logic
   
4. **API Endpoints**:
   - Contract tests for recommendations API
   - Contract tests for trending API  
   - Phoenix controller for recommendations
   - Phoenix controller for trending data
   - API parameter validation and error handling

5. **Frontend Integration**:
   - LiveView component for recommendations display
   - Integration tests for complete user journey
   - UI for recommendation tracking and dismissal

**Ordering Strategy**:
- TDD order: Contract tests → Integration tests → Implementation 
- Dependency order: Database → External APIs → AI Services → Controllers → Frontend
- Mark [P] for parallel execution (independent database/API tasks)
- Critical path: SleeperClient extension → AI recommendation logic → API endpoints

**Estimated Output**: 28-35 numbered, ordered tasks in tasks.md

**Key Dependencies**:
- Trending data endpoint must be implemented before AI recommendations
- Database schema must be ready before Ash resources  
- AI recommendation logic must be complete before API endpoints
- Contract tests must pass before user acceptance testing

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)  
**Phase 4**: Implementation (execute tasks.md following constitutional principles)  
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented

---
*Based on Constitution v2.1.1 - See `/memory/constitution.md`*