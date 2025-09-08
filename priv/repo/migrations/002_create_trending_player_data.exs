defmodule FantasyManager.Repo.Migrations.CreateTrendingPlayerData do
  @moduledoc """
  Creates the trending_player_data table for tracking player trending data from Sleeper API.
  """
  use Ecto.Migration

  def change do
    create table(:trending_player_data, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :player_id, :string, null: false
      add :player_name, :string, null: false
      add :position, :string, null: false
      add :team, :string
      add :trend_type, :string, null: false  # "add" or "drop"
      add :trend_count, :integer, null: false, default: 0
      add :retrieved_at, :naive_datetime, null: false
      add :week, :integer, null: false
      add :season, :integer, null: false

      timestamps(type: :naive_datetime_usec)
    end

    create index(:trending_player_data, [:player_id])
    create index(:trending_player_data, [:trend_type])
    create index(:trending_player_data, [:position])
    create index(:trending_player_data, [:week, :season])
    create index(:trending_player_data, [:retrieved_at])
    create unique_index(:trending_player_data, [:player_id, :trend_type, :week, :season])
  end
end