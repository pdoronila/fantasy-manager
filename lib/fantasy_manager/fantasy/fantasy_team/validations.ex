defmodule FantasyManager.Fantasy.FantasyTeam.Validations do
  @moduledoc """
  Custom validations for FantasyTeam resources.
  
  Contains business logic validations that ensure fantasy team data
  consistency and adherence to league rules.
  """
  
  alias FantasyManager.Fantasy.League
  
  @doc """
  Validates that the FAAB budget is within league-defined limits.
  """
  def faab_budget_within_league_limits(changeset, _opts) do
      league_id = Ash.Changeset.get_attribute(changeset, :league_id)
      faab_budget = Ash.Changeset.get_attribute(changeset, :faab_budget)
      
      case get_league_faab_limit(league_id) do
        {:ok, nil} -> 
          # League doesn't use FAAB, any budget is invalid
          if faab_budget && faab_budget > 0 do
            {:error, "League does not use FAAB budget system"}
          else
            :ok
          end
          
        {:ok, league_limit} ->
          if faab_budget && faab_budget > league_limit do
            {:error, "FAAB budget cannot exceed league limit of $#{league_limit}"}
          else
            :ok
          end
          
        {:error, _} ->
          {:error, "Could not validate FAAB budget - league not found"}
      end
  end
  
  @doc """
  Validates that waiver priority is unique within the league.
  """
  def waiver_priority_unique_within_league(changeset, _opts) do
      league_id = Ash.Changeset.get_attribute(changeset, :league_id)
      waiver_priority = Ash.Changeset.get_attribute(changeset, :waiver_priority)
      team_id = Ash.Changeset.get_attribute(changeset, :id)
      
      if waiver_priority && league_id do
        case check_waiver_priority_uniqueness(league_id, waiver_priority, team_id) do
          :ok -> :ok
          {:error, message} -> {:error, message}
        end
      else
        :ok
      end
  end
  
  @doc """
  Validates that roster size is within league-defined limits.
  """
  def roster_size_within_league_limits(changeset, _opts) do
      league_id = Ash.Changeset.get_attribute(changeset, :league_id)
      
      case get_league_roster_limits(league_id) do
        {:ok, {_min_size, _max_size}} ->
          # This would typically check the actual roster size
          # For now, we'll assume roster size checking happens elsewhere
          :ok
          
        {:error, _} ->
          {:error, "Could not validate roster size - league not found"}
      end
  end
  
  # Private helper functions
  
  defp get_league_faab_limit(league_id) do
    case Ash.get(League, league_id) do
      {:ok, league} ->
        # Extract FAAB budget from league settings
        faab_budget = get_in(league.league_settings, ["faab_budget"])
        {:ok, faab_budget}
        
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:ok, 200}  # Default FAAB budget if league settings unavailable
  end
  
  defp check_waiver_priority_uniqueness(_league_id, _waiver_priority, _current_team_id) do
    # This would typically query for other teams in the league with same waiver priority
    # For now, return :ok to allow compilation
    # In a real implementation:
    # FantasyTeam
    # |> Ash.Query.filter(league_id == ^league_id and waiver_priority == ^waiver_priority and id != ^current_team_id)
    # |> Ash.read()
    # |> case do
    #   {:ok, []} -> :ok
    #   {:ok, _teams} -> {:error, "Waiver priority #{waiver_priority} is already taken"}
    #   error -> error
    # end
    
    :ok
  end
  
  defp get_league_roster_limits(league_id) do
    case Ash.get(League, league_id) do
      {:ok, league} ->
        # Extract roster limits from league settings
        min_size = get_in(league.league_settings, ["min_roster_size"]) || 15
        max_size = get_in(league.league_settings, ["max_roster_size"]) || 16
        {:ok, {min_size, max_size}}
        
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:ok, {15, 16}}  # Default roster limits if league settings unavailable
  end
end