defmodule FantasyManagerWeb.Api.RecommendationsController do
  use FantasyManagerWeb, :controller

  alias FantasyManager.AI.RecommendationEngine

  def optimize_lineup(conn, %{"data" => %{"attributes" => attrs}}) do
    with {:ok, team_id} <- parse_uuid(attrs["team_id"]),
         {:ok, week} <- parse_integer(attrs["week"]),
         {:ok, season} <- parse_integer(attrs["season"]) do
      
      options = build_optimization_options(attrs)
      
      case RecommendationEngine.optimize_lineup(team_id, week, season, options) do
        {:ok, result} ->
          conn
          |> put_status(:ok)
          |> render(:lineup_optimization, result: result)

        {:error, :team_not_found} ->
          conn
          |> put_status(:not_found)
          |> render(:error, error: %{code: "team_not_found", detail: "Fantasy team not found"})

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> render(:error, error: %{code: "optimization_failed", detail: inspect(reason)})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: %{code: "invalid_parameters", detail: reason})
    end
  end

  def analyze_trade(conn, %{"data" => %{"attributes" => attrs}}) do
    with {:ok, team_id} <- parse_uuid(attrs["team_id"]),
         {:ok, trade_proposal} <- parse_trade_proposal(attrs["trade_proposal"]) do
      
      options = build_trade_options(attrs)
      
      case RecommendationEngine.analyze_trade(team_id, trade_proposal, options) do
        {:ok, analysis} ->
          conn
          |> put_status(:ok)
          |> render(:trade_analysis, analysis: analysis)

        {:error, :team_not_found} ->
          conn
          |> put_status(:not_found)
          |> render(:error, error: %{code: "team_not_found", detail: "Fantasy team not found"})

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> render(:error, error: %{code: "analysis_failed", detail: inspect(reason)})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: %{code: "invalid_parameters", detail: reason})
    end
  end

  def get_projections(conn, %{"data" => %{"attributes" => attrs}}) do
    with {:ok, player_ids} <- parse_player_ids(attrs["player_ids"]),
         {:ok, week} <- parse_integer(attrs["week"]),
         {:ok, season} <- parse_integer(attrs["season"]) do
      
      case RecommendationEngine.get_enhanced_projections(player_ids, week, season) do
        {:ok, projections} ->
          conn
          |> put_status(:ok)
          |> render(:projections, projections: projections)

        {:error, reason} ->
          conn
          |> put_status(:internal_server_server_error)
          |> render(:error, error: %{code: "projections_failed", detail: inspect(reason)})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: %{code: "invalid_parameters", detail: reason})
    end
  end

  def waiver_suggestions(conn, %{"data" => %{"attributes" => attrs}}) do
    with {:ok, _team_id} <- parse_uuid(attrs["team_id"]),
         {:ok, _week} <- parse_integer(attrs["week"]),
         {:ok, _season} <- parse_integer(attrs["season"]) do
      
      _budget = attrs["budget"]
      _position_needs = attrs["position_needs"] || []
      
      # This would be implemented in the RecommendationEngine
      # For now, return a placeholder response
      suggestions = [
        %{
          player_id: "placeholder-id",
          priority: 1,
          reasoning: "Strong matchup and injury replacement opportunity",
          confidence: 0.8,
          bid_suggestion: 15
        }
      ]

      conn
      |> put_status(:ok)
      |> render(:waiver_suggestions, suggestions: suggestions)
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: %{code: "invalid_parameters", detail: reason})
    end
  end

  def keeper_recommendations(conn, %{"data" => %{"attributes" => attrs}}) do
    with {:ok, _team_id} <- parse_uuid(attrs["team_id"]),
         {:ok, _keeper_count} <- parse_integer(attrs["keeper_count"]) do
      
      _season = attrs["season"] || Date.utc_today().year + 1
      
      # This would be implemented in the RecommendationEngine
      # For now, return a placeholder response
      recommendations = [
        %{
          player_id: "placeholder-id",
          keeper_rank: 1,
          reasoning: "Elite dynasty value with years of production ahead",
          confidence: 0.9,
          value_score: 95.5
        }
      ]

      conn
      |> put_status(:ok)
      |> render(:keeper_recommendations, recommendations: recommendations)
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: %{code: "invalid_parameters", detail: reason})
    end
  end

  def test_connection(conn, _params) do
    case RecommendationEngine.test_connection() do
      {:ok, response} ->
        conn
        |> put_status(:ok)
        |> render(:connection_test, response: response)

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> render(:error, error: %{code: "ai_connection_failed", detail: inspect(reason)})
    end
  end

  # JSON rendering functions
  def render("lineup_optimization.json", %{result: result}) do
    %{
      data: %{
        type: "lineup-optimization",
        attributes: %{
          lineup: result.lineup,
          reasoning: result.reasoning,
          confidence: result.confidence,
          risk_level: result.risk_level,
          key_factors: result.key_factors
        }
      },
      jsonapi: %{version: "1.0"}
    }
  end

  def render("trade_analysis.json", %{analysis: analysis}) do
    %{
      data: %{
        type: "trade-analysis",
        attributes: %{
          recommendation: analysis.recommendation,
          analysis: analysis.analysis,
          confidence: analysis.confidence,
          value_assessment: analysis.value_assessment,
          risk_factors: analysis.risk_factors,
          suggested_counters: analysis.suggested_counters
        }
      },
      jsonapi: %{version: "1.0"}
    }
  end

  def render("projections.json", %{projections: projections}) do
    %{
      data: Enum.map(projections, fn proj ->
        %{
          type: "projection",
          attributes: %{
            player_id: proj.player_id,
            projected_points: proj.projected_points,
            confidence: proj.confidence,
            factors_considered: proj.factors_considered
          }
        }
      end),
      jsonapi: %{version: "1.0"}
    }
  end

  def render("waiver_suggestions.json", %{suggestions: suggestions}) do
    %{
      data: Enum.map(suggestions, fn suggestion ->
        %{
          type: "waiver-suggestion",
          attributes: suggestion
        }
      end),
      jsonapi: %{version: "1.0"}
    }
  end

  def render("keeper_recommendations.json", %{recommendations: recommendations}) do
    %{
      data: Enum.map(recommendations, fn rec ->
        %{
          type: "keeper-recommendation",
          attributes: rec
        }
      end),
      jsonapi: %{version: "1.0"}
    }
  end

  def render("connection_test.json", %{response: response}) do
    %{
      data: %{
        type: "connection-test",
        attributes: response
      },
      jsonapi: %{version: "1.0"}
    }
  end

  def render("error.json", %{error: error}) do
    %{
      errors: [format_error(error)],
      jsonapi: %{version: "1.0"}
    }
  end

  # Private helper functions
  defp parse_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, "Invalid UUID format"}
    end
  end
  defp parse_uuid(_), do: {:error, "UUID must be a string"}

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid integer format"}
    end
  end
  defp parse_integer(_), do: {:error, "Value must be an integer"}

  defp parse_player_ids(value) when is_list(value) do
    try do
      uuids = Enum.map(value, fn id ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> uuid
          :error -> throw(:invalid_uuid)
        end
      end)
      {:ok, uuids}
    catch
      :invalid_uuid -> {:error, "All player IDs must be valid UUIDs"}
    end
  end
  defp parse_player_ids(_), do: {:error, "Player IDs must be a list"}

  defp parse_trade_proposal(%{"give" => give, "receive" => receive}) do
    with {:ok, give_ids} <- parse_player_ids(give),
         {:ok, receive_ids} <- parse_player_ids(receive) do
      {:ok, %{give: give_ids, receive: receive_ids}}
    end
  end
  defp parse_trade_proposal(_), do: {:error, "Trade proposal must have 'give' and 'receive' player lists"}

  defp build_optimization_options(attrs) do
    options = []
    
    options = if attrs["risk_tolerance"] do
      Keyword.put(options, :risk_tolerance, attrs["risk_tolerance"])
    else
      options
    end

    options = if attrs["prioritize_ceiling"] do
      Keyword.put(options, :prioritize_ceiling, attrs["prioritize_ceiling"])
    else
      options
    end

    options = if attrs["custom_goals"] do
      Keyword.put(options, :goals, attrs["custom_goals"])
    else
      options
    end

    options
  end

  defp build_trade_options(attrs) do
    options = []
    
    options = if attrs["competitive_window"] do
      Keyword.put(options, :competitive_window, attrs["competitive_window"])
    else
      options
    end

    options = if attrs["position_needs"] do
      Keyword.put(options, :position_needs, attrs["position_needs"])
    else
      options
    end

    options
  end

  defp format_error(%{code: code, detail: detail}) do
    %{
      code: code,
      detail: detail
    }
  end

  defp format_error(error) when is_binary(error) do
    %{
      code: "internal_error",
      detail: error
    }
  end

  defp format_error(error) do
    %{
      code: "internal_error",
      detail: inspect(error)
    }
  end
end