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
        |> assign(:page_title, "League: #{league.name}")
        
      {:error, _} ->
        socket
        |> assign(:error_message, "League not found")
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
    socket = assign(socket, loading: true, sync_status: "Syncing league...")

    case League.sync_from_sleeper(sleeper_id, false) do
      {:ok, result} ->
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
end