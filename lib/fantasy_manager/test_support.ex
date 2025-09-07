defmodule FantasyManager.TestSupport do
  @moduledoc """
  Test support utilities for FantasyManager tests.
  """

  def sample_league_id, do: "550e8400-e29b-41d4-a716-446655440000"
  def sample_team_id, do: "550e8400-e29b-41d4-a716-446655440001" 
  def sample_team_name, do: "Test Dynasty Team"

  defmodule MockData do
    @moduledoc """
    Mock data generators for testing without external API dependencies.
    """

    def sleeper_players_response do
      %{
        "4881" => %{
          "player_id" => "4881",
          "full_name" => "Josh Allen", 
          "position" => "QB",
          "team" => "BUF",
          "status" => "Active",
          "sport" => "nfl",
          "age" => 27,
          "years_exp" => 6
        },
        "4046" => %{
          "player_id" => "4046",
          "full_name" => "Christian McCaffrey",
          "position" => "RB", 
          "team" => "SF",
          "status" => "Active",
          "sport" => "nfl",
          "age" => 27,
          "years_exp" => 7
        }
      }
    end

    def get_team_roster(team_id) do
      case team_id do
        "550e8400-e29b-41d4-a716-446655440000" ->
          {:ok, [
            %{
              player_id: "4881",
              name: "Josh Allen",
              position: "QB",
              roster_position: "Starter"
            },
            %{
              player_id: "4046", 
              name: "Christian McCaffrey",
              position: "RB",
              roster_position: "Starter"
            }
          ]}
        _ ->
          {:error, :team_not_found}
      end
    end
  end
end