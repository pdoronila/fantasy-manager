# Configuration Setup

This directory contains the configuration files for the Fantasy Manager application.

## Files

- **`config.exs`** - Application-wide configuration and shared settings
- **`dev.exs`** - Development environment configuration
- **`test.exs`** - Test environment configuration  
- **`prod.exs`** - Production environment configuration
- **`runtime.exs`** - Runtime configuration that loads environment variables
- **`dev.exs.template`** - Template showing environment variable structure

## Environment Variables

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

### Required Variables

- `ANTHROPIC_API_KEY` - Your Claude API key for AI recommendations
- `SECRET_KEY_BASE` - Phoenix secret key (generate with `mix phx.gen.secret`)

### Optional Variables

- `NFL_API_KEY` - NFL statistics API key
- `OPENAI_API_KEY` - OpenAI API key for LangChain fallback
- `PORT` - Server port (default: 4000)
- `DATABASE_URL` - Full database URL (alternative to individual DB settings)

## Configuration Structure

### Cache Configuration
- **Default cache**: General application caching (limit: 2500)
- **Sleeper cache**: Sleeper API response cache (TTL: 1 hour, limit: 1000)
- **NFL data cache**: NFL API response cache (TTL: 2 hours, limit: 500)

### External API Configuration
- **Sleeper API**: Fantasy platform integration with rate limiting
- **NFL Data API**: Statistics and player information
- **Tesla/Finch**: HTTP client with connection pooling

### AI Configuration
- **Ash.ai**: Integrated AI framework using Claude
- **LangChain**: AI framework for complex workflows
- **Temperature**: 0.1 for consistent recommendations
- **Timeout**: 60 seconds for AI operations

## Development Setup

1. Install dependencies: `mix deps.get`
2. Setup database: `mix ecto.setup`
3. Copy environment template: `cp .env.example .env`
4. Fill in required API keys in `.env`
5. Start server: `mix phx.server`

## Testing Configuration

Test environment uses:
- In-memory database with sandbox mode
- Smaller cache limits for faster tests
- Mock API endpoints for external services
- Deterministic AI responses (temperature: 0.0)
- Shorter timeouts for faster test execution