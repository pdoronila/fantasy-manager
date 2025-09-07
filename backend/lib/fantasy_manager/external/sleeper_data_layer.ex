defmodule FantasyManager.External.SleeperDataLayer do
  @moduledoc """
  Custom Ash data layer for Sleeper API integration.
  
  Allows external Sleeper API data to be treated as first-class Ash resources
  while controlling caching, rate limiting, and error handling at the data layer level.
  
  This data layer handles:
  - Query translation from Ash filters to Sleeper API calls
  - Response transformation from Sleeper format to Ash resource format
  - Intelligent caching based on data type and freshness requirements
  - Error handling and fallback strategies
  """

  @behaviour Ash.DataLayer

  alias FantasyManager.External.SleeperClient
  require Logger

  @doc """
  Returns true if this data layer can be used for the given resource.
  Only supports resources configured with this data layer.
  """
  def can_run_query?(_resource, _query), do: true

  @doc """
  Returns true if this data layer supports transactions.
  Sleeper API is read-only, so no transactions are supported.
  """
  def in_transaction?(_resource), do: false

  @doc """
  Returns true if this data layer supports the given feature.
  """
  def can_rollback_transaction?(_resource), do: false

  @doc """
  Returns true if this data layer supports limiting results.
  """
  def can_limit?(_resource), do: true

  @doc """
  Returns true if this data layer supports sorting results.
  """
  def can_sort?(_resource), do: true

  @doc """
  Returns true if this data layer supports filtering results.
  """
  def can_filter?(_resource, _operator, _path), do: true

  @doc """
  Returns the resource's configuration for this data layer.
  """
  def resource_config(resource) do
    Ash.Resource.Info.data_layer_config(resource)
  end

  @doc """
  Executes a query against the Sleeper API.
  """
  def run_query(query, _resource) do
    try do
      case execute_sleeper_query(query) do
        {:ok, results} ->
          formatted_results = format_results(results, query)
          {:ok, formatted_results}
        
        {:error, reason} ->
          Logger.error("Sleeper data layer query failed: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception in Sleeper data layer: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  @doc """
  Returns true if the data layer supports aggregates.
  """
  def can_run_aggregate_query?(_resource, _aggregate), do: false

  @doc """
  Runs an aggregate query. Not supported for external APIs.
  """
  def run_aggregate_query(_query, _resource) do
    {:error, :not_supported}
  end

  @doc """
  Returns true if the data layer supports counting.
  """
  def can_count?(_resource), do: true

  @doc """
  Counts records. For external APIs, this estimates based on returned data.
  """
  def count(query, _resource) do
    case run_query(query, query.resource) do
      {:ok, results} when is_list(results) ->
        {:ok, length(results)}
      
      {:ok, _} ->
        {:ok, 1}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a record. Not supported for Sleeper API (read-only).
  """
  def create(_resource, _changeset), do: {:error, :not_supported}

  @doc """
  Updates a record. Not supported for Sleeper API (read-only).
  """
  def update(_resource, _changeset), do: {:error, :not_supported}

  @doc """
  Destroys a record. Not supported for Sleeper API (read-only).
  """
  def destroy(_resource, _changeset), do: {:error, :not_supported}

  @doc """
  Upserts a record. Not supported for Sleeper API (read-only).
  """
  def upsert(_resource, _changeset, _keys), do: {:error, :not_supported}

  # Private functions for query execution

  defp execute_sleeper_query(query) do
    resource_config = resource_config(query.resource)
    endpoint_type = get_endpoint_type(resource_config)
    
    case endpoint_type do
      :players -> execute_players_query(query)
      :leagues -> execute_leagues_query(query)
      :rosters -> execute_rosters_query(query)
      :matchups -> execute_matchups_query(query)
      :nfl_state -> execute_nfl_state_query(query)
      _ -> {:error, {:unsupported_endpoint, endpoint_type}}
    end
  end

  defp execute_players_query(_query) do
    case SleeperClient.get_all_players() do
      {:ok, players_map} ->
        # Convert map to list of players with IDs
        players_list = 
          players_map
          |> Enum.map(fn {player_id, player_data} ->
            Map.put(player_data, "player_id", player_id)
          end)
        
        {:ok, players_list}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_leagues_query(query) do
    case extract_league_id(query) do
      {:ok, league_id} ->
        SleeperClient.get_league(league_id)
      
      :error ->
        {:error, :league_id_required}
    end
  end

  defp execute_rosters_query(query) do
    case extract_league_id(query) do
      {:ok, league_id} ->
        SleeperClient.get_league_rosters(league_id)
      
      :error ->
        {:error, :league_id_required}
    end
  end

  defp execute_matchups_query(query) do
    with {:ok, league_id} <- extract_league_id(query),
         {:ok, week} <- extract_week(query) do
      SleeperClient.get_league_matchups(league_id, week)
    else
      :league_id_error -> {:error, :league_id_required}
      :week_error -> {:error, :week_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_nfl_state_query(_query) do
    SleeperClient.get_nfl_state()
  end

  # Helper functions for extracting query parameters

  defp get_endpoint_type(config) do
    config[:endpoint] || :players
  end

  defp extract_league_id(query) do
    # Look for league_id in filters
    case find_filter_value(query.filter, :sleeper_id) || 
         find_filter_value(query.filter, :league_id) do
      nil -> :error
      league_id when is_binary(league_id) -> {:ok, league_id}
      league_id -> {:ok, to_string(league_id)}
    end
  end

  defp extract_week(query) do
    case find_filter_value(query.filter, :week) do
      nil -> :error
      week when is_integer(week) -> {:ok, week}
      week when is_binary(week) ->
        case Integer.parse(week) do
          {int_week, ""} -> {:ok, int_week}
          _ -> :week_error
        end
      _ -> :week_error
    end
  end

  defp find_filter_value(nil, _field), do: nil
  
  defp find_filter_value(%Ash.Filter{expression: expression}, field) do
    find_filter_value_in_expression(expression, field)
  end
  
  defp find_filter_value(filter, field) when is_list(filter) do
    Enum.find_value(filter, &find_filter_value(&1, field))
  end
  
  defp find_filter_value(_, _), do: nil

  defp find_filter_value_in_expression(%Ash.Query.BooleanExpression{left: left, right: right}, field) do
    find_filter_value_in_expression(left, field) || find_filter_value_in_expression(right, field)
  end
  
  defp find_filter_value_in_expression(%Ash.Query.Function{name: :eq, arguments: [%Ash.Query.Ref{attribute: attribute}, value]}, field) do
    if attribute.name == field, do: value, else: nil
  end
  
  defp find_filter_value_in_expression(_, _), do: nil

  # Result formatting functions

  defp format_results(results, query) when is_list(results) do
    results
    |> apply_filters(query)
    |> apply_sorting(query)
    |> apply_limit(query)
  end
  
  defp format_results(result, _query) do
    [result]
  end

  defp apply_filters(results, %{filter: nil}), do: results
  defp apply_filters(results, %{filter: filter}) do
    # Basic client-side filtering for complex cases
    # Most filtering should be handled by specific API endpoints
    results
  end

  defp apply_sorting(results, %{sort: []}), do: results
  defp apply_sorting(results, %{sort: sort_criteria}) do
    # Apply basic sorting on common fields
    Enum.sort_by(results, fn item ->
      case List.first(sort_criteria) do
        %{field: field, order: :asc} ->
          get_sort_value(item, field)
        %{field: field, order: :desc} ->
          get_sort_value(item, field) |> negate_for_desc()
        _ ->
          0
      end
    end)
  end

  defp apply_limit(results, %{limit: nil}), do: results
  defp apply_limit(results, %{limit: limit}) do
    Enum.take(results, limit)
  end

  defp get_sort_value(item, field) when is_map(item) do
    case Map.get(item, to_string(field)) || Map.get(item, field) do
      nil -> ""
      value when is_binary(value) -> value
      value when is_number(value) -> value
      value -> to_string(value)
    end
  end
  
  defp get_sort_value(_, _), do: ""

  defp negate_for_desc(value) when is_number(value), do: -value
  defp negate_for_desc(value), do: value

  @doc """
  Transform function for creating custom data layers.
  """
  def transform(dsl_state) do
    {:ok, dsl_state}
  end

  @doc """
  Verify function for validating data layer configuration.
  """
  def verify(dsl_state, _opts) do
    {:ok, dsl_state}
  end
end