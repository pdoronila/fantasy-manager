# Research: Ash Framework and Ash.ai for Fantasy Football Management

**Phase 0 Output** | **Date**: 2025-09-07

## Technical Decisions

### Decision: Use Ash Framework as Core Architecture
**Rationale**: Ash provides declarative resource-based development that naturally maps to fantasy football domain (players, teams, leagues). Built-in API generation, calculated fields, and relationships reduce boilerplate while maintaining type safety.
**Alternatives Considered**: 
- Pure Phoenix (more manual work, less declarative)
- Absinthe-only GraphQL (missing REST APIs, no built-in caching)
- Traditional MVC pattern (doesn't leverage Elixir's strengths)

### Decision: Ash.ai for AI Integration
**Rationale**: Provides structured AI integration with tool calling, vectorization for similarity search, and prompt-backed actions. Integrates seamlessly with Claude API while maintaining type safety and error handling.
**Alternatives Considered**:
- Direct LangChain integration (less structured, more manual)
- OpenAI API directly (vendor lock-in, less structured outputs)
- Local LLMs (performance and resource constraints)

### Decision: Custom Data Layers for External APIs
**Rationale**: Allows external APIs (Sleeper, NFL stats) to be treated as first-class Ash resources while controlling caching, rate limiting, and error handling at the data layer level.
**Alternatives Considered**:
- Service layer pattern (breaks Ash resource paradigm)
- Direct HTTP calls in actions (less cacheable, harder to test)
- Background job sync (adds complexity, less real-time)

### Decision: Multi-Level Caching Strategy
**Rationale**: Different data types have different freshness requirements:
- Player info: 24h TTL (rarely changes)
- Game stats: 1h TTL during games, 6h otherwise
- Projections: 30min TTL (frequently recalculated)
- Roster data: 10min TTL (changes during trades/waivers)
**Alternatives Considered**:
- Single cache layer (less flexible)
- Database-only caching (slower)
- Redis external cache (additional infrastructure)

## Framework Capabilities Analysis

### Ash Resources for Fantasy Domain

```elixir
# Example resource structure
defmodule FantasyManager.Fantasy.Player do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshAi.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :position, :string, allow_nil?: false
    attribute :sleeper_id, :string
    attribute :dynasty_value, :decimal
  end

  calculations do
    calculate :projected_points, :decimal, FantasyManager.Calculations.WeeklyProjection
    calculate :keeper_value, :decimal, FantasyManager.Calculations.KeeperValue
  end

  ai do
    vectorize do
      vector_attribute :embedding
      attributes [:name, :position, :recent_performance]
    end
  end
end
```

### API Generation Benefits
- Automatic JSON:API endpoints for all resources
- GraphQL schema generation for complex queries
- Built-in pagination, filtering, and sorting
- Type-safe request/response validation

### External API Integration Pattern

```elixir
defmodule FantasyManager.External.SleeperDataLayer do
  use Ash.DataLayer

  def run_query(query, _resource, _context) do
    case query.action.name do
      :read -> 
        cached_result = Cachex.get(:sleeper_cache, cache_key(query))
        case cached_result do
          {:ok, nil} ->
            result = SleeperClient.fetch_data(query)
            Cachex.put(:sleeper_cache, cache_key(query), result, ttl: @ttl)
            {:ok, result}
          {:ok, data} -> {:ok, data}
        end
    end
  end
end
```

## AI Capabilities Assessment

### Ash.ai Integration Points
1. **Vectorization**: Player similarity search for trade recommendations
2. **Tool Calling**: Structured data access from AI recommendations
3. **Prompt Actions**: Natural language analysis of matchups and trades
4. **Embedding Search**: Finding similar players for dynasty planning

### Claude Integration Architecture
```elixir
defmodule FantasyManager.AI.RecommendationEngine do
  def analyze_trade_proposal(trade_data) do
    LangChain.Chains.LLMChain.run(
      llm: claude_model(),
      prompt: build_trade_analysis_prompt(trade_data),
      tools: FantasyManager.AI.Tools.list_tools(),
      output_schema: TradeAnalysisSchema
    )
  end
end
```

## Caching Strategy Details

### Cache Hierarchy
- **L1**: ETS tables for hot data (current week projections)
- **L2**: Cachex for API responses (external data)
- **L3**: PostgreSQL for computed aggregates (historical analysis)

### Invalidation Strategy
- Game completion triggers player stat cache invalidation
- Trade transactions invalidate roster caches
- Injury reports trigger projection recalculation
- Weekly rollover clears projection caches

## Testing Approach

### Resource Testing
```elixir
test "player projection calculation" do
  player = create_player_with_historical_data()
  
  projection = FantasyManager.Fantasy.Player
  |> Ash.Query.for_read(:read)
  |> Ash.Query.load(:projected_points)
  |> Ash.Query.filter(id == ^player.id)
  |> FantasyManager.Fantasy.read_one!()
  
  assert projection.projected_points > 0
end
```

### External API Mocking
- Use Tesla mocks for HTTP layer testing
- Custom test data layers for integration tests
- VCR-style recording for development

### AI Feature Testing
- Mock LangChain responses for deterministic tests
- Test tool calling integration separately
- Performance tests for embedding operations

## Performance Considerations

### Query Optimization
- Ash queries compile to optimized SQL
- Eager loading with `load/1` prevents N+1 queries
- Calculated fields cached at resource level

### Scaling Strategy
- Background jobs (Oban) for heavy computations
- Read replicas for analytics queries
- CDN for static fantasy data

## Risk Mitigation

### Framework Maturity
- Ash 3.0+ is production-ready
- Active community and maintainer support
- Fallback to Phoenix patterns if needed

### External Dependencies
- Circuit breaker pattern for API failures
- Graceful degradation when AI unavailable
- Local fallback data for critical operations

### Cost Management
- AI usage monitoring and limits
- Caching strategy reduces API calls
- Batch processing for bulk operations

## Implementation Recommendations

### Phase 1: Foundation (Weeks 1-2)
- Core Ash resources (Player, Team, League)
- Basic Sleeper API integration
- Simple caching layer

### Phase 2: Intelligence (Weeks 3-4)
- AI recommendation engine
- Advanced projections
- Dynasty/keeper analysis

### Phase 3: Optimization (Weeks 5-6)
- Performance tuning
- Advanced caching
- Monitoring and alerts

### Phase 4: Enhancement (Weeks 7-8)
- Claude Code integration
- Advanced analytics
- User experience improvements

## Conclusion

Ash Framework with Ash.ai provides an excellent foundation for a fantasy football management system. The declarative approach reduces development time while providing powerful features like automatic API generation, built-in AI integration, and flexible caching strategies. The framework's maturity and Phoenix ecosystem integration make it a solid choice for this domain.

**Key Success Factors**:
1. Leverage Ash's declarative patterns rather than fighting them
2. Design cache strategy early to handle API rate limits
3. Use AI judiciously - not every feature needs AI
4. Test external integrations thoroughly with mocks
5. Monitor performance from day one