defmodule FantasyManagerWeb.DashboardLive do
  use FantasyManagerWeb, :live_view

  alias FantasyManager.Fantasy.{League, Player, FantasyTeam}
  alias FantasyManager.External.SleeperClient

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Fantasy Manager Dashboard")
      |> assign(:leagues, [])
      |> assign(:players, [])
      |> assign(:search_query, "")
      |> assign(:selected_league, nil)
      |> assign(:selected_team, nil)
      |> assign(:sync_status, nil)
      |> assign(:loading, false)
      |> assign(:error_message, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dashboard")
    |> load_leagues()
  end

  defp apply_action(socket, :league_detail, %{"id" => league_id}) do
    case Ash.get(League, league_id, load: [:fantasy_teams]) do
      {:ok, league} ->
        socket
        |> assign(:selected_league, league)
        |> assign(:selected_team, nil)
        |> assign(:page_title, "League: #{league.name}")
        
      {:error, _} ->
        socket
        |> assign(:error_message, "League not found")
        |> push_navigate(to: ~p"/dashboard")
    end
  end

  defp apply_action(socket, :team_detail, %{"league_id" => league_id, "team_id" => team_id}) do
    with {:ok, league} <- Ash.get(League, league_id, load: [:fantasy_teams]),
         {:ok, team} <- Ash.get(FantasyTeam, team_id, load: [fantasy_team_players: [:player]]) do
      socket
      |> assign(:selected_league, league)
      |> assign(:selected_team, team)
      |> assign(:page_title, "Team: #{team.name}")
    else
      {:error, _} ->
        socket
        |> assign(:error_message, "Team or League not found")
        |> push_navigate(to: ~p"/dashboard")
    end
  end

  @impl true
  def handle_event("search_players", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)
      |> search_players(query)

    {:noreply, socket}
  end

  def handle_event("sync_league", %{"sleeper_id" => sleeper_id}, socket) do
    socket = assign(socket, loading: true, sync_status: "Syncing league and rosters...")

    case League.sync_from_sleeper(sleeper_id, true) do
      {:ok, _result} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:sync_status, "Sync completed successfully!")
          |> assign(:error_message, nil)
          |> load_leagues()

        # Clear sync status after 3 seconds
        Process.send_after(self(), :clear_sync_status, 3000)

        {:noreply, socket}

      {:error, error} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:sync_status, nil)
          |> assign(:error_message, "Sync failed: #{inspect(error)}")

        {:noreply, socket}
    end
  end

  def handle_event("sync_players", _params, socket) do
    socket = assign(socket, loading: true, sync_status: "Syncing players from Sleeper...")

    case FantasyManager.External.SleeperClient.get_all_players() do
      {:ok, players_data} ->
        # Create/update players in batches to avoid timeout
        {created_count, updated_count, skipped_count, error_count} = 
          players_data
          |> Enum.take(100)  # Limit to first 100 for testing
          |> Enum.reduce({0, 0, 0, 0}, fn {_sleeper_id, player_data}, {created, updated, skipped, errors} ->
            case Player.upsert_from_sleeper(player_data) do
              {:ok, {:created, _player}} -> 
                {created + 1, updated, skipped, errors}
              {:ok, {:updated, _player}} -> 
                {created, updated + 1, skipped, errors}
              {:ok, {:skipped, _reason}} -> 
                # Skip non-fantasy-relevant players (CB, OL, etc.)
                {created, updated, skipped + 1, errors}
              {:error, _reason} -> 
                {created, updated, skipped, errors + 1}
            end
          end)

        total_processed = created_count + updated_count
        status_message = cond do
          error_count > 0 -> 
            "Processed #{total_processed} players (#{created_count} created, #{updated_count} updated, #{skipped_count} skipped, #{error_count} errors)"
          skipped_count > 0 and updated_count > 0 -> 
            "Successfully synced #{total_processed} fantasy players (#{created_count} new, #{updated_count} updated, #{skipped_count} non-fantasy players skipped)!"
          skipped_count > 0 -> 
            "Successfully synced #{created_count} new fantasy players (#{skipped_count} non-fantasy players skipped)!"
          updated_count > 0 -> 
            "Successfully synced #{total_processed} players (#{created_count} new, #{updated_count} updated)!"
          true -> 
            "Successfully synced #{created_count} new players!"
        end

        socket
        |> assign(:loading, false)
        |> assign(:sync_status, status_message)
        |> assign(:error_message, nil)

      {:error, error} ->
        IO.puts("Failed to fetch players from Sleeper API: #{inspect(error)}")
        socket
        |> assign(:loading, false)
        |> assign(:sync_status, nil)
        |> assign(:error_message, "Failed to sync players from Sleeper")
    end
    |> then(fn socket -> {:noreply, socket} end)
  end

  def handle_event("sync_teams_and_rosters", %{"sleeper_id" => sleeper_id}, socket) do
    socket = assign(socket, loading: true, sync_status: "Syncing teams and rosters...")

    case League.sync_from_sleeper(sleeper_id, true) do
      {:ok, _result} ->
        # Reload the selected league with updated team data
        updated_socket = case socket.assigns.selected_league do
          nil -> socket
          league -> 
            case Ash.get(League, league.id, load: [:fantasy_teams]) do
              {:ok, updated_league} -> assign(socket, :selected_league, updated_league)
              {:error, _} -> socket
            end
        end

        socket =
          updated_socket
          |> assign(:loading, false)
          |> assign(:sync_status, "Teams and rosters synced successfully!")
          |> assign(:error_message, nil)

        # Clear sync status after 3 seconds
        Process.send_after(self(), :clear_sync_status, 3000)

        {:noreply, socket}

      {:error, error} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:sync_status, nil)
          |> assign(:error_message, "Sync failed: #{inspect(error)}")

        {:noreply, socket}
    end
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  def handle_event("refresh_leagues", _params, socket) do
    {:noreply, load_leagues(socket)}
  end

  @impl true
  def handle_info(:clear_sync_status, socket) do
    {:noreply, assign(socket, :sync_status, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="bg-base-100 shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center py-6">
            <div class="flex items-center">
              <h1 class="text-3xl font-bold text-base-content">
                Fantasy Manager Dashboard
              </h1>
            </div>
            <div class="flex items-center space-x-4">
              <.link navigate={~p"/dashboard/recommendations"} class="btn btn-primary">
                AI Recommendations
              </.link>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @error_message do %>
          <div class="alert alert-error mb-6">
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span><%= @error_message %></span>
            <button phx-click="clear_error" class="btn btn-sm btn-ghost">
              ✕
            </button>
          </div>
        <% end %>

        <%= if @sync_status do %>
          <div class="alert alert-info mb-6">
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6 animate-spin" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            <span><%= @sync_status %></span>
          </div>
        <% end %>

        <%= if @live_action == :league_detail and @selected_league do %>
          <%= render_league_detail(assigns) %>
        <% end %>
        
        <%= if @live_action == :team_detail and @selected_team do %>
          <%= render_team_detail(assigns) %>
        <% end %>
        
        <%= if @live_action == :index do %>
          <%= render_dashboard(assigns) %>
        <% end %>
      </div>
    </div>
    """
  end

  # Render main dashboard view
  defp render_dashboard(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
      <!-- League Management Panel -->
      <div class="lg:col-span-2">
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h3 class="card-title text-base-content mb-4">League Management</h3>
            
            <!-- Sync from Sleeper Form -->
            <div class="mb-6">
              <h4 class="text-md font-medium text-base-content mb-2">Sync League from Sleeper</h4>
              <form phx-submit="sync_league" class="flex space-x-2">
                <input
                  type="text"
                  name="sleeper_id"
                  placeholder="Enter Sleeper League ID"
                  class="input input-bordered flex-1"
                  required
                />
                <button
                  type="submit"
                  class="btn btn-primary"
                  disabled={@loading}
                >
                  <%= if @loading, do: "Syncing...", else: "Sync League" %>
                </button>
              </form>
              <p class="mt-2 text-sm text-base-content opacity-70">
                Enter your Sleeper league ID to import league data and teams.
              </p>
            </div>

            <!-- Sync Players -->
            <div class="mb-6">
              <h4 class="text-md font-medium text-base-content mb-2">Player Database</h4>
              <button
                phx-click="sync_players"
                class="btn btn-secondary"
                disabled={@loading}
              >
                <%= if @loading, do: "Syncing...", else: "Sync Players from Sleeper" %>
              </button>
              <p class="mt-2 text-sm text-base-content opacity-70">
                Populate the player database from Sleeper. Do this before syncing team rosters.
              </p>
            </div>

            <!-- Current Leagues -->
            <div>
              <div class="flex justify-between items-center mb-4">
                <h4 class="text-md font-medium text-base-content">Your Leagues</h4>
                <button phx-click="refresh_leagues" class="btn btn-ghost btn-sm">
                  <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                </button>
              </div>
              
              <%= if length(@leagues) > 0 do %>
                <div class="space-y-3">
                  <%= for league <- @leagues do %>
                    <div class="card bg-base-200 border border-base-300 p-4">
                      <div class="flex justify-between items-start">
                        <div>
                          <h5 class="font-medium text-base-content"><%= league.name %></h5>
                          <p class="text-sm text-base-content opacity-70">
                            <%= league.season %> • <%= String.capitalize(to_string(league.league_type)) %> • 
                            <%= String.capitalize(to_string(league.scoring_format)) %>
                          </p>
                          <p class="text-xs text-base-content opacity-50 mt-1">
                            Sleeper ID: <%= league.sleeper_id %>
                          </p>
                        </div>
                        <.link navigate={~p"/dashboard/league/#{league.id}"} class="btn btn-secondary btn-sm">
                          View Details
                        </.link>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-base-content opacity-70 text-center py-4">
                  No leagues found. Sync a league from Sleeper to get started.
                </p>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <!-- Player Search Panel -->
      <div>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h3 class="card-title text-base-content mb-4">Player Search</h3>
            
            <form phx-submit="search_players">
              <div class="flex">
                <input
                  type="text"
                  name="search[query]"
                  value={@search_query}
                  placeholder="Search players..."
                  class="input input-bordered flex-1 rounded-r-none"
                />
                <button
                  type="submit"
                  class="btn btn-primary rounded-l-none"
                  disabled={@loading}
                >
                  Search
                </button>
              </div>
            </form>

            <%= if length(@players) > 0 do %>
              <div class="mt-4 space-y-2">
                <%= for player <- @players do %>
                  <div class="card bg-base-200 border border-base-300 p-3">
                    <div class="flex justify-between items-center">
                      <div>
                        <p class="font-medium text-base-content"><%= player.name %></p>
                        <p class="text-sm text-base-content opacity-70">
                          <%= player.position %> • <%= player.nfl_team || "FA" %>
                        </p>
                      </div>
                      <div class="text-right">
                        <p class="text-sm font-medium text-primary">
                          Dynasty: <%= Float.round(Decimal.to_float(player.dynasty_value), 1) %>
                        </p>
                        <%= if player.injury_status != :Active do %>
                          <p class="text-xs text-error">
                            <%= player.injury_status %>
                          </p>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <%= if @search_query != "" do %>
                <p class="text-base-content opacity-70 text-center py-4 mt-4">
                  No players found for "<%= @search_query %>".
                </p>
              <% end %>
            <% end %>
          </div>
        </div>

        <!-- Quick Stats -->
        <div class="card bg-base-100 shadow-xl mt-6">
          <div class="card-body">
            <h3 class="card-title text-base-content mb-4">Quick Stats</h3>
            <div class="space-y-3">
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Total Leagues</span>
                <span class="text-sm font-medium text-base-content"><%= length(@leagues) %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Dynasty Leagues</span>
                <span class="text-sm font-medium text-base-content">
                  <%= Enum.count(@leagues, &(&1.league_type == :dynasty)) %>
                </span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Keeper Leagues</span>
                <span class="text-sm font-medium text-base-content">
                  <%= Enum.count(@leagues, &(&1.league_type == :keeper)) %>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Render league detail view  
  defp render_league_detail(assigns) do
    ~H"""
    <div class="mb-6">
      <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm">
        ← Back to Dashboard
      </.link>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
      <!-- League Info -->
      <div class="lg:col-span-2">
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title text-2xl text-base-content mb-4"><%= @selected_league.name %></h2>
            
            <div class="grid grid-cols-2 gap-4 mb-6">
              <div>
                <p class="text-sm text-base-content opacity-70">Season</p>
                <p class="font-medium text-base-content"><%= @selected_league.season %></p>
              </div>
              <div>
                <p class="text-sm text-base-content opacity-70">League Type</p>
                <p class="font-medium text-base-content"><%= String.capitalize(to_string(@selected_league.league_type)) %></p>
              </div>
              <div>
                <p class="text-sm text-base-content opacity-70">Scoring Format</p>
                <p class="font-medium text-base-content"><%= String.capitalize(to_string(@selected_league.scoring_format)) %></p>
              </div>
              <div>
                <p class="text-sm text-base-content opacity-70">Teams</p>
                <p class="font-medium text-base-content"><%= length(@selected_league.fantasy_teams) %></p>
              </div>
            </div>

            <!-- Fantasy Teams -->
            <h3 class="text-lg font-semibold text-base-content mb-4">Teams</h3>
            <%= if length(@selected_league.fantasy_teams) > 0 do %>
              <div class="space-y-3">
                <%= for team <- @selected_league.fantasy_teams do %>
                  <div class="card bg-base-200 border border-base-300 p-4">
                    <div class="flex justify-between items-start">
                      <div>
                        <h4 class="font-medium text-base-content"><%= team.name %></h4>
                        <p class="text-sm text-base-content opacity-70">
                          Owner: <%= team.owner_name || "Unknown" %>
                        </p>
                        <%= if team.wins || team.losses do %>
                          <p class="text-xs text-base-content opacity-50 mt-1">
                            Record: <%= team.wins || 0 %>-<%= team.losses || 0 %>-<%= team.ties || 0 %>
                          </p>
                        <% end %>
                      </div>
                      <div class="text-right">
                        <%= if team.points_for do %>
                          <p class="text-sm font-medium text-primary">
                            <%= team.points_for |> Decimal.to_float() |> Float.round(1) %> PF
                          </p>
                        <% end %>
                        <%= if team.faab_budget do %>
                          <p class="text-xs text-base-content opacity-50">
                            $<%= team.faab_budget %> FAAB
                          </p>
                        <% end %>
                        <.link 
                          navigate={~p"/dashboard/league/#{@selected_league.id}/team/#{team.id}"} 
                          class="btn btn-sm btn-primary mt-2"
                        >
                          View Roster
                        </.link>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="text-base-content opacity-70 text-center py-4">
                No teams found. Try syncing the league to load team data.
              </p>
            <% end %>
          </div>
        </div>
      </div>

      <!-- League Stats -->
      <div>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h3 class="card-title text-base-content mb-4">League Settings</h3>
            <div class="space-y-3">
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Roster Size</span>
                <span class="text-sm font-medium text-base-content"><%= @selected_league.roster_size %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Playoff Teams</span>
                <span class="text-sm font-medium text-base-content"><%= @selected_league.playoff_teams %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Trade Deadline</span>
                <span class="text-sm font-medium text-base-content">Week <%= @selected_league.trade_deadline_week %></span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Waiver Type</span>
                <span class="text-sm font-medium text-base-content">
                  <%= String.upcase(to_string(@selected_league.waiver_type)) %>
                </span>
              </div>
              <div class="flex justify-between">
                <span class="text-sm text-base-content opacity-70">Draft Type</span>
                <span class="text-sm font-medium text-base-content">
                  <%= String.capitalize(to_string(@selected_league.draft_type)) %>
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl mt-6">
          <div class="card-body">
            <h3 class="card-title text-base-content mb-4">Actions</h3>
            <div class="space-y-2">
              <button phx-click="sync_teams_and_rosters" phx-value-sleeper_id={@selected_league.sleeper_id} class="btn btn-primary btn-block" disabled={@loading}>
                <%= if @loading, do: "Syncing...", else: "Sync Teams & Rosters" %>
              </button>
              <.link navigate={~p"/dashboard/recommendations"} class="btn btn-secondary btn-block">
                Get AI Recommendations
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions
  defp load_leagues(socket) do
    case League.read() do
      {:ok, leagues} ->
        assign(socket, :leagues, leagues)
      {:error, _} ->
        assign(socket, leagues: [], error_message: "Failed to load leagues")
    end
  end

  defp search_players(socket, query) when query != "" do
    search_term = "%#{query}%"
    
    case Player.search(search_term) do
      {:ok, players} ->
        socket
        |> assign(:players, Enum.take(players, 10))  # Limit to 10 results
        |> assign(:loading, false)
        |> assign(:error_message, nil)
      
      {:error, _} ->
        socket
        |> assign(:players, [])
        |> assign(:loading, false)
        |> assign(:error_message, "Failed to search players")
    end
  end

  defp search_players(socket, _query) do
    socket
    |> assign(:players, [])
    |> assign(:loading, false)
  end

  # Render team detail view with roster
  defp render_team_detail(assigns) do
    ~H"""
    <div class="mb-8">
      <!-- Breadcrumb -->
      <nav class="breadcrumbs text-sm text-base-content opacity-70 mb-4">
        <ul>
          <li>
            <.link navigate={~p"/dashboard"}>Dashboard</.link>
          </li>
          <li>
            <.link navigate={~p"/dashboard/league/#{@selected_league.id}"}>
              <%= @selected_league.name %>
            </.link>
          </li>
          <li>
            <%= @selected_team.name %>
          </li>
        </ul>
      </nav>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-4 gap-8">
      <!-- Team Info Sidebar -->
      <div class="lg:col-span-1">
        <div class="card bg-base-100 shadow-xl sticky top-4">
          <div class="card-body">
            <h2 class="card-title text-xl text-base-content mb-4">
              <%= @selected_team.name %>
            </h2>
            
            <div class="space-y-3">
              <div>
                <p class="text-sm text-base-content opacity-70">Owner</p>
                <p class="font-medium text-base-content"><%= @selected_team.owner_name %></p>
              </div>
              
              <%= if @selected_team.wins || @selected_team.losses do %>
                <div>
                  <p class="text-sm text-base-content opacity-70">Record</p>
                  <p class="font-medium text-base-content">
                    <%= @selected_team.wins || 0 %>-<%= @selected_team.losses || 0 %>-<%= @selected_team.ties || 0 %>
                  </p>
                </div>
              <% end %>
              
              <%= if @selected_team.points_for do %>
                <div>
                  <p class="text-sm text-base-content opacity-70">Points For</p>
                  <p class="font-medium text-primary">
                    <%= @selected_team.points_for |> Decimal.to_float() |> Float.round(1) %>
                  </p>
                </div>
              <% end %>
              
              <%= if @selected_team.points_against do %>
                <div>
                  <p class="text-sm text-base-content opacity-70">Points Against</p>
                  <p class="font-medium text-base-content">
                    <%= @selected_team.points_against |> Decimal.to_float() |> Float.round(1) %>
                  </p>
                </div>
              <% end %>
              
              <div>
                <p class="text-sm text-base-content opacity-70">FAAB Budget</p>
                <p class="font-medium text-base-content">$<%= @selected_team.faab_budget %></p>
              </div>
              
              <div>
                <p class="text-sm text-base-content opacity-70">Total Moves</p>
                <p class="font-medium text-base-content"><%= @selected_team.total_moves %></p>
              </div>
              
              <div>
                <p class="text-sm text-base-content opacity-70">Competitive Window</p>
                <span class={[
                  "badge",
                  case @selected_team.competitive_window do
                    :Contending -> "badge-success"
                    :Rebuilding -> "badge-warning"
                    :Neutral -> "badge-neutral"
                    _ -> "badge-neutral"
                  end
                ]}>
                  <%= @selected_team.competitive_window %>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Roster -->
      <div class="lg:col-span-3">
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h3 class="card-title text-2xl text-base-content mb-6">Roster</h3>
            
            <%= if length(@selected_team.fantasy_team_players) > 0 do %>
              <!-- Starters Section -->
              <div class="mb-8">
                <h4 class="text-lg font-semibold text-base-content mb-4 flex items-center">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
                  </svg>
                  Starting Lineup
                </h4>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <%= for team_player <- Enum.filter(@selected_team.fantasy_team_players, &(&1.roster_position == :Starter)) do %>
                    <div class="card bg-primary text-primary-content border-2 border-primary">
                      <div class="card-body p-4">
                        <div class="flex justify-between items-start">
                          <div>
                            <h5 class="font-bold text-lg"><%= team_player.player.name %></h5>
                            <p class="opacity-80"><%= team_player.player.position %> - <%= team_player.player.nfl_team || "FA" %></p>
                            <%= if team_player.lineup_position do %>
                              <span class="badge badge-secondary badge-sm mt-1"><%= team_player.lineup_position %></span>
                            <% end %>
                          </div>
                          <div class="text-right">
                            <%= if team_player.player.dynasty_value do %>
                              <p class="text-sm opacity-80">
                                Dynasty: <%= Float.round(Decimal.to_float(team_player.player.dynasty_value), 1) %>
                              </p>
                            <% end %>
                            <p class="text-xs opacity-70 mt-1">
                              <%= String.capitalize(to_string(team_player.acquisition_type)) %>
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Bench Section -->
              <div class="mb-8">
                <h4 class="text-lg font-semibold text-base-content mb-4 flex items-center">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                  </svg>
                  Bench
                </h4>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <%= for team_player <- Enum.filter(@selected_team.fantasy_team_players, &(&1.roster_position == :Bench)) do %>
                    <div class="card bg-base-200 border border-base-300">
                      <div class="card-body p-4">
                        <div class="flex justify-between items-start">
                          <div>
                            <h5 class="font-semibold text-base-content"><%= team_player.player.name %></h5>
                            <p class="text-sm text-base-content opacity-70"><%= team_player.player.position %> - <%= team_player.player.nfl_team || "FA" %></p>
                          </div>
                          <div class="text-right">
                            <%= if team_player.player.dynasty_value do %>
                              <p class="text-xs text-base-content opacity-50">
                                Dynasty: <%= Float.round(Decimal.to_float(team_player.player.dynasty_value), 1) %>
                              </p>
                            <% end %>
                          </div>
                        </div>
                        <p class="text-xs text-base-content opacity-50 mt-2">
                          <%= String.capitalize(to_string(team_player.acquisition_type)) %>
                        </p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Other Positions (IR, Taxi) -->
              <%= if Enum.any?(@selected_team.fantasy_team_players, &(&1.roster_position not in [:Starter, :Bench])) do %>
                <div class="mb-8">
                  <h4 class="text-lg font-semibold text-base-content mb-4">Other</h4>
                  <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <%= for team_player <- Enum.filter(@selected_team.fantasy_team_players, &(&1.roster_position not in [:Starter, :Bench])) do %>
                      <div class="card bg-warning text-warning-content">
                        <div class="card-body p-4">
                          <div class="flex justify-between items-start">
                            <div>
                              <h5 class="font-semibold"><%= team_player.player.name %></h5>
                              <p class="opacity-80 text-sm"><%= team_player.player.position %> - <%= team_player.player.nfl_team || "FA" %></p>
                            </div>
                            <span class="badge badge-neutral badge-sm">
                              <%= team_player.roster_position %>
                            </span>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

            <% else %>
              <div class="text-center py-8">
                <p class="text-base-content opacity-70">No roster data available</p>
                <p class="text-sm text-base-content opacity-50 mt-2">
                  Try syncing the team data from Sleeper
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end