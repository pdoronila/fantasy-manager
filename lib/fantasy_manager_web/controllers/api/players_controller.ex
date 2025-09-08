defmodule FantasyManagerWeb.Api.PlayersController do
  use FantasyManagerWeb, :controller
  import Ash.Expr

  alias FantasyManager.Fantasy.Player

  def index(conn, params) do
    # Handle filtering and search parameters
    query_opts = build_query_opts(params)
    
    case Player.read(query_opts) do
      {:ok, players} ->
        # Extract the actual player list for rendering
        player_list = case players do
          %Ash.Page.Offset{results: results} -> results
          results when is_list(results) -> results
          _ -> []
        end
        
        conn
        |> put_status(:ok)
        |> render(:index, players: player_list, meta: build_meta(players, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def show(conn, %{"id" => id}) do
    case Player.read() |> Ash.Query.filter(expr(id == ^id)) |> Ash.read_one() do
      {:ok, player} when not is_nil(player) ->
        conn
        |> put_status(:ok)
        |> render(:show, player: player)

      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:error, error: %{code: "not_found", detail: "Player not found"})

      {:error, error} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:error, error: error)
    end
  end

  def search(conn, %{"q" => query} = params) do
    search_term = "%#{query}%"
    
    case Player.search(search_term) do
      {:ok, players} ->
        conn
        |> put_status(:ok)
        |> render(:index, players: players, meta: build_meta(players, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def by_position(conn, %{"position" => position} = params) do
    position_atom = normalize_position(position)
    
    if position_atom do
      case Player.by_position(position_atom) do
        {:ok, players} ->
          conn
          |> put_status(:ok)
          |> render(:index, players: players, meta: build_meta(players, params))

        {:error, error} ->
          conn
          |> put_status(:bad_request)
          |> render(:error, error: error)
      end
    else
      conn
      |> put_status(:bad_request)
      |> render(:error, error: %{code: "invalid_position", detail: "Invalid position: #{position}"})
    end
  end

  def dynasty_prospects(conn, params) do
    min_value = String.to_float(params["min_value"] || "50.0")
    max_age = String.to_integer(params["max_age"] || "26")

    case Player.dynasty_prospects(min_value, max_age) do
      {:ok, players} ->
        conn
        |> put_status(:ok)
        |> render(:index, players: players, meta: build_meta(players, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def injury_report(conn, params) do
    case Player.injury_report() do
      {:ok, players} ->
        conn
        |> put_status(:ok)
        |> render(:index, players: players, meta: build_meta(players, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  # JSON:API rendering functions
  def render("index.json", %{players: players, meta: meta}) do
    %{
      data: Enum.map(players, &player_json/1),
      meta: meta,
      jsonapi: %{version: "1.0"}
    }
  end

  def render("show.json", %{player: player}) do
    %{
      data: player_json(player),
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
  defp build_query_opts(params) do
    opts = []
    
    # Add pagination using page with limit
    opts = if params["page"] do
      page_size = String.to_integer(params["page"]["size"] || "20")
      Keyword.merge(opts, [page: [limit: page_size]])
    else
      Keyword.merge(opts, [page: [limit: 20]])
    end

    # Add sorting
    opts = if params["sort"] do
      sort_field = String.to_atom(params["sort"])
      Keyword.merge(opts, [sort: [sort_field]])
    else
      opts
    end

    opts
  end

  defp build_meta(players, params) do
    # Handle Ash pagination result
    {count, results} = case players do
      %Ash.Page.Offset{results: results, count: count} -> {count, results}
      results when is_list(results) -> {length(results), results}
      _ -> {0, []}
    end
    
    page_size = String.to_integer(params["page"]["size"] || "20")
    page_number = String.to_integer(params["page"]["number"] || "1")

    %{
      page: %{
        current: page_number,
        size: page_size,
        total_results: count
      }
    }
  end

  defp player_json(player) do
    %{
      type: "player",
      id: player.id,
      attributes: %{
        name: player.name,
        position: player.position,
        nfl_team: player.nfl_team,
        injury_status: player.injury_status,
        age: player.age,
        years_pro: player.years_pro,
        dynasty_value: player.dynasty_value,
        keeper_eligible: player.keeper_eligible,
        status: player.status,
        sleeper_id: player.sleeper_id,
        rookie_year: player.rookie_year
      },
      relationships: %{
        projections: %{
          links: %{
            related: "/api/v1/players/#{player.id}/projections"
          }
        },
        stats: %{
          links: %{
            related: "/api/v1/players/#{player.id}/stats"
          }
        }
      },
      links: %{
        self: "/api/v1/players/#{player.id}"
      }
    }
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

  defp normalize_position(position) when is_binary(position) do
    case String.upcase(position) do
      "QB" -> :QB
      "RB" -> :RB
      "WR" -> :WR
      "TE" -> :TE
      "K" -> :K
      "DEF" -> :DEF
      _ -> nil
    end
  end
end