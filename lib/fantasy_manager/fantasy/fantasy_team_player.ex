defmodule FantasyManager.Fantasy.FantasyTeamPlayer do
  use Ash.Resource,
    domain: FantasyManager.Fantasy,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "fantasy_team_players"
    repo FantasyManager.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :roster_position, :atom do
      allow_nil? false
      default :Bench
      constraints [one_of: [:Starter, :Bench, :IR, :Taxi, :Dropped]]
    end

    attribute :lineup_position, :string do
      allow_nil? true
      constraints [max_length: 10]
    end

    attribute :acquisition_type, :atom do
      allow_nil? false
      default :Draft
      constraints [one_of: [:Draft, :Trade, :Waiver, :"Free Agent"]]
    end

    attribute :acquisition_date, :date do
      allow_nil? false
    end

    attribute :acquisition_cost, :integer do
      allow_nil? false
      default 0
      constraints [min: 0]
    end

    timestamps()
  end

  relationships do
    belongs_to :fantasy_team, FantasyManager.Fantasy.FantasyTeam do
      source_attribute :fantasy_team_id
      destination_attribute :id
    end

    belongs_to :player, FantasyManager.Fantasy.Player do
      source_attribute :player_id
      destination_attribute :id
    end
  end

  validations do
    validate present([:fantasy_team_id, :player_id, :acquisition_date])
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
        :fantasy_team_id,
        :player_id,
        :roster_position,
        :lineup_position,
        :acquisition_type,
        :acquisition_date,
        :acquisition_cost
      ]
    end

    read :by_team do
      argument :team_id, :uuid, allow_nil?: false

      filter expr(fantasy_team_id == ^arg(:team_id) and roster_position != :Dropped)
    end

    read :starters do
      argument :team_id, :uuid, allow_nil?: false

      filter expr(fantasy_team_id == ^arg(:team_id) and roster_position == :Starter)
    end

    read :bench do
      argument :team_id, :uuid, allow_nil?: false

      filter expr(fantasy_team_id == ^arg(:team_id) and roster_position == :Bench)
    end
  end

  calculations do
    calculate :is_starter, :boolean, expr(roster_position == :Starter)
    calculate :is_bench, :boolean, expr(roster_position == :Bench)
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :by_team, args: [:team_id]
    define :starters, args: [:team_id]
    define :bench, args: [:team_id]
  end

  identities do
    identity :unique_player_team, [:player_id, :fantasy_team_id]
  end
end