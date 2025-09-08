defmodule FantasyManagerWeb.PlayersApiTest do
  use FantasyManagerWeb.ConnCase
  import FantasyManager.TestSupport

  @players_endpoint "/api/v1/players"

  describe "GET /api/v1/players" do
    test "returns list of players in JSON:API format", %{conn: conn} do
      conn = get(conn, @players_endpoint)
      
      assert %{
        "data" => players,
        "meta" => meta
      } = json_response(conn, 200)

      assert is_list(players)
      assert %{"page" => page_info} = meta
      assert %{"total" => _, "size" => _, "offset" => _} = page_info
    end

    test "filters players by position", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"position" => "QB"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      Enum.each(players, fn player ->
        assert %{
          "type" => "player",
          "attributes" => %{"position" => "QB"}
        } = player
      end)
    end

    test "filters players by injury status", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"injury_status" => "Active"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      Enum.each(players, fn player ->
        assert %{
          "type" => "player",
          "attributes" => %{"injury_status" => "Active"}
        } = player
      end)
    end

    test "filters players by nfl team", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"nfl_team" => "BUF"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      Enum.each(players, fn player ->
        assert %{
          "type" => "player",
          "attributes" => %{"nfl_team" => "BUF"}
        } = player
      end)
    end

    test "filters players by dynasty value range", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"dynasty_value_min" => "50", "dynasty_value_max" => "100"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      Enum.each(players, fn player ->
        assert %{
          "type" => "player",
          "attributes" => %{"dynasty_value" => value}
        } = player
        assert value >= 50 and value <= 100
      end)
    end

    test "supports pagination with page[size] and page[offset]", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"page[size]" => "5", "page[offset]" => "10"})
      
      response = json_response(conn, 200)
      assert %{
        "data" => players,
        "meta" => %{"page" => %{"size" => 5, "offset" => 10}}
      } = response
      
      assert length(players) <= 5
    end

    test "supports sorting by dynasty_value", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"sort" => "dynasty_value"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      dynasty_values = Enum.map(players, fn player ->
        player["attributes"]["dynasty_value"]
      end)
      
      assert dynasty_values == Enum.sort(dynasty_values)
    end

    test "supports sorting by dynasty_value descending", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"sort" => "-dynasty_value"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      dynasty_values = Enum.map(players, fn player ->
        player["attributes"]["dynasty_value"]
      end)
      
      assert dynasty_values == Enum.sort(dynasty_values, :desc)
    end

    test "returns proper JSON:API structure for each player", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"page[size]" => "1"})
      
      response = json_response(conn, 200)
      assert %{"data" => [player]} = response
      
      assert %{
        "type" => "player",
        "id" => _,
        "attributes" => attributes,
        "relationships" => relationships
      } = player

      assert %{
        "name" => _,
        "position" => position,
        "nfl_team" => _,
        "injury_status" => _,
        "age" => _,
        "years_pro" => _,
        "dynasty_value" => _,
        "keeper_eligible" => _,
        "sleeper_id" => _,
        "inserted_at" => _,
        "updated_at" => _
      } = attributes

      assert position in ["QB", "RB", "WR", "TE", "K", "DEF"]

      assert %{
        "stats" => %{"links" => %{"related" => _}},
        "projections" => %{"links" => %{"related" => _}}
      } = relationships
    end

    test "returns 400 for invalid query parameters", %{conn: conn} do
      conn = get(conn, @players_endpoint, %{"position" => "INVALID"})
      
      response = json_response(conn, 400)
      assert %{
        "errors" => [%{
          "title" => _,
          "detail" => _,
          "status" => "400"
        }]
      } = response
    end
  end

  describe "POST /api/v1/players" do
    test "creates a new player with valid data", %{conn: conn} do
      player_data = %{
        "data" => %{
          "type" => "player",
          "attributes" => %{
            "name" => "Test Player",
            "position" => "QB",
            "nfl_team" => "BUF",
            "sleeper_id" => "1234",
            "dynasty_value" => 75.0
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(@players_endpoint, player_data)
      
      response = json_response(conn, 201)
      assert %{
        "data" => %{
          "type" => "player",
          "id" => _,
          "attributes" => %{
            "name" => "Test Player",
            "position" => "QB"
          }
        }
      } = response
    end

    test "returns 422 for invalid player data", %{conn: conn} do
      invalid_data = %{
        "data" => %{
          "type" => "player",
          "attributes" => %{
            "position" => "QB"
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(@players_endpoint, invalid_data)
      
      response = json_response(conn, 422)
      assert %{
        "errors" => [%{
          "title" => "Validation Error",
          "status" => "422",
          "source" => %{"pointer" => "/data/attributes/name"}
        }]
      } = response
    end
  end

  describe "GET /api/v1/players/:player_id" do
    test "returns player details with relationships", %{conn: conn} do
      player_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, "#{@players_endpoint}/#{player_id}", %{"include" => "stats,projections"})
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "player",
          "id" => ^player_id,
          "attributes" => _,
          "relationships" => _
        },
        "included" => included
      } = response

      assert is_list(included)
    end

    test "returns 404 for non-existent player", %{conn: conn} do
      non_existent_id = "550e8400-e29b-41d4-a716-999999999999"
      conn = get(conn, "#{@players_endpoint}/#{non_existent_id}")
      
      response = json_response(conn, 404)
      assert %{
        "errors" => [%{
          "title" => _,
          "detail" => _,
          "status" => "404"
        }]
      } = response
    end
  end

  describe "PATCH /api/v1/players/:player_id" do
    test "updates player with valid data", %{conn: conn} do
      player_id = "550e8400-e29b-41d4-a716-446655440000"
      update_data = %{
        "data" => %{
          "type" => "player",
          "attributes" => %{
            "injury_status" => "Questionable",
            "dynasty_value" => 80.0
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> patch("#{@players_endpoint}/#{player_id}", update_data)
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "player",
          "id" => ^player_id,
          "attributes" => %{
            "injury_status" => "Questionable",
            "dynasty_value" => 80.0
          }
        }
      } = response
    end
  end

  describe "POST /api/v1/players/:player_id/sync-sleeper" do
    test "syncs player data from Sleeper API", %{conn: conn} do
      player_id = "550e8400-e29b-41d4-a716-446655440000"
      
      conn = post(conn, "#{@players_endpoint}/#{player_id}/sync-sleeper")
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "player",
          "id" => ^player_id
        }
      } = response
    end

    test "returns 502 when Sleeper API unavailable", %{conn: conn} do
      player_id = "550e8400-e29b-41d4-a716-446655440000"
      
      conn = post(conn, "#{@players_endpoint}/#{player_id}/sync-sleeper")
      
      response = json_response(conn, 502)
      assert %{
        "errors" => [%{
          "title" => _,
          "detail" => _,
          "status" => "502"
        }]
      } = response
    end
  end

  describe "GET /api/v1/players/search" do
    test "searches players by name", %{conn: conn} do
      conn = get(conn, "#{@players_endpoint}/search", %{"q" => "Josh"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      Enum.each(players, fn player ->
        assert %{
          "type" => "player",
          "attributes" => %{"name" => name}
        } = player
        assert String.contains?(String.downcase(name), "josh")
      end)
    end

    test "limits search results", %{conn: conn} do
      conn = get(conn, "#{@players_endpoint}/search", %{"q" => "player", "limit" => "3"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      assert length(players) <= 3
    end

    test "filters search by position", %{conn: conn} do
      conn = get(conn, "#{@players_endpoint}/search", %{"q" => "Josh", "position" => "QB"})
      
      response = json_response(conn, 200)
      assert %{"data" => players} = response
      
      Enum.each(players, fn player ->
        assert %{
          "type" => "player",
          "attributes" => %{"position" => "QB"}
        } = player
      end)
    end

    test "requires minimum query length", %{conn: conn} do
      conn = get(conn, "#{@players_endpoint}/search", %{"q" => "J"})
      
      response = json_response(conn, 400)
      assert %{
        "errors" => [%{
          "title" => _,
          "detail" => _,
          "status" => "400"
        }]
      } = response
    end
  end
end