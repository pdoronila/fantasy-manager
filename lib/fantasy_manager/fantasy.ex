defmodule FantasyManager.Fantasy do
  @moduledoc """
  The Fantasy domain for managing fantasy football resources.
  
  This domain contains all fantasy football related resources including
  Players, Leagues, FantasyTeams, and WeeklyProjections.
  """
  
  use Ash.Domain
  
  resources do
    resource FantasyManager.Fantasy.Player
    resource FantasyManager.Fantasy.League
    resource FantasyManager.Fantasy.FantasyTeam
    resource FantasyManager.Fantasy.WeeklyProjection
  end
end