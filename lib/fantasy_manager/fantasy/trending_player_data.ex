defmodule FantasyManager.Fantasy.TrendingPlayerData do
  @moduledoc """
  Represents trending player data from Sleeper API.
  
  Tracks which players are being added or dropped by fantasy managers,
  providing insights into player popularity and potential waiver wire targets.
  """
  
  use Ash.Resource,
    domain: FantasyManager.Fantasy,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "trending_player_data"
    repo FantasyManager.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :player_id, :string do
      allow_nil? false
      public? true
    end

    attribute :player_name, :string do
      allow_nil? false
      public? true
    end

    attribute :position, :string do
      allow_nil? false
      public? true
    end

    attribute :team, :string do
      public? true
    end

    attribute :trend_type, :string do
      allow_nil? false
      public? true
    end

    attribute :trend_count, :integer do
      allow_nil? false
      public? true
      default 0
    end

    attribute :retrieved_at, :naive_datetime do
      allow_nil? false
      public? true
    end

    attribute :week, :integer do
      allow_nil? false
      public? true
    end

    attribute :season, :integer do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :player_id,
        :player_name,
        :position,
        :team,
        :trend_type,
        :trend_count,
        :retrieved_at,
        :week,
        :season
      ]
    end

    update :update do
      primary? true
      accept [
        :trend_count,
        :retrieved_at
      ]
    end

    read :get do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end
  end

  identities do
    identity :unique_player_trend, [:player_id, :trend_type, :week, :season] do
      eager_check_with FantasyManager.Fantasy
    end
  end

  preparations do
    prepare build(sort: [trend_count: :desc, inserted_at: :desc])
  end

  code_interface do
    domain FantasyManager.Fantasy
    define :create
    define :read
    define :update
    define :destroy
    define :get
  end
end