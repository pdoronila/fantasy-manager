# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fantasy_manager,
  ecto_repos: [FantasyManager.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :fantasy_manager, FantasyManagerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FantasyManagerWeb.ErrorHTML, json: FantasyManagerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FantasyManager.PubSub,
  live_view: [signing_salt: "hFiDSJYb"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fantasy_manager, FantasyManager.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fantasy_manager: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  fantasy_manager: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ash Framework
config :ash, :include_embedded_source_by_default?, false

# Configure Cachex
config :cachex, :default_ttl, :timer.hours(1)

# Configure LangChain for AI integration
config :langchain, :openai_key, System.get_env("OPENAI_API_KEY")
config :langchain, :anthropic_key, System.get_env("ANTHROPIC_API_KEY")

# Configure Tesla HTTP client
config :tesla, adapter: Tesla.Adapter.Finch
config :tesla, disable_deprecated_builder_warning: true

# Configure Finch HTTP client
config :fantasy_manager, :finch_pools, %{
  "https://api.sleeper.app" => [
    size: 16,
    conn_max_idle_time: 30_000
  ],
  "https://api.nfl.com" => [
    size: 8,
    conn_max_idle_time: 30_000
  ],
  default: [
    size: 32,
    conn_max_idle_time: 10_000
  ]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
