defmodule FantasyManager.Repo.Migrations.AddDropCandidateToWaiverRecommendations do
  use Ecto.Migration

  def change do
    alter table(:waiver_recommendations) do
      add :drop_candidate, :text
    end
  end
end
