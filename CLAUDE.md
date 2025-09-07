# Fantasy Manager Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-09-07

## Active Technologies
- **Elixir 1.15+** with Phoenix v1.8.1 (001-build-an-application)
- **Ash Framework** for declarative resources and APIs (001-build-an-application)
- **Ash.ai** for AI integration with Claude (001-build-an-application)
- **PostgreSQL** with Ecto for data persistence (001-build-an-application)
- **Cachex** for multi-level API response caching (001-build-an-application)
- **Tesla/Finch** for HTTP clients (Sleeper API, NFL APIs) (001-build-an-application)

## Project Structure
```
├── lib/
│   ├── fantasy_manager/           # Core fantasy domain
│   │   ├── fantasy/              # Fantasy domain (Ash resources)
│   │   └── external/             # External API integrations
│   ├── fantasy_manager_core/     # Application core
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   └── mailer.ex
│   ├── fantasy_manager_web/      # Web interface
│   │   ├── controllers/
│   │   ├── components/
│   │   └── endpoint.ex
│   └── fantasy_manager.ex        # Main application module
├── test/
│   ├── fantasy_manager_web/      # Web tests
│   ├── integration/              # Integration tests
│   └── support/                  # Test support files
├── config/                       # Configuration files
├── priv/repo/migrations/         # Database migrations
└── mix.exs                       # Project configuration
```

## Commands
```bash
# Development
mix phx.server                # Start development server
mix test                      # Run all tests
mix test --include integration # Include integration tests

# External API clients
mix run -e "FantasyManager.External.SleeperClient.get_all_players()"
mix run -e "FantasyManager.Tasks.SyncLeague.run(\"sleeper_league_id\")"

# AI testing
mix run -e "FantasyManager.AI.RecommendationEngine.test_connection()"
```

## Code Style
- **Ash Resources**: Use declarative resource definitions for all domain entities
- **AI Integration**: Use Ash.ai tools and prompt-backed actions for AI features
- **External APIs**: Implement custom data layers for external API integration
- **Caching**: Use Cachex with appropriate TTL for different data types
- **Testing**: TDD approach with contract tests for API compatibility

## Recent Changes
- 001-build-an-application: Added Elixir/Phoenix with Ash framework for fantasy football management system
- 001-build-an-application: Integrated Ash.ai for Claude-powered recommendations
- 001-build-an-application: Implemented multi-level caching strategy for external APIs

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->