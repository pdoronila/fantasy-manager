defmodule FantasyManagerWeb.Api.RecommendationsController do
  @moduledoc """
  API controller for waiver recommendations endpoints.
  
  Handles:
  - GET /api/v1/teams/:team_id/recommendations - Get recommendations for a team
  - PATCH /api/v1/teams/:team_id/recommendations/:id/status - Update recommendation status
  """
  
  use FantasyManagerWeb, :controller
  
  alias FantasyManager.AI.RecommendationEngine
  alias FantasyManager.Fantasy.WaiverRecommendation
  alias FantasyManager.Fantasy.FantasyTeam
  
  require Ash.Query
  import Ash.Expr
  
  action_fallback FantasyManagerWeb.Api.FallbackController

  # Rate limiting configuration
  @rate_limits %{
    # Regular recommendation requests: 10 per hour per team
    recommendations: %{limit: 10, window: 60 * 60, scope: :team},
    
    # Status updates: 50 per hour per team (more lenient)
    status_updates: %{limit: 50, window: 60 * 60, scope: :team},
    
    # Global rate limit per IP: 100 requests per hour
    global: %{limit: 100, window: 60 * 60, scope: :ip}
  }

  @doc """
  GET /api/v1/teams/:team_id/recommendations
  
  Retrieves waiver recommendations for a specific team.
  
  Query parameters:
  - status: Filter by status (pending, applied, dismissed)
  - position: Filter by position (QB, RB, WR, TE, K, DEF)
  - page: Page number for pagination (default: 1)
  - per_page: Results per page (default: 20, max: 100)
  """
  def index(conn, %{"team_id" => team_id} = params) do
    with {:ok, conn} <- check_rate_limit(conn, :recommendations, team_id),
         {:ok, _team} <- validate_team_exists(team_id),
         {:ok, {recommendations, meta}} <- get_recommendations(team_id, params) do
      
      conn
      |> add_rate_limit_headers(:recommendations, team_id)
      |> put_status(:ok)
      |> json(%{
        data: format_recommendations(recommendations),
        meta: meta
      })
    end
  end

  @doc """
  PATCH /api/v1/teams/:team_id/recommendations/:recommendation_id/status
  
  Updates the status of a recommendation.
  
  Body parameters:
  - status: New status (applied, dismissed)
  """
  def update_status(conn, %{
    "team_id" => team_id, 
    "recommendation_id" => recommendation_id,
    "status" => new_status
  }) do
    with {:ok, conn} <- check_rate_limit(conn, :status_updates, team_id),
         {:ok, _team} <- validate_team_exists(team_id),
         {:ok, recommendation} <- get_recommendation_for_team(recommendation_id, team_id),
         {:ok, valid_status} <- validate_status(new_status),
         {:ok, updated_recommendation} <- update_recommendation_status(recommendation, valid_status) do
      
      conn
      |> add_rate_limit_headers(:status_updates, team_id)
      |> put_status(:ok)
      |> json(%{
        data: format_recommendation(updated_recommendation)
      })
    end
  end

  def update_status(conn, params) do
    missing_params = []
    missing_params = if Map.has_key?(params, "status"), do: missing_params, else: ["status" | missing_params]
    
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "Missing required parameters",
      missing: missing_params
    })
  end

  # Private functions
  
  defp validate_team_exists(team_id) do
    case Ash.get(FantasyTeam, team_id) do
      {:ok, team} -> {:ok, team}
      {:error, %Ash.Error.Query.NotFound{}} ->
        {:error, :not_found, "Team not found"}
      {:error, reason} ->
        {:error, :internal_error, "Database error: #{inspect(reason)}"}
    end
  end
  
  defp get_recommendations(team_id, params) do
    # Parse query parameters
    status_filter = Map.get(params, "status")
    position_filter = Map.get(params, "position")
    page = parse_integer(Map.get(params, "page", "1"), 1)
    per_page = parse_integer(Map.get(params, "per_page", "20"), 20)
    per_page = min(per_page, 100) # Limit maximum per_page
    
    # Build query
    query = WaiverRecommendation
    |> Ash.Query.filter(team_id == ^team_id)
    |> Ash.Query.sort(priority_score: :desc, generated_at: :desc)
    
    # Apply filters
    query = if status_filter do
      Ash.Query.filter(query, status == ^status_filter)
    else
      query
    end
    
    query = if position_filter do
      Ash.Query.filter(query, position == ^position_filter)
    else
      query
    end
    
    # Apply pagination
    offset = (page - 1) * per_page
    paginated_query = query
    |> Ash.Query.limit(per_page)
    |> Ash.Query.offset(offset)
    
    case Ash.read(paginated_query) do
      {:ok, recommendations} ->
        # Get total count for pagination metadata
        case Ash.count(query) do
          {:ok, total_count} ->
            meta = %{
              total: total_count,
              page: page,
              per_page: per_page,
              total_pages: div(total_count + per_page - 1, per_page)
            }
            {:ok, {recommendations, meta}}
          
          {:error, reason} ->
            {:error, :internal_error, "Count query failed: #{inspect(reason)}"}
        end
      
      {:error, reason} ->
        {:error, :internal_error, "Query failed: #{inspect(reason)}"}
    end
  end
  
  defp get_recommendation_for_team(recommendation_id, team_id) do
    case WaiverRecommendation
         |> Ash.Query.filter(id == ^recommendation_id and team_id == ^team_id)
         |> Ash.read_one() do
      {:ok, nil} ->
        {:error, :not_found, "Recommendation not found"}
      {:ok, recommendation} ->
        {:ok, recommendation}
      {:error, reason} ->
        {:error, :internal_error, "Database error: #{inspect(reason)}"}
    end
  end
  
  defp validate_status(status) when status in ["applied", "dismissed"] do
    {:ok, status}
  end
  
  defp validate_status(status) do
    {:error, :bad_request, "Invalid status: #{status}. Must be 'applied' or 'dismissed'"}
  end
  
  defp update_recommendation_status(recommendation, new_status) do
    case WaiverRecommendation.update_status(recommendation, %{status: new_status}) do
      {:ok, updated_rec} -> {:ok, updated_rec}
      {:error, reason} -> {:error, :internal_error, "Update failed: #{inspect(reason)}"}
    end
  end
  
  defp format_recommendations(recommendations) do
    Enum.map(recommendations, &format_recommendation/1)
  end
  
  defp format_recommendation(recommendation) do
    %{
      id: recommendation.id,
      player_id: recommendation.player_id,
      player_name: recommendation.player_name,
      position: recommendation.position,
      team: recommendation.team,
      recommendation_type: recommendation.recommendation_type,
      priority_score: if(is_struct(recommendation.priority_score, Decimal), do: Decimal.to_float(recommendation.priority_score), else: recommendation.priority_score),
      reasoning: recommendation.reasoning,
      status: recommendation.status,
      week: recommendation.week,
      season: recommendation.season,
      generated_at: recommendation.generated_at,
      expires_at: recommendation.expires_at
    }
  end
  
  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
  
  defp parse_integer(value, default) when is_integer(value) and value > 0, do: value
  defp parse_integer(_, default), do: default

  # ============================================================================
  # RATE LIMITING IMPLEMENTATION
  # ============================================================================

  @doc """
  Checks rate limits for the current request.
  
  Implements both specific endpoint rate limits and global IP-based rate limits.
  Uses ETS tables for fast in-memory rate limit storage with TTL expiration.
  """
  defp check_rate_limit(conn, rate_type, identifier) do
    rate_config = @rate_limits[rate_type]
    global_config = @rate_limits[:global]
    
    client_ip = get_client_ip(conn)
    
    with {:ok, conn} <- check_specific_rate_limit(conn, rate_type, identifier, rate_config),
         {:ok, conn} <- check_global_rate_limit(conn, client_ip, global_config) do
      {:ok, conn}
    else
      {:error, :rate_limit_exceeded} = error -> error
      error -> error
    end
  end

  defp check_specific_rate_limit(conn, rate_type, identifier, config) do
    key = build_rate_limit_key(rate_type, config.scope, identifier, conn)
    
    case check_and_increment_rate_limit(key, config.limit, config.window) do
      {:ok, current_count} ->
        conn = put_rate_limit_info(conn, rate_type, current_count, config)
        {:ok, conn}
      
      {:error, :rate_limit_exceeded, current_count, reset_time} ->
        Logger.warn("Rate limit exceeded", %{
          rate_type: rate_type,
          identifier: identifier,
          current_count: current_count,
          limit: config.limit,
          window: config.window,
          reset_time: reset_time
        })
        
        conn
        |> put_rate_limit_headers(rate_type, config, current_count, reset_time)
        |> put_status(:too_many_requests)
        |> json(%{
          error: "Rate limit exceeded",
          message: format_rate_limit_message(rate_type, config),
          retry_after: reset_time - System.system_time(:second),
          limit: config.limit,
          window: config.window,
          current: current_count
        })
        |> halt()
        
        {:error, :rate_limit_exceeded}
    end
  end

  defp check_global_rate_limit(conn, client_ip, config) do
    key = build_rate_limit_key(:global, :ip, client_ip, conn)
    
    case check_and_increment_rate_limit(key, config.limit, config.window) do
      {:ok, _current_count} ->
        {:ok, conn}
      
      {:error, :rate_limit_exceeded, current_count, reset_time} ->
        Logger.warn("Global rate limit exceeded", %{
          client_ip: client_ip,
          current_count: current_count,
          limit: config.limit,
          window: config.window
        })
        
        conn
        |> put_resp_header("x-ratelimit-global-limit", to_string(config.limit))
        |> put_resp_header("x-ratelimit-global-remaining", to_string(max(0, config.limit - current_count)))
        |> put_resp_header("x-ratelimit-global-reset", to_string(reset_time))
        |> put_resp_header("retry-after", to_string(reset_time - System.system_time(:second)))
        |> put_status(:too_many_requests)
        |> json(%{
          error: "Global rate limit exceeded",
          message: "Too many requests from this IP address. Please try again later.",
          retry_after: reset_time - System.system_time(:second)
        })
        |> halt()
        
        {:error, :rate_limit_exceeded}
    end
  end

  defp check_and_increment_rate_limit(key, limit, window) do
    current_time = System.system_time(:second)
    window_start = current_time - window
    
    # Clean up old entries and get current count
    cleanup_expired_entries(key, window_start)
    current_count = get_current_count(key, window_start)
    
    if current_count >= limit do
      reset_time = get_earliest_entry_time(key) + window
      {:error, :rate_limit_exceeded, current_count, reset_time}
    else
      # Increment the count
      increment_rate_limit_counter(key, current_time)
      {:ok, current_count + 1}
    end
  end

  defp build_rate_limit_key(rate_type, scope, identifier, conn) do
    case scope do
      :team -> "rate_limit:#{rate_type}:team:#{identifier}"
      :ip -> "rate_limit:#{rate_type}:ip:#{identifier}"
      :user -> "rate_limit:#{rate_type}:user:#{get_user_id(conn)}"
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip |> String.split(",") |> hd() |> String.trim()
      [] -> 
        case get_req_header(conn, "x-real-ip") do
          [ip | _] -> ip
          [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
        end
    end
  end

  defp get_user_id(conn) do
    # Extract user ID from authentication headers/session
    # For now, fallback to IP if no user authentication
    get_client_ip(conn)
  end

  # ETS-based rate limiting storage
  defp get_rate_limit_table do
    case :ets.whereis(:rate_limits) do
      :undefined ->
        :ets.new(:rate_limits, [:set, :public, :named_table, {:write_concurrency, true}])
      table -> table
    end
  end

  defp cleanup_expired_entries(key, window_start) do
    table = get_rate_limit_table()
    
    case :ets.lookup(table, key) do
      [{^key, timestamps}] ->
        valid_timestamps = Enum.filter(timestamps, fn ts -> ts >= window_start end)
        :ets.insert(table, {key, valid_timestamps})
      
      [] -> :ok
    end
  end

  defp get_current_count(key, window_start) do
    table = get_rate_limit_table()
    
    case :ets.lookup(table, key) do
      [{^key, timestamps}] ->
        timestamps
        |> Enum.filter(fn ts -> ts >= window_start end)
        |> length()
      
      [] -> 0
    end
  end

  defp get_earliest_entry_time(key) do
    table = get_rate_limit_table()
    
    case :ets.lookup(table, key) do
      [{^key, timestamps}] when length(timestamps) > 0 ->
        Enum.min(timestamps)
      
      _ -> System.system_time(:second)
    end
  end

  defp increment_rate_limit_counter(key, current_time) do
    table = get_rate_limit_table()
    
    case :ets.lookup(table, key) do
      [{^key, timestamps}] ->
        :ets.insert(table, {key, [current_time | timestamps]})
      
      [] ->
        :ets.insert(table, {key, [current_time]})
    end
  end

  defp put_rate_limit_info(conn, rate_type, current_count, config) do
    assign(conn, :rate_limit_info, %{
      type: rate_type,
      current: current_count,
      limit: config.limit,
      window: config.window
    })
  end

  defp add_rate_limit_headers(conn, rate_type, identifier) do
    config = @rate_limits[rate_type]
    key = build_rate_limit_key(rate_type, config.scope, identifier, conn)
    
    window_start = System.system_time(:second) - config.window
    current_count = get_current_count(key, window_start)
    remaining = max(0, config.limit - current_count)
    reset_time = get_earliest_entry_time(key) + config.window
    
    conn
    |> put_resp_header("x-ratelimit-limit", to_string(config.limit))
    |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
    |> put_resp_header("x-ratelimit-reset", to_string(reset_time))
    |> put_resp_header("x-ratelimit-window", to_string(config.window))
  end

  defp put_rate_limit_headers(conn, rate_type, config, current_count, reset_time) do
    remaining = max(0, config.limit - current_count)
    
    conn
    |> put_resp_header("x-ratelimit-limit", to_string(config.limit))
    |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
    |> put_resp_header("x-ratelimit-reset", to_string(reset_time))
    |> put_resp_header("x-ratelimit-window", to_string(config.window))
    |> put_resp_header("retry-after", to_string(reset_time - System.system_time(:second)))
  end

  defp format_rate_limit_message(rate_type, config) do
    case rate_type do
      :recommendations ->
        "Too many recommendation requests for this team. Limit: #{config.limit} per #{div(config.window, 60)} minutes."
      
      :status_updates ->
        "Too many status update requests for this team. Limit: #{config.limit} per #{div(config.window, 60)} minutes."
      
      :global ->
        "Too many requests from this IP address. Limit: #{config.limit} per #{div(config.window, 60)} minutes."
      
      _ ->
        "Rate limit exceeded. Limit: #{config.limit} per #{div(config.window, 60)} minutes."
    end
  end

  @doc """
  Middleware function that can be used in router pipelines for automatic rate limiting.
  
  Example usage in router:
    pipeline :api_with_rate_limiting do
      plug FantasyManagerWeb.Api.RecommendationsController, :rate_limit_middleware
    end
  """
  def rate_limit_middleware(conn, _opts) do
    # This could be used as a plug for more general rate limiting
    # For now, rate limiting is handled per-action
    conn
  end

  @doc """
  Resets rate limits for a given identifier (for testing or administrative purposes).
  """
  def reset_rate_limits(rate_type, identifier) do
    table = get_rate_limit_table()
    config = @rate_limits[rate_type]
    key = build_rate_limit_key(rate_type, config.scope, identifier, %Plug.Conn{})
    
    :ets.delete(table, key)
    :ok
  end

  @doc """
  Gets current rate limit status for debugging/monitoring.
  """
  def get_rate_limit_status(rate_type, identifier) do
    config = @rate_limits[rate_type]
    key = build_rate_limit_key(rate_type, config.scope, identifier, %Plug.Conn{})
    
    window_start = System.system_time(:second) - config.window
    current_count = get_current_count(key, window_start)
    
    %{
      rate_type: rate_type,
      identifier: identifier,
      current_count: current_count,
      limit: config.limit,
      window: config.window,
      remaining: max(0, config.limit - current_count),
      reset_time: get_earliest_entry_time(key) + config.window
    }
  end
end