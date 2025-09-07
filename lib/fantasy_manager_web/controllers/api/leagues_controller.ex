defmodule FantasyManagerWeb.Api.LeaguesController do
  use FantasyManagerWeb, :controller
  import Ash.Expr

  alias FantasyManager.Fantasy.League

  def index(conn, params) do
    query_opts = build_query_opts(params)
    
    case League.read(query_opts) do
      {:ok, leagues} ->
        conn
        |> put_status(:ok)
        |> render(:index, leagues: leagues, meta: build_meta(leagues, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def show(conn, %{"id" => id}) do
    query = League.read() |> Ash.Query.filter(expr(id == ^id)) |> Ash.Query.load([:fantasy_teams])
    
    case Ash.read_one(query) do
      {:ok, league} when not is_nil(league) ->
        conn
        |> put_status(:ok)
        |> render(:show, league: league)

      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:error, error: %{code: "not_found", detail: "League not found"})

      {:error, error} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:error, error: error)
    end
  end

  def create(conn, %{"data" => %{"attributes" => attrs}}) do
    case League.create(attrs) do
      {:ok, league} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/api/v1/leagues/#{league.id}")
        |> render(:show, league: league)

      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: error)
    end
  end

  def sync_from_sleeper(conn, %{"sleeper_id" => sleeper_id} = params) do
    full_sync = Map.get(params, "full_sync", "false") == "true"
    
    case League.sync_from_sleeper(sleeper_id, full_sync) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> render(:sync_result, result: result)

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def by_season(conn, %{"season" => season} = params) do
    season_int = String.to_integer(season)
    
    case League.by_season(season_int) do
      {:ok, leagues} ->
        conn
        |> put_status(:ok)
        |> render(:index, leagues: leagues, meta: build_meta(leagues, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def by_type(conn, %{"type" => type} = params) do
    type_atom = normalize_league_type(type)
    
    if type_atom do
      case League.by_league_type(type_atom) do
        {:ok, leagues} ->
          conn
          |> put_status(:ok)
          |> render(:index, leagues: leagues, meta: build_meta(leagues, params))

        {:error, error} ->
          conn
          |> put_status(:bad_request)
          |> render(:error, error: error)
      end
    else
      conn
      |> put_status(:bad_request)
      |> render(:error, error: %{code: "invalid_type", detail: "Invalid league type: #{type}"})
    end
  end

  def keeper_leagues(conn, params) do
    case League.keeper_leagues() do
      {:ok, leagues} ->
        conn
        |> put_status(:ok)
        |> render(:index, leagues: leagues, meta: build_meta(leagues, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def dynasty_leagues(conn, params) do
    case League.dynasty_leagues() do
      {:ok, leagues} ->
        conn
        |> put_status(:ok)
        |> render(:index, leagues: leagues, meta: build_meta(leagues, params))

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, error: error)
    end
  end

  def teams(conn, %{"id" => league_id}) do
    query = League.read() 
    |> Ash.Query.filter(expr(id == ^league_id)) 
    |> Ash.Query.load(fantasy_teams: [:roster_players])
    
    case Ash.read_one(query) do
      {:ok, league} when not is_nil(league) ->
        conn
        |> put_status(:ok)
        |> render(:teams, teams: league.fantasy_teams)

      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:error, error: %{code: "not_found", detail: "League not found"})

      {:error, error} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:error, error: error)
    end
  end

  def update(conn, %{"id" => id, "data" => %{"attributes" => attrs}}) do
    query = League.read() |> Ash.Query.filter(expr(id == ^id))
    
    case Ash.read_one(query) do
      {:ok, league} when not is_nil(league) ->
        case League.update(league, attrs) do
          {:ok, updated_league} ->
            conn
            |> put_status(:ok)
            |> render(:show, league: updated_league)

          {:error, error} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, error: error)
        end

      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> render(:error, error: %{code: "not_found", detail: "League not found"})

      {:error, error} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:error, error: error)
    end
  end

  # JSON:API rendering functions
  def render("index.json", %{leagues: leagues, meta: meta}) do
    %{
      data: Enum.map(leagues, &league_json/1),
      meta: meta,
      jsonapi: %{version: "1.0"}
    }
  end

  def render("show.json", %{league: league}) do
    %{
      data: league_json(league),
      jsonapi: %{version: "1.0"}
    }
  end

  def render("teams.json", %{teams: teams}) do
    %{
      data: Enum.map(teams, &team_json/1),
      jsonapi: %{version: "1.0"}
    }
  end

  def render("sync_result.json", %{result: result}) do
    %{
      data: %{
        type: "sync-result",
        attributes: result
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
  defp build_query_opts(params) do
    opts = []
    
    # Add pagination
    opts = if params["page"] do
      page_size = String.to_integer(params["page"]["size"] || "20")
      page_number = String.to_integer(params["page"]["number"] || "1")
      offset = (page_number - 1) * page_size
      
      Keyword.merge(opts, [limit: page_size, offset: offset])
    else
      Keyword.merge(opts, [limit: 20])
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

  defp build_meta(leagues, params) do
    count = length(leagues)
    
    page_size = try do
      String.to_integer(params["page"]["size"] || "20")
    rescue
      _ -> 20
    end
    
    page_number = try do
      String.to_integer(params["page"]["number"] || "1")
    rescue
      _ -> 1
    end

    %{
      page: %{
        current: page_number,
        size: page_size,
        total_results: count
      }
    }
  end

  defp league_json(league) do
    base_attributes = %{
      name: league.name,
      season: league.season,
      league_type: league.league_type,
      scoring_format: league.scoring_format,
      roster_size: league.roster_size,
      keeper_count: league.keeper_count,
      dynasty_transition_year: league.dynasty_transition_year,
      trade_deadline_week: league.trade_deadline_week,
      waiver_type: league.waiver_type,
      playoff_teams: league.playoff_teams,
      regular_season_weeks: league.regular_season_weeks,
      draft_type: league.draft_type,
      sleeper_id: league.sleeper_id,
      settings: league.settings,
      scoring_settings: league.scoring_settings
    }

    relationships = %{
      teams: %{
        links: %{
          related: "/api/v1/leagues/#{league.id}/teams"
        }
      }
    }

    # Add fantasy teams data if loaded
    relationships = if Map.has_key?(league, :fantasy_teams) && league.fantasy_teams != %Ash.NotLoaded{} do
      Map.put(relationships, :teams, %{
        data: Enum.map(league.fantasy_teams, fn team ->
          %{type: "fantasy-team", id: team.id}
        end),
        links: %{
          related: "/api/v1/leagues/#{league.id}/teams"
        }
      })
    else
      relationships
    end

    %{
      type: "league",
      id: league.id,
      attributes: base_attributes,
      relationships: relationships,
      links: %{
        self: "/api/v1/leagues/#{league.id}"
      }
    }
  end

  defp team_json(team) do
    %{
      type: "fantasy-team",
      id: team.id,
      attributes: %{
        name: team.name,
        owner_name: team.owner_name,
        sleeper_id: Map.get(team, :sleeper_id),
        wins: Map.get(team, :wins, 0),
        losses: Map.get(team, :losses, 0),
        ties: Map.get(team, :ties, 0),
        points_for: Map.get(team, :points_for, 0.0),
        points_against: Map.get(team, :points_against, 0.0)
      },
      relationships: %{
        roster: %{
          links: %{
            related: "/api/v1/teams/#{team.id}/roster"
          }
        }
      },
      links: %{
        self: "/api/v1/teams/#{team.id}"
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

  defp normalize_league_type(type) when is_binary(type) do
    case String.downcase(type) do
      "keeper" -> :keeper
      "dynasty" -> :dynasty
      "redraft" -> :redraft
      _ -> nil
    end
  end
end