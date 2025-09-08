# Fantasy Manager

An AI-powered dynasty fantasy football management system built with Elixir, Phoenix, and Ash Framework. Features intelligent lineup optimization, player valuations, and trade analysis using Claude AI.

## Features

🏈 **Dynasty League Management**
- Multi-league support with full dynasty configurations
- Player tracking with injury status and dynasty values
- Team roster management with keeper eligibility

🤖 **AI-Powered Recommendations**
- Lineup optimization with AI reasoning
- Trade analysis and recommendations  
- Player projections and valuations
- Keeper selection assistance

🔌 **External Integrations**
- Sleeper API for league synchronization
- Real-time player data and statistics
- Multi-level caching for performance

🌐 **Modern Web Interface**
- Phoenix LiveView for real-time updates
- Mobile-responsive design
- Interactive dashboard and analytics

## Quick Start

### Prerequisites

- Elixir 1.15+ and Erlang/OTP 25+
- PostgreSQL 14+
- Node.js 18+ (for assets)

### Setup

1. **Clone and install dependencies:**
   ```bash
   git clone <repository-url>
   cd fantasy-manager
   mix deps.get
   cd assets && npm install && cd ..
   ```

2. **Configure environment variables:**
   ```bash
   cp config/dev.exs.template config/dev.exs
   # Edit config/dev.exs with your settings
   ```

   **Required environment variables:**
   ```bash
   # Database
   export DB_USERNAME=postgres
   export DB_PASSWORD=postgres
   export DB_NAME=fantasy_manager_dev
   
   # AI Integration (required for recommendations)
   export ANTHROPIC_API_KEY=your_claude_api_key_here
   
   # Optional: Sleeper API (for league sync)
   export SLEEPER_BASE_URL=https://api.sleeper.app/v1
   ```

3. **Setup database and seed data:**
   ```bash
   mix ecto.setup
   mix run priv/repo/seeds.exs
   ```

4. **Start the development server:**
   ```bash
   mix phx.server
   ```

5. **Browse the application:**
   - Main app: http://localhost:4000
   - Dashboard: http://localhost:4000/dashboard
   - Health checks: http://localhost:4000/health
   - API docs: http://localhost:4000/api/v1

### Browser Testing

After setup, you can test these features:

✅ **League Management**
- View leagues at `/dashboard`
- Browse team rosters and standings
- Search players by position or name

✅ **AI Recommendations** 
- Generate lineup suggestions at `/dashboard/recommendations`
- Get AI-powered player analysis
- Test recommendation engine connectivity

✅ **API Endpoints**
- `GET /api/v1/players` - List all players
- `GET /api/v1/leagues` - List leagues
- `POST /api/v1/recommendations/optimize-lineup` - Get lineup optimization

✅ **Health Monitoring**
- `GET /health` - Basic health check
- `GET /health/ready` - Readiness probe (db + cache)
- `GET /health/live` - Liveness probe

## Development

### Project Structure

```
lib/
├── fantasy_manager/           # Core fantasy domain
│   ├── fantasy/              # Ash resources (Player, League, etc.)
│   ├── external/             # External API integrations
│   └── ai/                   # AI tools and recommendation engine
├── fantasy_manager_core/     # Application core (Repo, Mailer)
├── fantasy_manager_web/      # Web interface (Controllers, LiveViews)
└── fantasy_manager.ex        # Main application module
```

### Key Commands

```bash
# Development
mix phx.server                # Start development server
mix test                      # Run all tests
mix test --include integration # Include integration tests

# Database
mix ecto.reset               # Reset database and re-run seeds
mix ecto.migrate             # Run pending migrations

# External API testing
mix run -e "FantasyManager.External.SleeperClient.get_all_players()"
mix run -e "FantasyManager.Tasks.SyncLeague.run(\"sleeper_league_id\")"

# AI testing
mix run -e "FantasyManager.AI.RecommendationEngine.test_connection()"
```

### Configuration

The application uses environment variables for configuration:

- **Database**: Standard PostgreSQL connection settings
- **AI**: Anthropic Claude API key for recommendations
- **Cache**: Configurable TTL and limits for different data types
- **External APIs**: Rate limiting and timeout settings

See `config/dev.exs.template` for all available options.

## Architecture

### Technology Stack

- **Elixir 1.15+** with Phoenix v1.8.1 for web framework
- **Ash Framework** for declarative resources and APIs
- **Ash.ai** for AI integration with Claude
- **PostgreSQL** with Ecto for data persistence
- **Cachex** for multi-level API response caching
- **Tesla/Finch** for HTTP clients (Sleeper API, NFL APIs)

### Core Components

**Fantasy Domain** (`lib/fantasy_manager/fantasy/`)
- `Player` - Fantasy player with dynasty values and injury tracking
- `League` - Dynasty league with scoring settings and keeper rules
- `FantasyTeam` - Team roster management and competitive windows
- `WeeklyProjection` - AI-generated player projections

**AI Integration** (`lib/fantasy_manager/ai/`)
- `RecommendationEngine` - Claude-powered lineup optimization
- `FantasyTools` - Ash.ai tools for player analysis and trade evaluation

**External APIs** (`lib/fantasy_manager/external/`)
- `SleeperClient` - Sleeper API integration with caching
- Custom data layers for external API integration

### Design Principles

- **TDD Approach**: Contract tests before implementation
- **Offline Capable**: Mock data for development without external APIs
- **Performance First**: Aggressive caching with appropriate TTLs
- **Error Resilience**: Graceful degradation when external services unavailable
- **Clean Architecture**: Separation between domain, web, and external layers

## API Documentation

### Players API

```bash
# List all players
GET /api/v1/players

# Search players
GET /api/v1/players/search?q=josh&position=QB

# Get player details
GET /api/v1/players/{id}

# Filter by position
GET /api/v1/players/position/QB

# Dynasty prospects
GET /api/v1/players/dynasty

# Injury report
GET /api/v1/players/injury-report
```

### Leagues API

```bash
# List leagues
GET /api/v1/leagues

# Get league with teams
GET /api/v1/leagues/{id}

# Sync from Sleeper
POST /api/v1/leagues/sync
{"sleeper_league_id": "123456789"}

# Filter leagues
GET /api/v1/leagues/season/2024
GET /api/v1/leagues/type/dynasty
```

### AI Recommendations API

```bash
# Optimize lineup
POST /api/v1/recommendations/optimize-lineup
{
  "team_id": "uuid",
  "week": 1,
  "scoring_format": "ppr"
}

# Analyze trade
POST /api/v1/recommendations/analyze-trade
{
  "giving_players": ["player1_id"],
  "receiving_players": ["player2_id"],
  "team_context": {...}
}

# Test AI connection
GET /api/v1/recommendations/test
```

## Testing

The application includes comprehensive test coverage:

- **Unit Tests**: Resource validations and business logic
- **Integration Tests**: External API clients and AI recommendations  
- **Contract Tests**: API endpoint behavior and response formats
- **Browser Tests**: End-to-end user journeys

Run tests with:
```bash
mix test                      # Unit tests only
mix test --include integration # Include integration tests
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Follow TDD: Write failing tests first
4. Implement the feature
5. Ensure all tests pass (`mix test --include integration`)
6. Run the linter (`mix format && mix credo`)
7. Commit changes (`git commit -m 'Add amazing feature'`)
8. Push to branch (`git push origin feature/amazing-feature`)
9. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- Create an issue for bug reports or feature requests
- Check existing issues before creating new ones
- Include steps to reproduce for bug reports

---

**Fantasy Manager** - Built with ❤️ using Elixir, Phoenix, and AI