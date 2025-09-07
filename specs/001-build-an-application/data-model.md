# Data Model: Fantasy Football Management System

**Phase 1 Output** | **Date**: 2025-09-07

## Core Entities

### Player
**Purpose**: Represents an NFL player with fantasy-relevant data
**Fields**:
- `id`: UUID (primary key)
- `sleeper_id`: String (external identifier)
- `name`: String (full name)
- `position`: String (QB, RB, WR, TE, K, DEF)
- `nfl_team`: String (team abbreviation)
- `injury_status`: String (Active, Questionable, Doubtful, Out, IR, PUP)
- `years_pro`: Integer
- `age`: Integer
- `rookie_year`: Integer
- `dynasty_value`: Decimal (0-100 scale)
- `keeper_eligible`: Boolean
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `has_many :player_stats` → PlayerStat
- `has_many :fantasy_team_players` → FantasyTeamPlayer
- `has_many :projections` → WeeklyProjection
- `has_many :keeper_contracts` → KeeperContract

**Validations**:
- Name must be present and at least 2 characters
- Position must be one of valid NFL positions
- Dynasty value between 0-100
- Years pro must be non-negative

**State Transitions**:
- Active → Injured (injury occurs)
- Injured → Active (returns from injury)
- Active → Retired (end of career)

### League
**Purpose**: Represents a Sleeper fantasy league configuration
**Fields**:
- `id`: UUID (primary key)
- `sleeper_id`: String (external identifier)
- `name`: String
- `season`: Integer
- `league_type`: String (keeper, dynasty, redraft)
- `scoring_format`: String (PPR, Half PPR, Standard, Superflex)
- `roster_size`: Integer
- `keeper_count`: Integer (for keeper leagues)
- `dynasty_transition_year`: Integer (nullable)
- `trade_deadline_week`: Integer
- `waiver_type`: String (FAAB, Rolling, Reverse)
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `has_many :fantasy_teams` → FantasyTeam
- `has_many :league_settings` → LeagueSetting
- `belongs_to :owner` → User

**Validations**:
- Name must be present
- Season must be current or future year
- Roster size between 10-20
- Keeper count <= roster size
- Trade deadline between weeks 1-17

### FantasyTeam
**Purpose**: Represents a user's team within a specific league
**Fields**:
- `id`: UUID (primary key)
- `sleeper_id`: String (external identifier)
- `name`: String
- `owner_name`: String
- `competitive_window`: String (Contending, Rebuilding, Neutral)
- `waiver_priority`: Integer
- `faab_budget`: Integer
- `total_moves`: Integer
- `league_id`: UUID (foreign key)
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :league` → League
- `has_many :fantasy_team_players` → FantasyTeamPlayer
- `has_many :keeper_contracts` → KeeperContract
- `has_many :trade_proposals_sent` → TradeProposal (as sender)
- `has_many :trade_proposals_received` → TradeProposal (as receiver)

**Validations**:
- Name must be present
- Competitive window must be valid enum
- FAAB budget must be non-negative

### FantasyTeamPlayer
**Purpose**: Junction table for team rosters with position info
**Fields**:
- `id`: UUID (primary key)
- `fantasy_team_id`: UUID (foreign key)
- `player_id`: UUID (foreign key)
- `roster_position`: String (Starter, Bench, IR, Taxi)
- `lineup_position`: String (QB1, RB1, RB2, WR1, WR2, TE, FLEX, K, DEF)
- `acquisition_type`: String (Draft, Trade, Waiver, Free Agent)
- `acquisition_date`: Date
- `acquisition_cost`: Integer (FAAB or waiver priority)
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :fantasy_team` → FantasyTeam
- `belongs_to :player` → Player

**Validations**:
- Roster position must be valid enum
- Only one player per lineup position per team
- Acquisition cost must be non-negative

### PlayerStat
**Purpose**: Weekly and seasonal statistics for players
**Fields**:
- `id`: UUID (primary key)
- `player_id`: UUID (foreign key)
- `season`: Integer
- `week`: Integer (nullable for season totals)
- `game_id`: String
- `opponent`: String
- `passing_yards`: Integer
- `passing_tds`: Integer
- `passing_ints`: Integer
- `rushing_yards`: Integer
- `rushing_tds`: Integer
- `receiving_yards`: Integer
- `receiving_tds`: Integer
- `receptions`: Integer
- `targets`: Integer
- `fantasy_points`: Decimal
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :player` → Player

**Validations**:
- Season must be valid NFL season
- Week between 1-18 if present
- All stat fields must be non-negative

### WeeklyProjection
**Purpose**: AI-generated projections for upcoming games
**Fields**:
- `id`: UUID (primary key)
- `player_id`: UUID (foreign key)
- `season`: Integer
- `week`: Integer
- `projected_points`: Decimal
- `confidence_score`: Decimal (0-1)
- `projection_model`: String
- `factors_considered`: JSONB
- `created_by`: String (AI model version)
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :player` → Player

**Validations**:
- Season and week must be valid
- Confidence score between 0-1
- Projected points must be non-negative

