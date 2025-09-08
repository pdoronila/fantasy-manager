defmodule FantasyManager.Repo.Migrations.CreateWaiverRecommendations do
  @moduledoc """
  Creates the waiver_recommendations table for storing AI-generated waiver pickup recommendations.
  """
  use Ecto.Migration

  def change do
    create table(:waiver_recommendations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :team_id, :string, null: false
      add :player_id, :string, null: false
      add :player_name, :string, null: false
      add :position, :string, null: false
      add :team, :string
      add :recommendation_type, :string, null: false  # "pickup", "drop", "hold"
      add :priority_score, :decimal, precision: 5, scale: 2, null: false
      add :reasoning, :text, null: false
      add :status, :string, null: false, default: "pending"  # "pending", "applied", "dismissed"
      add :week, :integer, null: false
      add :season, :integer, null: false
      add :generated_at, :naive_datetime, null: false
      add :expires_at, :naive_datetime

      timestamps(type: :naive_datetime_usec)
    end

    create index(:waiver_recommendations, [:team_id])
    create index(:waiver_recommendations, [:player_id])
    create index(:waiver_recommendations, [:position])
    create index(:waiver_recommendations, [:recommendation_type])
    create index(:waiver_recommendations, [:status])
    create index(:waiver_recommendations, [:week, :season])
    create index(:waiver_recommendations, [:priority_score])
    create index(:waiver_recommendations, [:generated_at])
    create index(:waiver_recommendations, [:expires_at])
  end
end