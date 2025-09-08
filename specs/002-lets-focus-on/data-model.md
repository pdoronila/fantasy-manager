# Data Model: AI-Powered Free Agent Pickup Recommendations

**Feature**: 002-lets-focus-on
**Date**: 2025-09-08

## Core Entities

### TrendingPlayerData
**Purpose**: Track trending adds/drops from Sleeper API with time-based analysis

**Fields**:
- `id` (UUID, Primary Key)
- `player_id` (String, Foreign Key → Player.id) 
- `trend_type` (Enum: :add | :drop)
- `count` (Integer) - Number of adds/drops in period
- `lookback_hours` (Integer, Default: 24) - Analysis window
- `captured_at` (DateTime) - When trending data was captured
- `week` (Integer) - Fantasy week when captured
- `season` (Integer) - Fantasy season when captured

**Relationships**:
- `belongs_to :player, Player`

**Validations**:
- `player_id` required
- `trend_type` required, must be :add or :drop  
- `count` required, must be >= 0
- `lookback_hours` required, must be > 0 and <= 168 (7 days)
- `captured_at` required
- `week` required, must be 1-18
- `season` required, must be >= 2024

**Indexes**:
- `player_id, trend_type, captured_at` (compound)
- `week, season, trend_type` (compound)

### WaiverRecommendation
**Purpose**: Store AI-generated pickup recommendations for user review and history

**Fields**:
- `id` (UUID, Primary Key)
- `fantasy_team_id` (UUID, Foreign Key → FantasyTeam.id)
- `recommended_player_id` (String, Foreign Key → Player.id)
- `drop_candidate_player_id` (String, Foreign Key → Player.id, Optional)
- `priority_score` (Float) - 1.0-10.0 recommendation strength
- `reasoning` (Text) - AI-generated explanation
- `confidence_level` (Float) - 0.0-1.0 AI confidence
- `recommendation_factors` (Map) - Structured factors considered
- `estimated_points_gain` (Float, Optional) - Projected weekly points improvement
- `generated_at` (DateTime) - When recommendation was created
- `expires_at` (DateTime) - When recommendation becomes stale
- `status` (Enum: :active | :executed | :dismissed | :expired, Default: :active)
- `week` (Integer) - Target fantasy week
- `season` (Integer) - Target fantasy season

**Relationships**:
- `belongs_to :fantasy_team, FantasyTeam`
- `belongs_to :recommended_player, Player`
- `belongs_to :drop_candidate_player, Player, optional: true`

**Validations**:
- `fantasy_team_id` required
- `recommended_player_id` required
- `priority_score` required, must be 1.0-10.0
- `reasoning` required, min length 10 characters
- `confidence_level` required, must be 0.0-1.0
- `generated_at` required
- `expires_at` required, must be after `generated_at`
- `week` required, must be 1-18
- `season` required, must be >= 2024
- `status` required

**Indexes**:
- `fantasy_team_id, week, season` (compound)
- `status, expires_at` (compound)
- `recommended_player_id`

### RosterAnalysis (Extended)
**Purpose**: Detailed analysis of team roster strengths/weaknesses for AI recommendations

**New Fields** (extending existing entity):
- `position_rankings` (Map) - Performance ranking by position vs league average
- `weakness_scores` (Map) - Numerical weakness by position (0.0-10.0)
- `bench_depth_analysis` (Map) - Starter vs backup performance gaps
- `upcoming_matchup_factors` (Map) - Next 3 weeks matchup difficulty by position
- `replacement_value_needs` (Array) - Positions needing immediate attention

**Validation Rules**:
- `weakness_scores` values must be 0.0-10.0
- `position_rankings` must include QB, RB, WR, TE, K, DEF
- `upcoming_matchup_factors` must include next 1-3 weeks

## Enhanced Existing Entities

### Player (Extensions)
**New Fields**:
- `trending_adds_count` (Virtual) - Current week trending adds
- `trending_drops_count` (Virtual) - Current week trending drops  
- `roster_percentage` (Virtual) - League ownership percentage
- `recent_performance_trend` (Virtual) - Last 3 weeks point progression
- `depth_chart_position` (String, Optional) - Position on NFL team (e.g., "WR1", "RB2")

**Virtual Field Calculations**:
- Trending counts: Aggregated from TrendingPlayerData
- Roster percentage: Calculated from current league rosters
- Performance trend: Derived from recent WeeklyProjection records
- Depth chart: Sourced from external NFL data

### FantasyTeam (Extensions)  
**New Fields**:
- `waiver_budget` (Integer, Optional) - FAAB budget remaining
- `waiver_priority` (Integer, Optional) - Waiver wire position
- `recent_moves` (Array) - Last 5 add/drop transactions
- `positional_needs` (Array) - AI-identified position priorities

## Data Relationships

```
FantasyTeam ||--o{ WaiverRecommendation : generates
Player ||--o{ WaiverRecommendation : recommended_as
Player ||--o{ TrendingPlayerData : trends_for
Player ||--o{ RosterAnalysis : analyzed_in
League ||--o{ TrendingPlayerData : captures_trends_for
```