### TradeProposal
**Purpose**: Trade proposals between teams
**Fields**:
- `id`: UUID (primary key)
- `sender_team_id`: UUID (foreign key)
- `receiver_team_id`: UUID (foreign key)
- `status`: String (Pending, Accepted, Rejected, Countered, Expired)
- `offered_players`: JSONB (array of player IDs)
- `requested_players`: JSONB (array of player IDs)
- `offered_picks`: JSONB (draft picks if applicable)
- `requested_picks`: JSONB (draft picks if applicable)
- `notes`: Text
- `expires_at`: DateTime
- `ai_analysis`: JSONB
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :sender_team` → FantasyTeam
- `belongs_to :receiver_team` → FantasyTeam

**Validations**:
- Status must be valid enum
- Must have at least one offered or requested asset
- Cannot trade with self
- Expires at must be future date

### KeeperContract
**Purpose**: Keeper eligibility and cost tracking
**Fields**:
- `id`: UUID (primary key)
- `fantasy_team_id`: UUID (foreign key)
- `player_id`: UUID (foreign key)
- `contract_year`: Integer
- `years_remaining`: Integer
- `keeper_cost`: Integer (draft round or FAAB amount)
- `cost_escalation`: Decimal (yearly increase multiplier)
- `is_eligible`: Boolean
- `designation_deadline`: Date
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :fantasy_team` → FantasyTeam
- `belongs_to :player` → Player

**Validations**:
- Years remaining must be non-negative
- Keeper cost must be positive
- Cost escalation must be >= 1.0

### Matchup
**Purpose**: Weekly head-to-head matchups
**Fields**:
- `id`: UUID (primary key)
- `league_id`: UUID (foreign key)
- `season`: Integer
- `week`: Integer
- `team_1_id`: UUID (foreign key)
- `team_2_id`: UUID (foreign key)
- `team_1_score`: Decimal
- `team_2_score`: Decimal
- `is_playoffs`: Boolean
- `matchup_type`: String (Regular, Playoffs, Championship)
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :league` → League
- `belongs_to :team_1` → FantasyTeam
- `belongs_to :team_2` → FantasyTeam

**Validations**:
- Week between 1-18
- Scores must be non-negative
- Teams cannot play themselves

### Recommendation
**Purpose**: AI-generated recommendations and analysis
**Fields**:
- `id`: UUID (primary key)
- `fantasy_team_id`: UUID (foreign key)
- `recommendation_type`: String (Lineup, Trade, Pickup, Keeper, Dynasty)
- `context`: JSONB (request parameters)
- `recommendation_data`: JSONB (structured recommendation)
- `confidence_score`: Decimal (0-1)
- `reasoning`: Text
- `time_horizon`: String (Short, Medium, Long)
- `ai_model`: String
- `expires_at`: DateTime
- `inserted_at`: DateTime
- `updated_at`: DateTime

**Relationships**:
- `belongs_to :fantasy_team` → FantasyTeam

**Validations**:
- Recommendation type must be valid enum
- Confidence score between 0-1
- Time horizon must be valid enum

## Entity Relationships Summary

```
League (1) ←→ (Many) FantasyTeam
FantasyTeam (1) ←→ (Many) FantasyTeamPlayer (Many) ←→ (1) Player
Player (1) ←→ (Many) PlayerStat
Player (1) ←→ (Many) WeeklyProjection
FantasyTeam (1) ←→ (Many) KeeperContract (Many) ←→ (1) Player
FantasyTeam (1) ←→ (Many) TradeProposal (sender/receiver)
League (1) ←→ (Many) Matchup
FantasyTeam (1) ←→ (Many) Recommendation
```

## Data Validation Rules

### Business Rules
1. **Roster Limits**: Teams cannot exceed league roster size
2. **Position Limits**: Cannot start more players than position limits allow
3. **Trade Deadlines**: Trades cannot be processed after deadline
4. **Keeper Limits**: Cannot designate more keepers than league allows
5. **FAAB Budget**: Total spending cannot exceed allocated budget
6. **Waiver Priority**: Must be unique per team in league

### Data Integrity
1. **Soft Deletes**: Players and stats are never hard deleted
2. **Audit Trail**: All roster moves tracked with timestamps
3. **Referential Integrity**: Foreign keys enforced at database level
4. **Unique Constraints**: Sleeper IDs unique per entity type

## Indexing Strategy

### Performance Indexes
```sql
-- Query optimization
CREATE INDEX idx_player_stats_player_season_week ON player_stats(player_id, season, week);
CREATE INDEX idx_fantasy_team_players_team_active ON fantasy_team_players(fantasy_team_id) WHERE roster_position != 'Dropped';
CREATE INDEX idx_weekly_projections_season_week ON weekly_projections(season, week);

-- External API lookups
CREATE INDEX idx_players_sleeper_id ON players(sleeper_id);
CREATE INDEX idx_leagues_sleeper_id ON leagues(sleeper_id);
CREATE INDEX idx_fantasy_teams_sleeper_id ON fantasy_teams(sleeper_id);

-- AI and analysis queries
CREATE INDEX idx_players_position_dynasty_value ON players(position, dynasty_value DESC);
CREATE INDEX idx_recommendations_team_type_expires ON recommendations(fantasy_team_id, recommendation_type, expires_at);
```

## Migration Strategy

### Phase 1: Core Tables
1. Create core entities (Player, League, FantasyTeam)
2. Basic relationships and constraints
3. Essential indexes

### Phase 2: Statistics and Projections  
1. PlayerStat and WeeklyProjection tables
2. Historical data migration
3. Performance indexes

### Phase 3: Advanced Features
1. TradeProposal and KeeperContract
2. Recommendation system
3. AI-specific fields and indexes

### Phase 4: Optimization
1. Additional performance indexes
2. Partitioning for large tables
3. Archive strategy for old data

This data model provides a comprehensive foundation for the fantasy football management system while maintaining flexibility for future enhancements and supporting both keeper and dynasty league formats.