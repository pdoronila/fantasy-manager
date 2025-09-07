defmodule FantasyManagerWeb.Router do
  use FantasyManagerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FantasyManagerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    # TODO: Add AshJsonApi.Plug once API is configured
    # plug AshJsonApi.Plug
  end

  scope "/", FantasyManagerWeb do
    pipe_through :browser

    get "/", PageController, :home
    
    # Fantasy Manager LiveViews
    live "/dashboard", DashboardLive, :index
    live "/dashboard/league/:id", DashboardLive, :league_detail
    live "/dashboard/recommendations", RecommendationsLive, :index
  end

  # API routes
  scope "/api/v1", FantasyManagerWeb.Api do
    pipe_through :api
    
    # Players API
    get "/players", PlayersController, :index
    get "/players/search", PlayersController, :search
    get "/players/:id", PlayersController, :show
    get "/players/position/:position", PlayersController, :by_position
    get "/players/dynasty", PlayersController, :dynasty_prospects
    get "/players/injury-report", PlayersController, :injury_report
    
    # Leagues API
    get "/leagues", LeaguesController, :index
    get "/leagues/:id", LeaguesController, :show
    post "/leagues", LeaguesController, :create
    put "/leagues/:id", LeaguesController, :update
    post "/leagues/sync", LeaguesController, :sync_from_sleeper
    get "/leagues/season/:season", LeaguesController, :by_season
    get "/leagues/type/:type", LeaguesController, :by_type
    get "/leagues/keeper", LeaguesController, :keeper_leagues
    get "/leagues/dynasty", LeaguesController, :dynasty_leagues
    get "/leagues/:id/teams", LeaguesController, :teams
    
    # AI Recommendations API
    post "/recommendations/optimize-lineup", RecommendationsController, :optimize_lineup
    post "/recommendations/analyze-trade", RecommendationsController, :analyze_trade
    post "/recommendations/projections", RecommendationsController, :get_projections
    post "/recommendations/waivers", RecommendationsController, :waiver_suggestions
    post "/recommendations/keepers", RecommendationsController, :keeper_recommendations
    get "/recommendations/test", RecommendationsController, :test_connection
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fantasy_manager, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FantasyManagerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