## Caching Strategy

### TrendingPlayerData
- **Cache Key**: `"trending:#{trend_type}:#{lookback_hours}:#{week}:#{season}"`
- **TTL**: 15 minutes (frequent updates during waiver periods)
- **Invalidation**: Manual trigger for Tuesday post-MNF updates

### WaiverRecommendation  
- **Cache Key**: `"recommendations:#{fantasy_team_id}:#{week}:#{season}"`
- **TTL**: 30 minutes (session-based caching)
- **Invalidation**: On roster changes or new player acquisitions

### RosterAnalysis
- **Cache Key**: `"roster_analysis:#{fantasy_team_id}:#{week}:#{season}"`
- **TTL**: 1 hour (updates with roster changes)
- **Invalidation**: On lineup changes or player moves

## Storage Considerations

### PostgreSQL Schema Extensions

**New Tables**:
```sql
-- Trending player data from Sleeper API
CREATE TABLE trending_player_data (
    id UUID PRIMARY KEY,
    player_id VARCHAR NOT NULL REFERENCES players(id),
    trend_type trending_type_enum NOT NULL,
    count INTEGER NOT NULL CHECK (count >= 0),
    lookback_hours INTEGER NOT NULL CHECK (lookback_hours > 0 AND lookback_hours <= 168),
    captured_at TIMESTAMP WITH TIME ZONE NOT NULL,
    week INTEGER NOT NULL CHECK (week >= 1 AND week <= 18),
    season INTEGER NOT NULL CHECK (season >= 2024),
    inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- AI-generated waiver recommendations  
CREATE TABLE waiver_recommendations (
    id UUID PRIMARY KEY,
    fantasy_team_id UUID NOT NULL REFERENCES fantasy_teams(id),
    recommended_player_id VARCHAR NOT NULL REFERENCES players(id),
    drop_candidate_player_id VARCHAR REFERENCES players(id),
    priority_score DECIMAL(3,1) NOT NULL CHECK (priority_score >= 1.0 AND priority_score <= 10.0),
    reasoning TEXT NOT NULL CHECK (LENGTH(reasoning) >= 10),
    confidence_level DECIMAL(3,2) NOT NULL CHECK (confidence_level >= 0.0 AND confidence_level <= 1.0),
    recommendation_factors JSONB,
    estimated_points_gain DECIMAL(5,2),
    generated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    status recommendation_status_enum DEFAULT 'active',
    week INTEGER NOT NULL CHECK (week >= 1 AND week <= 18),
    season INTEGER NOT NULL CHECK (season >= 2024),
    inserted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enums
CREATE TYPE trending_type_enum AS ENUM ('add', 'drop');
CREATE TYPE recommendation_status_enum AS ENUM ('active', 'executed', 'dismissed', 'expired');
```

**Indexes**:
```sql
-- Trending data indexes
CREATE INDEX idx_trending_player_data_compound ON trending_player_data (player_id, trend_type, captured_at);
CREATE INDEX idx_trending_data_week_season ON trending_player_data (week, season, trend_type);

-- Recommendation indexes  
CREATE INDEX idx_waiver_recommendations_team_week ON waiver_recommendations (fantasy_team_id, week, season);
CREATE INDEX idx_waiver_recommendations_status_expires ON waiver_recommendations (status, expires_at);
CREATE INDEX idx_waiver_recommendations_player ON waiver_recommendations (recommended_player_id);
```

## Data Migration Strategy

### Phase 1: Schema Creation
- Add new tables and enums
- Create indexes for performance
- Add foreign key constraints

### Phase 2: Backfill Historical Data
- Import recent trending data from Sleeper API (last 4 weeks)
- Generate initial roster analyses for existing teams
- Create baseline recommendation history

### Phase 3: Integration
- Update Ash resources with new fields
- Add virtual field calculations
- Enable caching layers

## Performance Considerations

**Query Optimization**:
- Compound indexes on frequently queried field combinations
- Partitioning trending_player_data by season for large datasets
- JSONB indexing on recommendation_factors for filtered queries

**Data Retention**:
- Archive trending_player_data older than 1 season
- Keep waiver_recommendations for 2 seasons for historical analysis
- Purge expired recommendations after 30 days

**Scalability**:
- Read replicas for reporting and analytics queries
- Connection pooling for concurrent recommendation requests
- Background job processing for data sync and analysis

---

## Validation Summary

✅ **Entities align with feature requirements**
- TrendingPlayerData supports Sleeper API integration
- WaiverRecommendation enables AI recommendation storage
- Enhanced existing entities maintain data consistency

✅ **Relationships support user workflows** 
- Team → Recommendations → Players pathway clear
- Historical tracking enabled for improvement analysis
- Cache strategy optimizes for real-time user experience

✅ **Performance considerations addressed**
- Strategic indexing for query patterns
- Appropriate caching TTLs for data freshness vs performance
- Scalable architecture for growth