defmodule FantasyManager.Fantasy.WaiverRecommendationTest do
  use FantasyManager.DataCase, async: true
  alias FantasyManager.Fantasy.WaiverRecommendation

  describe "WaiverRecommendation resource" do
    test "creates waiver recommendation with valid attributes" do
      valid_attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        team: "LAR",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Strong waiver pickup due to increased usage and favorable matchups",
        status: "pending",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00],
        expires_at: ~N[2024-09-15 12:00:00]
      }

      assert {:ok, recommendation} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, valid_attrs)
        |> Ash.create()

      assert recommendation.team_id == "team_123"
      assert recommendation.player_id == "player_456"
      assert recommendation.player_name == "Test Player"
      assert recommendation.position == "RB"
      assert recommendation.team == "LAR"
      assert recommendation.recommendation_type == "pickup"
      assert Decimal.equal?(recommendation.priority_score, Decimal.new("8.5"))
      assert recommendation.reasoning == "Strong waiver pickup due to increased usage and favorable matchups"
      assert recommendation.status == "pending"
      assert recommendation.week == 8
      assert recommendation.season == 2024
      assert recommendation.id != nil
      assert recommendation.inserted_at != nil
      assert recommendation.updated_at != nil
    end

    test "uses default status 'pending' when not specified" do
      attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      assert {:ok, recommendation} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      assert recommendation.status == "pending"
    end

    test "fails to create with invalid recommendation_type" do
      invalid_attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "invalid_type",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      assert {:error, %Ash.Error.Invalid{}} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, invalid_attrs)
        |> Ash.create()
    end

    test "fails to create with invalid status" do
      invalid_attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        status: "invalid_status",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      assert {:error, %Ash.Error.Invalid{}} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, invalid_attrs)
        |> Ash.create()
    end

    test "fails to create with invalid position" do
      invalid_attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "INVALID",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      assert {:error, %Ash.Error.Invalid{}} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, invalid_attrs)
        |> Ash.create()
    end

    test "validates priority_score bounds" do
      # Test negative priority score
      negative_attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: -1.0,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      assert {:error, %Ash.Error.Invalid{}} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, negative_attrs)
        |> Ash.create()

      # Test priority score over 10
      high_attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 11.0,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      assert {:error, %Ash.Error.Invalid{}} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, high_attrs)
        |> Ash.create()

      # Test valid boundary values
      min_attrs = Map.put(negative_attrs, :priority_score, 0.0)
      assert {:ok, _} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, min_attrs)
        |> Ash.create()

      max_attrs = Map.put(high_attrs, :priority_score, 10.0)
      assert {:ok, _} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, max_attrs)
        |> Ash.create()
    end

    test "validates reasoning is not empty" do
      attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      assert {:error, %Ash.Error.Invalid{}} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
    end

    test "fails to create with missing required fields" do
      incomplete_attrs = %{
        team_id: "team_123",
        player_name: "Test Player",
        position: "RB"
      }

      assert {:error, %Ash.Error.Invalid{}} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, incomplete_attrs)
        |> Ash.create()
    end
  end

  describe "WaiverRecommendation queries" do
    setup do
      # Create test recommendations
      recommendations_data = [
        %{
          team_id: "team_123",
          player_id: "qb_1",
          player_name: "QB One",
          position: "QB",
          team: "LAR",
          recommendation_type: "pickup",
          priority_score: 9.0,
          reasoning: "Elite QB pickup for immediate impact",
          status: "pending",
          week: 8,
          season: 2024,
          generated_at: ~N[2024-09-08 12:00:00]
        },
        %{
          team_id: "team_123",
          player_id: "rb_1",
          player_name: "RB One",
          position: "RB",
          team: "DAL",
          recommendation_type: "pickup",
          priority_score: 7.5,
          reasoning: "Solid RB depth pickup",
          status: "applied",
          week: 8,
          season: 2024,
          generated_at: ~N[2024-09-08 12:00:00]
        },
        %{
          team_id: "team_123",
          player_id: "wr_1",
          player_name: "WR One",
          position: "WR",
          team: "KC",
          recommendation_type: "drop",
          priority_score: 3.0,
          reasoning: "Consider dropping for better options",
          status: "dismissed",
          week: 8,
          season: 2024,
          generated_at: ~N[2024-09-08 12:00:00]
        },
        %{
          team_id: "team_456",
          player_id: "te_1",
          player_name: "TE One",
          position: "TE",
          team: "SF",
          recommendation_type: "pickup",
          priority_score: 6.0,
          reasoning: "TE streaming option",
          status: "pending",
          week: 8,
          season: 2024,
          generated_at: ~N[2024-09-08 12:00:00]
        }
      ]

      created_recommendations = Enum.map(recommendations_data, fn attrs ->
        {:ok, rec} = WaiverRecommendation
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create()
        rec
      end)

      %{recommendations: created_recommendations}
    end

    test "reads all recommendations", %{recommendations: recommendations} do
      {:ok, results} = WaiverRecommendation |> Ash.read()
      
      assert length(results) == length(recommendations)
    end

    test "filters by team_id" do
      {:ok, team123_results} = WaiverRecommendation 
        |> Ash.Query.filter(team_id == "team_123")
        |> Ash.read()
      
      assert length(team123_results) == 3
      Enum.each(team123_results, fn result ->
        assert result.team_id == "team_123"
      end)

      {:ok, team456_results} = WaiverRecommendation 
        |> Ash.Query.filter(team_id == "team_456")
        |> Ash.read()
      
      assert length(team456_results) == 1
      assert hd(team456_results).team_id == "team_456"
    end

    test "filters by position" do
      {:ok, qb_results} = WaiverRecommendation 
        |> Ash.Query.filter(position == "QB")
        |> Ash.read()
      
      assert length(qb_results) == 1
      assert hd(qb_results).position == "QB"
      assert hd(qb_results).player_name == "QB One"
    end

    test "filters by recommendation_type" do
      {:ok, pickup_results} = WaiverRecommendation 
        |> Ash.Query.filter(recommendation_type == "pickup")
        |> Ash.read()
      
      assert length(pickup_results) == 3
      Enum.each(pickup_results, fn result ->
        assert result.recommendation_type == "pickup"
      end)

      {:ok, drop_results} = WaiverRecommendation 
        |> Ash.Query.filter(recommendation_type == "drop")
        |> Ash.read()
      
      assert length(drop_results) == 1
      assert hd(drop_results).recommendation_type == "drop"
    end

    test "filters by status" do
      {:ok, pending_results} = WaiverRecommendation 
        |> Ash.Query.filter(status == "pending")
        |> Ash.read()
      
      assert length(pending_results) == 2

      {:ok, applied_results} = WaiverRecommendation 
        |> Ash.Query.filter(status == "applied")
        |> Ash.read()
      
      assert length(applied_results) == 1
      assert hd(applied_results).status == "applied"

      {:ok, dismissed_results} = WaiverRecommendation 
        |> Ash.Query.filter(status == "dismissed")
        |> Ash.read()
      
      assert length(dismissed_results) == 1
      assert hd(dismissed_results).status == "dismissed"
    end

    test "filters by week and season" do
      {:ok, week8_results} = WaiverRecommendation 
        |> Ash.Query.filter(week == 8 and season == 2024)
        |> Ash.read()
      
      assert length(week8_results) == 4

      {:ok, week7_results} = WaiverRecommendation 
        |> Ash.Query.filter(week == 7 and season == 2024)
        |> Ash.read()
      
      assert length(week7_results) == 0
    end

    test "filters by priority_score range" do
      {:ok, high_priority_results} = WaiverRecommendation 
        |> Ash.Query.filter(priority_score >= 7.0)
        |> Ash.read()
      
      assert length(high_priority_results) == 2

      {:ok, low_priority_results} = WaiverRecommendation 
        |> Ash.Query.filter(priority_score < 5.0)
        |> Ash.read()
      
      assert length(low_priority_results) == 1
    end

    test "sorts by priority_score descending" do
      {:ok, sorted_results} = WaiverRecommendation 
        |> Ash.Query.sort(priority_score: :desc)
        |> Ash.read()
      
      priority_scores = Enum.map(sorted_results, fn r -> 
        Decimal.to_float(r.priority_score) 
      end)
      
      assert priority_scores == [9.0, 7.5, 6.0, 3.0]
    end

    test "combines multiple filters" do
      {:ok, combined_results} = WaiverRecommendation 
        |> Ash.Query.filter(team_id == "team_123" and status == "pending" and recommendation_type == "pickup")
        |> Ash.read()
      
      assert length(combined_results) == 1
      
      result = hd(combined_results)
      assert result.team_id == "team_123"
      assert result.status == "pending"
      assert result.recommendation_type == "pickup"
      assert result.player_name == "QB One"
    end

    test "limits and offsets results" do
      {:ok, limited_results} = WaiverRecommendation 
        |> Ash.Query.sort(priority_score: :desc)
        |> Ash.Query.limit(2)
        |> Ash.read()
      
      assert length(limited_results) == 2
      
      priority_scores = Enum.map(limited_results, fn r -> 
        Decimal.to_float(r.priority_score) 
      end)
      assert priority_scores == [9.0, 7.5]

      {:ok, offset_results} = WaiverRecommendation 
        |> Ash.Query.sort(priority_score: :desc)
        |> Ash.Query.limit(2)
        |> Ash.Query.offset(2)
        |> Ash.read()
      
      assert length(offset_results) == 2
      
      offset_scores = Enum.map(offset_results, fn r -> 
        Decimal.to_float(r.priority_score) 
      end)
      assert offset_scores == [6.0, 3.0]
    end

    test "gets recommendation by id" do
      {:ok, all_recs} = WaiverRecommendation |> Ash.read()
      first_rec = hd(all_recs)
      
      {:ok, found_rec} = WaiverRecommendation |> Ash.get(first_rec.id)
      
      assert found_rec.id == first_rec.id
      assert found_rec.team_id == first_rec.team_id
      assert found_rec.player_id == first_rec.player_id
    end
  end

  describe "WaiverRecommendation updates" do
    test "updates status" do
      attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        status: "pending",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      {:ok, recommendation} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      {:ok, updated_rec} = recommendation
        |> Ash.Changeset.for_update(:update, %{status: "applied"})
        |> Ash.update()

      assert updated_rec.status == "applied"
      assert updated_rec.id == recommendation.id
    end

    test "prevents updating immutable fields" do
      attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      {:ok, recommendation} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      # Attempting to update generated_at should fail or be ignored based on resource configuration
      {:error, %Ash.Error.Invalid{}} = recommendation
        |> Ash.Changeset.for_update(:update, %{generated_at: ~N[2024-09-09 12:00:00]})
        |> Ash.update()
    end
  end

  describe "WaiverRecommendation deletion" do
    test "destroys recommendation" do
      attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00]
      }

      {:ok, recommendation} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      assert {:ok, _} = recommendation |> Ash.destroy()

      # Verify it's been deleted
      assert {:error, %Ash.Error.Query.NotFound{}} = WaiverRecommendation |> Ash.get(recommendation.id)
    end
  end

  describe "WaiverRecommendation expiration" do
    test "handles expiry dates correctly" do
      future_expiry = ~N[2024-12-31 23:59:59]
      
      attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00],
        expires_at: future_expiry
      }

      {:ok, recommendation} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      assert recommendation.expires_at == future_expiry
    end

    test "allows nil expiry date" do
      attrs = %{
        team_id: "team_123",
        player_id: "player_456",
        player_name: "Test Player",
        position: "RB",
        recommendation_type: "pickup",
        priority_score: 8.5,
        reasoning: "Test reasoning",
        week: 8,
        season: 2024,
        generated_at: ~N[2024-09-08 12:00:00],
        expires_at: nil
      }

      {:ok, recommendation} = WaiverRecommendation
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()

      assert recommendation.expires_at == nil
    end
  end
end