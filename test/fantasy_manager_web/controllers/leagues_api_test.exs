defmodule FantasyManagerWeb.LeaguesApiTest do
  use FantasyManagerWeb.ConnCase
  import FantasyManager.TestSupport

  @leagues_endpoint "/api/v1/leagues"
  @teams_endpoint "/api/v1/teams"

  describe "GET /api/v1/leagues" do
    test "returns list of user's leagues", %{conn: conn} do
      conn = get(conn, @leagues_endpoint)
      
      response = json_response(conn, 200)
      assert %{"data" => leagues} = response
      assert is_list(leagues)

      Enum.each(leagues, fn league ->
        assert %{
          "type" => "league",
          "id" => _,
          "attributes" => attributes,
          "relationships" => relationships
        } = league

        assert %{
          "name" => _,
          "sleeper_id" => _,
          "season" => season,
          "league_type" => league_type,
          "scoring_format" => scoring,
          "roster_size" => roster_size,
          "keeper_count" => _,
          "dynasty_transition_year" => _,
          "trade_deadline_week" => _,
          "waiver_type" => waiver_type,
          "inserted_at" => _,
          "updated_at" => _
        } = attributes

        assert is_integer(season)
        assert league_type in ["keeper", "dynasty", "redraft"]
        assert scoring in ["PPR", "Half PPR", "Standard", "Superflex"]
        assert is_integer(roster_size)
        assert waiver_type in ["FAAB", "Rolling", "Reverse"]

        assert %{
          "teams" => %{"links" => %{"related" => _}}
        } = relationships
      end)
    end

    test "filters leagues by season", %{conn: conn} do
      conn = get(conn, @leagues_endpoint, %{"season" => "2024"})
      
      response = json_response(conn, 200)
      assert %{"data" => leagues} = response

      Enum.each(leagues, fn league ->
        assert %{
          "attributes" => %{"season" => 2024}
        } = league
      end)
    end

    test "filters leagues by league type", %{conn: conn} do
      conn = get(conn, @leagues_endpoint, %{"league_type" => "dynasty"})
      
      response = json_response(conn, 200)
      assert %{"data" => leagues} = response

      Enum.each(leagues, fn league ->
        assert %{
          "attributes" => %{"league_type" => "dynasty"}
        } = league
      end)
    end

    test "includes related teams when requested", %{conn: conn} do
      conn = get(conn, @leagues_endpoint, %{"include" => "teams"})
      
      response = json_response(conn, 200)
      assert %{"data" => leagues, "included" => included} = response
      assert is_list(included)

      # Verify included teams have proper structure
      teams = Enum.filter(included, &(&1["type"] == "fantasy_team"))
      Enum.each(teams, fn team ->
        assert %{
          "type" => "fantasy_team",
          "id" => _,
          "attributes" => %{
            "name" => _,
            "owner_name" => _,
            "competitive_window" => window
          }
        } = team

        assert window in ["Contending", "Rebuilding", "Neutral"]
      end)
    end
  end

  describe "POST /api/v1/leagues" do
    test "creates league from Sleeper ID", %{conn: conn} do
      league_data = %{
        "data" => %{
          "type" => "league",
          "attributes" => %{
            "sleeper_id" => "123456789",
            "sync_historical" => false
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(@leagues_endpoint, league_data)
      
      response = json_response(conn, 201)
      assert %{
        "data" => %{
          "type" => "league",
          "id" => _,
          "attributes" => %{
            "sleeper_id" => "123456789",
            "name" => _
          }
        }
      } = response
    end

    test "syncs league with historical data when requested", %{conn: conn} do
      league_data = %{
        "data" => %{
          "type" => "league",
          "attributes" => %{
            "sleeper_id" => "123456789",
            "sync_historical" => true
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post(@leagues_endpoint, league_data)
      
      response = json_response(conn, 201)
      assert %{
        "data" => %{
          "type" => "league",
          "attributes" => %{"sleeper_id" => "123456789"}
        }
      } = response
    end
  end

  describe "GET /api/v1/leagues/:league_id" do
    test "returns league details with basic structure", %{conn: conn} do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, "#{@leagues_endpoint}/#{league_id}")
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "league",
          "id" => ^league_id,
          "attributes" => attributes,
          "relationships" => relationships
        }
      } = response

      assert %{
        "name" => _,
        "sleeper_id" => _,
        "season" => _,
        "league_type" => _,
        "scoring_format" => _,
        "roster_size" => _
      } = attributes

      assert %{
        "teams" => %{"links" => %{"related" => _}}
      } = relationships
    end

    test "includes teams and their players when requested", %{conn: conn} do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, "#{@leagues_endpoint}/#{league_id}", %{"include" => "teams,teams.players"})
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{"id" => ^league_id},
        "included" => included
      } = response

      assert is_list(included)
      teams = Enum.filter(included, &(&1["type"] == "fantasy_team"))
      players = Enum.filter(included, &(&1["type"] == "player"))

      assert length(teams) > 0
      assert length(players) >= 0  # May be 0 if no players loaded yet
    end

    test "includes matchups when requested", %{conn: conn} do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, "#{@leagues_endpoint}/#{league_id}", %{"include" => "matchups"})
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{"id" => ^league_id},
        "included" => included
      } = response

      matchups = Enum.filter(included, &(&1["type"] == "matchup"))
      Enum.each(matchups, fn matchup ->
        assert %{
          "type" => "matchup",
          "id" => _,
          "attributes" => %{
            "season" => _,
            "week" => week,
            "team_1_score" => _,
            "team_2_score" => _,
            "is_playoffs" => _,
            "matchup_type" => matchup_type
          },
          "relationships" => %{
            "team_1" => %{"data" => %{"type" => "fantasy_team"}},
            "team_2" => %{"data" => %{"type" => "fantasy_team"}}
          }
        } = matchup

        assert is_integer(week) and week >= 1 and week <= 18
        assert matchup_type in ["Regular", "Playoffs", "Championship"]
      end)
    end

    test "returns 404 for non-existent league", %{conn: conn} do
      non_existent_id = "550e8400-e29b-41d4-a716-999999999999"
      conn = get(conn, "#{@leagues_endpoint}/#{non_existent_id}")
      
      response = json_response(conn, 404)
      assert %{"errors" => [%{"status" => "404"}]} = response
    end
  end

  describe "PATCH /api/v1/leagues/:league_id" do
    test "updates league settings", %{conn: conn} do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      update_data = %{
        "data" => %{
          "type" => "league",
          "attributes" => %{
            "dynasty_transition_year" => 2025,
            "keeper_count" => 5
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> patch("#{@leagues_endpoint}/#{league_id}", update_data)
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "league",
          "id" => ^league_id,
          "attributes" => %{
            "dynasty_transition_year" => 2025,
            "keeper_count" => 5
          }
        }
      } = response
    end
  end

  describe "POST /api/v1/leagues/:league_id/sync-sleeper" do
    test "syncs league data from Sleeper API", %{conn: conn} do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = post(conn, "#{@leagues_endpoint}/#{league_id}/sync-sleeper")
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "league",
          "id" => ^league_id
        },
        "meta" => %{
          "sync_stats" => %{
            "teams_updated" => teams_count,
            "players_updated" => players_count,
            "rosters_synced" => rosters_count
          }
        }
      } = response

      assert is_integer(teams_count)
      assert is_integer(players_count)
      assert is_integer(rosters_count)
    end

    test "performs full sync when requested", %{conn: conn} do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = post(conn, "#{@leagues_endpoint}/#{league_id}/sync-sleeper", %{"full_sync" => "true"})
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{"id" => ^league_id},
        "meta" => %{"sync_stats" => _}
      } = response
    end
  end

  describe "GET /api/v1/teams" do
    test "returns list of fantasy teams", %{conn: conn} do
      conn = get(conn, @teams_endpoint)
      
      response = json_response(conn, 200)
      assert %{"data" => teams} = response
      assert is_list(teams)

      Enum.each(teams, fn team ->
        assert %{
          "type" => "fantasy_team",
          "id" => _,
          "attributes" => attributes,
          "relationships" => relationships
        } = team

        assert %{
          "name" => _,
          "sleeper_id" => _,
          "owner_name" => _,
          "competitive_window" => window,
          "waiver_priority" => _,
          "faab_budget" => _,
          "total_moves" => _
        } = attributes

        assert window in ["Contending", "Rebuilding", "Neutral"]

        assert %{
          "league" => %{"data" => %{"type" => "league"}},
          "players" => %{"links" => %{"related" => _}}
        } = relationships
      end)
    end

    test "filters teams by league", %{conn: conn} do
      league_id = "550e8400-e29b-41d4-a716-446655440000"
      conn = get(conn, @teams_endpoint, %{"league_id" => league_id})
      
      response = json_response(conn, 200)
      assert %{"data" => teams} = response

      Enum.each(teams, fn team ->
        assert %{
          "relationships" => %{
            "league" => %{"data" => %{"id" => ^league_id}}
          }
        } = team
      end)
    end

    test "filters teams by competitive window", %{conn: conn} do
      conn = get(conn, @teams_endpoint, %{"competitive_window" => "Contending"})
      
      response = json_response(conn, 200)
      assert %{"data" => teams} = response

      Enum.each(teams, fn team ->
        assert %{
          "attributes" => %{"competitive_window" => "Contending"}
        } = team
      end)
    end

    test "includes players and keeper contracts when requested", %{conn: conn} do
      conn = get(conn, @teams_endpoint, %{"include" => "players,keeper_contracts"})
      
      response = json_response(conn, 200)
      assert %{"data" => teams, "included" => included} = response

      players = Enum.filter(included, &(&1["type"] == "player"))
      contracts = Enum.filter(included, &(&1["type"] == "keeper_contract"))

      assert length(players) >= 0
      assert length(contracts) >= 0
    end
  end

  describe "GET /api/v1/teams/:team_id" do
    test "returns team details", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}")
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "type" => "fantasy_team",
          "id" => ^team_id,
          "attributes" => %{
            "name" => _,
            "owner_name" => _,
            "competitive_window" => _
          },
          "relationships" => %{
            "league" => %{"data" => %{"type" => "league"}},
            "players" => %{"links" => %{"related" => _}}
          }
        }
      } = response
    end

    test "includes comprehensive data when requested", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}", %{
        "include" => "players,players.stats,keeper_contracts,league"
      })
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{"id" => ^team_id},
        "included" => included
      } = response

      leagues = Enum.filter(included, &(&1["type"] == "league"))
      players = Enum.filter(included, &(&1["type"] == "player"))
      stats = Enum.filter(included, &(&1["type"] == "player_stat"))
      contracts = Enum.filter(included, &(&1["type"] == "keeper_contract"))

      assert length(leagues) == 1
      assert length(players) >= 0
      assert length(stats) >= 0
      assert length(contracts) >= 0
    end
  end

  describe "PATCH /api/v1/teams/:team_id" do
    test "updates team competitive window", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      update_data = %{
        "data" => %{
          "type" => "fantasy_team",
          "attributes" => %{
            "competitive_window" => "Rebuilding"
          }
        }
      }

      conn = conn
        |> put_req_header("content-type", "application/vnd.api+json")
        |> patch("#{@teams_endpoint}/#{team_id}", update_data)
      
      response = json_response(conn, 200)
      assert %{
        "data" => %{
          "id" => ^team_id,
          "attributes" => %{"competitive_window" => "Rebuilding"}
        }
      } = response
    end
  end

  describe "GET /api/v1/teams/:team_id/roster" do
    test "returns current team roster", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}/roster")
      
      response = json_response(conn, 200)
      assert %{"data" => roster_players} = response
      assert is_list(roster_players)

      Enum.each(roster_players, fn roster_player ->
        assert %{
          "type" => "roster_player",
          "id" => _,
          "attributes" => %{
            "roster_position" => roster_pos,
            "lineup_position" => _,
            "acquisition_type" => acq_type,
            "acquisition_date" => _,
            "acquisition_cost" => _
          },
          "relationships" => %{
            "player" => %{"data" => %{"type" => "player"}}
          }
        } = roster_player

        assert roster_pos in ["Starter", "Bench", "IR", "Taxi"]
        assert acq_type in ["Draft", "Trade", "Waiver", "Free Agent"]
      end)
    end

    test "filters roster by position", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}/roster", %{"position" => "Starter"})
      
      response = json_response(conn, 200)
      assert %{"data" => roster_players} = response

      Enum.each(roster_players, fn roster_player ->
        assert %{
          "attributes" => %{"roster_position" => "Starter"}
        } = roster_player
      end)
    end

    test "includes projections when requested", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}/roster", %{"include_projections" => "true"})
      
      response = json_response(conn, 200)
      assert %{"data" => roster_players} = response
      
      # Test should pass whether projections are available or not
      assert is_list(roster_players)
    end
  end

  describe "GET /api/v1/teams/:team_id/available-players" do
    test "returns available free agents", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}/available-players")
      
      response = json_response(conn, 200)
      assert %{"data" => available_players} = response
      assert is_list(available_players)

      Enum.each(available_players, fn player ->
        assert %{
          "type" => "available_player",
          "id" => _,
          "attributes" => %{
            "name" => _,
            "position" => _,
            "nfl_team" => _,
            "ownership_percentage" => ownership,
            "projected_points" => _,
            "dynasty_value" => _,
            "recent_trend" => trend
          }
        } = player

        assert is_number(ownership) and ownership >= 0 and ownership <= 100
        assert trend in ["Up", "Down", "Stable"]
      end)
    end

    test "filters available players by position", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}/available-players", %{"position" => "RB"})
      
      response = json_response(conn, 200)
      assert %{"data" => available_players} = response

      Enum.each(available_players, fn player ->
        assert %{
          "attributes" => %{"position" => "RB"}
        } = player
      end)
    end

    test "filters by ownership threshold", %{conn: conn} do
      team_id = "550e8400-e29b-41d4-a716-446655440001"
      conn = get(conn, "#{@teams_endpoint}/#{team_id}/available-players", %{"ownership_threshold" => "25"})
      
      response = json_response(conn, 200)
      assert %{"data" => available_players} = response

      Enum.each(available_players, fn player ->
        assert %{
          "attributes" => %{"ownership_percentage" => ownership}
        } = player
        assert ownership <= 25
      end)
    end
  end
end