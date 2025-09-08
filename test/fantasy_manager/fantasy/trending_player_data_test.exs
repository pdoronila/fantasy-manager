defmodule FantasyManager.Fantasy.TrendingPlayerDataTest do
  use FantasyManager.DataCase, async: true
  alias FantasyManager.Fantasy.TrendingPlayerData

  describe "TrendingPlayerData resource" do
    test "creates trending player data with valid attributes" do
      valid_attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: 150,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      assert {:ok, trending_data} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, valid_attrs)
        |> Ash.create()

      assert trending_data.player_id == "test_player_123"
      assert trending_data.player_name == "Test Player"
      assert trending_data.position == "RB"
      assert trending_data.team == "LAR"
      assert trending_data.trend_type == "add"
      assert trending_data.trend_count == 150
      assert trending_data.week == 8
      assert trending_data.season == 2024
      assert trending_data.id != nil
      assert trending_data.inserted_at != nil
      assert trending_data.updated_at != nil
    end

    test "fails to create with invalid trend_type" do
      invalid_attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        trend_type: "invalid_type",
        trend_count: 150,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      assert {:error, %Ash.Error.Invalid{}} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, invalid_attrs)
        |> Ash.create()
    end

    test "fails to create with invalid position" do
      invalid_attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "INVALID",
        trend_type: "add",
        trend_count: 150,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      assert {:error, %Ash.Error.Invalid{}} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, invalid_attrs)
        |> Ash.create()
    end

    test "fails to create with missing required fields" do
      invalid_attrs = %{
        player_name: "Test Player",
        position: "RB"
      }

      assert {:error, %Ash.Error.Invalid{}} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, invalid_attrs)
        |> Ash.create()
    end

    test "enforces unique constraint on player_id, trend_type, week, season" do
      base_attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: 150,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      # First creation should succeed
      assert {:ok, _} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, base_attrs)
        |> Ash.create()

      # Second creation with same unique fields should fail
      assert {:error, %Ash.Error.Invalid{}} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, base_attrs)
        |> Ash.create()
    end

    test "allows same player with different trend_type" do
      base_attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_count: 150,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      # Create "add" trend
      add_attrs = Map.put(base_attrs, :trend_type, "add")
      assert {:ok, add_trend} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, add_attrs)
        |> Ash.create()

      # Create "drop" trend for same player should succeed
      drop_attrs = Map.put(base_attrs, :trend_type, "drop")
      assert {:ok, drop_trend} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, drop_attrs)
        |> Ash.create()

      assert add_trend.id != drop_trend.id
      assert add_trend.trend_type == "add"
      assert drop_trend.trend_type == "drop"
    end

    test "allows same player in different weeks" do
      base_attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: 150,
        retrieved_at: ~N[2024-09-08 12:00:00],
        season: 2024
      }

      # Week 7
      week7_attrs = Map.put(base_attrs, :week, 7)
      assert {:ok, week7_trend} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, week7_attrs)
        |> Ash.create()

      # Week 8
      week8_attrs = Map.put(base_attrs, :week, 8)
      assert {:ok, week8_trend} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, week8_attrs)
        |> Ash.create()

      assert week7_trend.id != week8_trend.id
      assert week7_trend.week == 7
      assert week8_trend.week == 8
    end

    test "handles trend_count of zero" do
      attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: 0,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      assert {:ok, trending_data} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      assert trending_data.trend_count == 0
    end

    test "validates trend_count is non-negative" do
      attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: -1,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      assert {:error, %Ash.Error.Invalid{}} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
    end
  end

  describe "TrendingPlayerData queries" do
    setup do
      # Create test data
      players_data = [
        %{
          player_id: "qb_1",
          player_name: "QB One",
          position: "QB",
          team: "LAR",
          trend_type: "add",
          trend_count: 200,
          retrieved_at: ~N[2024-09-08 12:00:00],
          week: 8,
          season: 2024
        },
        %{
          player_id: "rb_1",
          player_name: "RB One",
          position: "RB",
          team: "DAL",
          trend_type: "add",
          trend_count: 150,
          retrieved_at: ~N[2024-09-08 12:00:00],
          week: 8,
          season: 2024
        },
        %{
          player_id: "rb_1",
          player_name: "RB One",
          position: "RB",
          team: "DAL",
          trend_type: "drop",
          trend_count: 50,
          retrieved_at: ~N[2024-09-08 12:00:00],
          week: 8,
          season: 2024
        },
        %{
          player_id: "wr_1",
          player_name: "WR One",
          position: "WR",
          team: "KC",
          trend_type: "add",
          trend_count: 100,
          retrieved_at: ~N[2024-09-08 12:00:00],
          week: 7,
          season: 2024
        }
      ]

      created_players = Enum.map(players_data, fn attrs ->
        {:ok, player} = TrendingPlayerData
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create()
        player
      end)

      %{players: created_players}
    end

    test "reads all trending player data", %{players: players} do
      {:ok, results} = TrendingPlayerData |> Ash.read()
      
      assert length(results) == length(players)
    end

    test "filters by trend_type" do
      {:ok, add_results} = TrendingPlayerData 
        |> Ash.Query.filter(trend_type == "add")
        |> Ash.read()
      
      assert length(add_results) == 3
      Enum.each(add_results, fn result ->
        assert result.trend_type == "add"
      end)

      {:ok, drop_results} = TrendingPlayerData 
        |> Ash.Query.filter(trend_type == "drop")
        |> Ash.read()
      
      assert length(drop_results) == 1
      assert hd(drop_results).trend_type == "drop"
    end

    test "filters by position" do
      {:ok, rb_results} = TrendingPlayerData 
        |> Ash.Query.filter(position == "RB")
        |> Ash.read()
      
      assert length(rb_results) == 2
      Enum.each(rb_results, fn result ->
        assert result.position == "RB"
      end)
    end

    test "filters by week and season" do
      {:ok, week8_results} = TrendingPlayerData 
        |> Ash.Query.filter(week == 8 and season == 2024)
        |> Ash.read()
      
      assert length(week8_results) == 3
      
      {:ok, week7_results} = TrendingPlayerData 
        |> Ash.Query.filter(week == 7 and season == 2024)
        |> Ash.read()
      
      assert length(week7_results) == 1
    end

    test "filters by player_id" do
      {:ok, rb1_results} = TrendingPlayerData 
        |> Ash.Query.filter(player_id == "rb_1")
        |> Ash.read()
      
      # Should have both add and drop trends for rb_1
      assert length(rb1_results) == 2
      
      trend_types = Enum.map(rb1_results, fn r -> r.trend_type end)
      assert "add" in trend_types
      assert "drop" in trend_types
    end

    test "sorts by trend_count descending" do
      {:ok, sorted_results} = TrendingPlayerData 
        |> Ash.Query.filter(trend_type == "add")
        |> Ash.Query.sort(trend_count: :desc)
        |> Ash.read()
      
      trend_counts = Enum.map(sorted_results, fn r -> r.trend_count end)
      assert trend_counts == [200, 150, 100]
    end

    test "limits results" do
      {:ok, limited_results} = TrendingPlayerData 
        |> Ash.Query.limit(2)
        |> Ash.read()
      
      assert length(limited_results) == 2
    end

    test "gets trending player by id" do
      {:ok, all_players} = TrendingPlayerData |> Ash.read()
      first_player = hd(all_players)
      
      {:ok, found_player} = TrendingPlayerData |> Ash.get(first_player.id)
      
      assert found_player.id == first_player.id
      assert found_player.player_id == first_player.player_id
    end
  end

  describe "TrendingPlayerData updates" do
    test "updates trend_count" do
      attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: 100,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      {:ok, trending_data} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      {:ok, updated_data} = trending_data
        |> Ash.Changeset.for_update(:update, %{trend_count: 200})
        |> Ash.update()

      assert updated_data.trend_count == 200
      assert updated_data.id == trending_data.id
    end

    test "updates retrieved_at timestamp" do
      attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: 100,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      {:ok, trending_data} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      new_retrieved_at = ~N[2024-09-08 13:00:00]

      {:ok, updated_data} = trending_data
        |> Ash.Changeset.for_update(:update, %{retrieved_at: new_retrieved_at})
        |> Ash.update()

      assert updated_data.retrieved_at == new_retrieved_at
    end
  end

  describe "TrendingPlayerData deletion" do
    test "destroys trending player data" do
      attrs = %{
        player_id: "test_player_123",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        trend_type: "add",
        trend_count: 100,
        retrieved_at: ~N[2024-09-08 12:00:00],
        week: 8,
        season: 2024
      }

      {:ok, trending_data} = TrendingPlayerData
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      assert {:ok, _} = trending_data |> Ash.destroy()

      # Verify it's been deleted
      assert {:error, %Ash.Error.Query.NotFound{}} = TrendingPlayerData |> Ash.get(trending_data.id)
    end
  end
end