defmodule FantasyManagerWeb.RecommendationsLive do
  use FantasyManagerWeb, :live_view
  import Ash.Expr

  alias FantasyManager.Fantasy.{League, FantasyTeam}
  alias FantasyManager.AI.RecommendationEngine

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "AI Recommendations")
      |> assign(:leagues, [])
      |> assign(:teams, [])
      |> assign(:selected_league_id, nil)
      |> assign(:selected_team_id, nil)
      |> assign(:week, current_week())
      |> assign(:season, current_season())
      |> assign(:loading, false)
      |> assign(:error_message, nil)
      |> assign(:success_message, nil)
      |> assign(:recommendation_result, nil)
      |> assign(:recommendation_type, :lineup)
      |> assign(:chat_messages, [])
      |> assign(:chat_input, "")
      |> load_leagues()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "AI Recommendations")
  end

  @impl true
  def handle_event("league_changed", params, socket) do
    league_id = params["league_id"]
    socket =
      socket
      |> assign(:selected_league_id, league_id)
      |> assign(:selected_team_id, nil)
      |> assign(:recommendation_result, nil)
      |> load_teams_for_league(league_id)

    {:noreply, socket}
  end

  def handle_event("team_changed", %{"team_id" => team_id}, socket) do
    socket =
      socket
      |> assign(:selected_team_id, team_id)
      |> assign(:recommendation_result, nil)

    {:noreply, socket}
  end

  def handle_event("week_changed", %{"week" => week}, socket) do
    {week_int, _} = Integer.parse(week)
    {:noreply, assign(socket, :week, week_int)}
  end

  def handle_event("season_changed", %{"season" => season}, socket) do
    {season_int, _} = Integer.parse(season)
    {:noreply, assign(socket, :season, season_int)}
  end

  def handle_event("recommendation_type_changed", %{"type" => type}, socket) do
    type_atom = String.to_atom(type)
    socket = 
      socket
      |> assign(:recommendation_type, type_atom)
      |> assign(:recommendation_result, nil)

    {:noreply, socket}
  end

  def handle_event("get_lineup_recommendation", _params, socket) do
    if socket.assigns.selected_team_id do
      socket = 
        socket
        |> assign(loading: true, error_message: nil, success_message: nil)
        |> assign(:success_message, "Getting AI lineup recommendation...")
      
      case RecommendationEngine.optimize_lineup(
        socket.assigns.selected_team_id,
        socket.assigns.week,
        socket.assigns.season
      ) do
        {:ok, result} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:success_message, "Lineup recommendation generated successfully!")
            |> assign(:recommendation_result, %{type: :lineup, data: result})

          # Auto-clear success message after 3 seconds
          Process.send_after(self(), :clear_success_message, 3000)

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:success_message, nil)
            |> assign(:error_message, "Failed to get lineup recommendation: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :error_message, "Please select a team first")}
    end
  end

  def handle_event("test_ai_connection", _params, socket) do
    socket = assign(socket, loading: true, error_message: nil)
    
    try do
      case RecommendationEngine.test_connection() do
        {:ok, response} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:recommendation_result, %{type: :connection_test, data: response})

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:error_message, "AI connection test failed: #{inspect(reason)}")

          {:noreply, socket}
      end
    rescue
      error in RuntimeError ->
        message = case error.message do
          "ANTHROPIC_API_KEY environment variable is required" ->
            "AI backend automatically switched to claude-code CLI. No API key needed!"
          _ ->
            "AI connection test failed: #{error.message}"
        end
        
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error_message, message)

        {:noreply, socket}
        
      error ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error_message, "AI connection test failed: #{Exception.message(error)}")

        {:noreply, socket}
    end
  end

  def handle_event("clear_results", _params, socket) do
    socket =
      socket
      |> assign(:recommendation_result, nil)
      |> assign(:error_message, nil)
      |> assign(:success_message, "Results cleared successfully")
      |> assign(:loading, false)
    
    # Auto-clear the success message after 2 seconds
    Process.send_after(self(), :clear_success_message, 2000)
    
    {:noreply, socket}
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  def handle_event("clear_success", _params, socket) do
    {:noreply, assign(socket, :success_message, nil)}
  end

  def handle_event("update_chat_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :chat_input, value)}
  end

  def handle_event("send_chat_message", %{"message" => message}, socket) do
    if socket.assigns.selected_team_id && String.trim(message) != "" do
      timestamp = DateTime.utc_now() |> DateTime.to_string()
      
      # Add user message to chat history
      user_message = %{role: :user, content: String.trim(message), timestamp: timestamp}
      updated_messages = socket.assigns.chat_messages ++ [user_message]
      
      socket = 
        socket
        |> assign(:chat_messages, updated_messages)
        |> assign(:chat_input, "")
        |> assign(:loading, true)
        |> assign(:error_message, nil)
      
      # Send message to AI (for now, simulate AI response)
      case get_chat_response(message, socket.assigns.selected_team_id) do
        {:ok, ai_response} ->
          ai_message = %{role: :ai, content: ai_response, timestamp: DateTime.utc_now() |> DateTime.to_string()}
          final_messages = updated_messages ++ [ai_message]
          
          socket =
            socket
            |> assign(:chat_messages, final_messages)
            |> assign(:loading, false)
            
          {:noreply, socket}
          
        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:error_message, "Failed to get AI response: #{inspect(reason)}")
            
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("get_pickup_recommendations", _params, socket) do
    if socket.assigns.selected_team_id do
      socket = assign(socket, loading: true, error_message: nil)
      
      case RecommendationEngine.get_waiver_recommendations(
        socket.assigns.selected_team_id,
        socket.assigns.week,
        socket.assigns.season
      ) do
        {:ok, result} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:recommendation_result, %{type: :pickups, data: result})

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:error_message, "Failed to get pickup recommendations: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :error_message, "Please select a team first")}
    end
  end

  def handle_event("get_keeper_recommendations", _params, socket) do
    if socket.assigns.selected_team_id do
      socket = assign(socket, loading: true, error_message: nil)
      
      case RecommendationEngine.optimize_keepers(
        socket.assigns.selected_team_id,
        socket.assigns.season
      ) do
        {:ok, result} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:recommendation_result, %{type: :keepers, data: result})

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:error_message, "Failed to get keeper recommendations: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :error_message, "Please select a team first")}
    end
  end

  def handle_event("get_dynasty_plan", _params, socket) do
    if socket.assigns.selected_team_id do
      socket = assign(socket, loading: true, error_message: nil)
      
      case RecommendationEngine.create_dynasty_plan(
        socket.assigns.selected_team_id,
        "medium" # default timeline for now
      ) do
        {:ok, result} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:recommendation_result, %{type: :dynasty, data: result})

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:error_message, "Failed to create dynasty plan: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :error_message, "Please select a team first")}
    end
  end

  def handle_event("analyze_trade", %{"trade" => trade_params}, socket) do
    if socket.assigns.selected_team_id do
      socket = assign(socket, loading: true, error_message: nil)
      
      # Parse trade proposal from form data
      trade_proposal = %{
        give: String.split(trade_params["give_players"] || "", ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")),
        receive: String.split(trade_params["receive_players"] || "", ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      }

      case RecommendationEngine.analyze_trade(socket.assigns.selected_team_id, trade_proposal) do
        {:ok, analysis} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:recommendation_result, %{type: :trade, data: analysis})

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:error_message, "Failed to analyze trade: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :error_message, "Please select a team first")}
    end
  end

  @impl true
  def handle_info(:clear_success_message, socket) do
    {:noreply, assign(socket, :success_message, nil)}
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
                AI Recommendations
              </h1>
            </div>
            <div class="flex items-center space-x-4">
              <.link navigate={~p"/dashboard"} class="btn btn-secondary">
                ← Back to Dashboard
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

        <%= if @success_message do %>
          <div class="alert alert-success mb-6">
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span><%= @success_message %></span>
            <button phx-click="clear_success" class="btn btn-sm btn-ghost">
              ✕
            </button>
          </div>
        <% end %>

        <div class="flex flex-col lg:flex-row gap-8 min-h-screen">
          <!-- Settings Panel -->
          <div class="lg:w-80 flex-shrink-0">
            <div class="card bg-base-100 shadow-xl sticky top-4">
              <div class="card-body space-y-4">
                <h3 class="card-title text-base-content text-lg">Settings</h3>
              
              <!-- League Selection -->
              <div>
                <label for="league-select" class="label">
                  <span class="label-text">League</span>
                </label>
                <form phx-change="league_changed">
                  <select
                    id="league-select"
                    name="league_id"
                    class="select select-bordered w-full"
                  >
                    <option value="">Select League...</option>
                    <%= for league <- @leagues do %>
                      <option value={league.id} selected={league.id == @selected_league_id}>
                        <%= league.name %> (<%= league.season %>)
                      </option>
                    <% end %>
                  </select>
                </form>
              </div>

              <!-- Team Selection -->
              <%= if @selected_league_id do %>
                <div>
                  <label for="team-select" class="label">
                    <span class="label-text">Team</span>
                  </label>
                  <form phx-change="team_changed">
                    <select
                      id="team-select"
                      name="team_id"
                      class="select select-bordered w-full"
                    >
                      <option value="">Select Team...</option>
                      <%= for team <- @teams do %>
                        <option value={team.id} selected={team.id == @selected_team_id}>
                          <%= team.name %>
                        </option>
                      <% end %>
                    </select>
                  </form>
                </div>
              <% end %>

              <!-- Week and Season -->
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label for="week" class="label">
                    <span class="label-text">Week</span>
                  </label>
                  <input
                    type="number"
                    id="week"
                    min="1"
                    max="18"
                    value={@week}
                    phx-change="week_changed"
                    class="input input-bordered w-full"
                  />
                </div>
                <div>
                  <label for="season" class="label">
                    <span class="label-text">Season</span>
                  </label>
                  <input
                    type="number"
                    id="season"
                    min="2020"
                    max="2030"
                    value={@season}
                    phx-change="season_changed"
                    class="input input-bordered w-full"
                  />
                </div>
              </div>

              <!-- Recommendation Type -->
              <div>
                <label class="label">
                  <span class="label-text">Recommendation Type</span>
                </label>
                <div class="space-y-2">
                  <label class="label cursor-pointer justify-start">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="lineup"
                      checked={@recommendation_type == :lineup}
                      phx-click="recommendation_type_changed"
                      phx-value-type="lineup"
                      class="radio radio-primary"
                    />
                    <span class="label-text ml-2">Lineup Optimization</span>
                  </label>
                  <label class="label cursor-pointer justify-start">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="trade"
                      checked={@recommendation_type == :trade}
                      phx-click="recommendation_type_changed"
                      phx-value-type="trade"
                      class="radio radio-primary"
                    />
                    <span class="label-text ml-2">Trade Analysis</span>
                  </label>
                  <label class="label cursor-pointer justify-start">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="pickups"
                      checked={@recommendation_type == :pickups}
                      phx-click="recommendation_type_changed"
                      phx-value-type="pickups"
                      class="radio radio-primary"
                    />
                    <span class="label-text ml-2">Free Agent Pickups</span>
                  </label>
                  <label class="label cursor-pointer justify-start">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="keepers"
                      checked={@recommendation_type == :keepers}
                      phx-click="recommendation_type_changed"
                      phx-value-type="keepers"
                      class="radio radio-primary"
                    />
                    <span class="label-text ml-2">Keeper Selection</span>
                  </label>
                  <label class="label cursor-pointer justify-start">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="dynasty"
                      checked={@recommendation_type == :dynasty}
                      phx-click="recommendation_type_changed"
                      phx-value-type="dynasty"
                      class="radio radio-primary"
                    />
                    <span class="label-text ml-2">Dynasty Planning</span>
                  </label>
                  <label class="label cursor-pointer justify-start">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="chat"
                      checked={@recommendation_type == :chat}
                      phx-click="recommendation_type_changed"
                      phx-value-type="chat"
                      class="radio radio-primary"
                    />
                    <span class="label-text ml-2">Chat with AI</span>
                  </label>
                </div>
              </div>
            </div>

              <!-- AI Connection Test -->
              <div class="pt-4 border-t border-base-300">
                <h4 class="font-semibold text-base-content mb-3">AI Connection</h4>
                <button
                  phx-click="test_ai_connection"
                  disabled={@loading}
                  class="btn btn-primary w-full"
                >
                  <%= if @loading, do: "Testing...", else: "Test AI Connection" %>
                </button>
              </div>
            </div>
          </div>

          <!-- Results Panel -->
          <div class="flex-1 min-w-0">
            <div class="card bg-base-100 shadow-xl h-fit">
              <div class="card-body">
                <div class="flex justify-between items-center mb-6">
                  <h3 class="card-title text-base-content text-xl">
                    <%= case @recommendation_type do %>
                      <% :lineup -> %> Lineup Optimization
                      <% :trade -> %> Trade Analysis
                      <% :pickups -> %> Free Agent Pickups
                      <% :keepers -> %> Keeper Selection
                      <% :dynasty -> %> Dynasty Planning
                      <% :chat -> %> Chat with AI Assistant
                      <% _ -> %> AI Recommendations
                    <% end %>
                  </h3>
                  <%= if @recommendation_result do %>
                    <button 
                      phx-click="clear_results" 
                      class="btn btn-error btn-sm"
                      title="Clear all recommendation results"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                      Clear Results
                    </button>
                  <% end %>
                </div>

                <%= if @recommendation_type == :lineup do %>
                  <div class="mb-6 p-4 bg-base-200 rounded-lg">
                    <h4 class="font-semibold text-base-content mb-4">Lineup Optimization</h4>
                    <p class="text-sm text-base-content opacity-80 mb-4">Get AI-powered lineup recommendations based on matchups, projections, and advanced analytics.</p>
                    <button
                      phx-click="get_lineup_recommendation"
                      disabled={@loading or is_nil(@selected_team_id)}
                      class={"btn btn-lg w-full #{if @loading, do: "btn-disabled", else: "btn-primary"}"}
                    >
                      <%= if @loading do %>
                        <span class="loading loading-spinner loading-sm mr-2"></span>
                        Analyzing Lineup...
                      <% else %>
                        Get AI Lineup Recommendation
                      <% end %>
                    </button>
                    <%= if is_nil(@selected_team_id) do %>
                      <div class="alert alert-warning mt-4">
                        <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
                        </svg>
                        <span class="text-sm">Please select a league and team to get recommendations.</span>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if @recommendation_type == :trade do %>
                  <div class="mb-6 p-4 bg-base-200 rounded-lg">
                    <h4 class="font-semibold text-base-content mb-4">Trade Analysis</h4>
                    <p class="text-sm text-base-content opacity-80 mb-4">Analyze trade proposals with AI-powered value assessment and strategic recommendations.</p>
                    <form phx-submit="analyze_trade" class="space-y-4">
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Players to Give</span>
                        </label>
                        <textarea
                          name="trade[give_players]"
                          rows="2"
                          placeholder="Enter player names or IDs, separated by commas"
                          class="textarea textarea-bordered w-full"
                        ></textarea>
                      </div>
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Players to Receive</span>
                        </label>
                        <textarea
                          name="trade[receive_players]"
                          rows="2"
                          placeholder="Enter player names or IDs, separated by commas"
                          class="textarea textarea-bordered w-full"
                        ></textarea>
                      </div>
                      <button
                        type="submit"
                        disabled={@loading or is_nil(@selected_team_id)}
                        class="btn btn-lg btn-primary w-full"
                      >
                        <%= if @loading do %>
                          <span class="loading loading-spinner loading-sm mr-2"></span>
                          Analyzing Trade...
                        <% else %>
                          Analyze Trade Proposal
                        <% end %>
                      </button>
                    </form>
                  </div>
                <% end %>

                <%= if @recommendation_type == :pickups do %>
                  <div class="mb-6 p-4 bg-base-200 rounded-lg">
                    <h4 class="font-semibold text-base-content mb-4">Free Agent Pickups</h4>
                    <p class="text-sm text-base-content opacity-80 mb-4">Find the best available players on waivers based on your team needs and upcoming matchups.</p>
                    <button
                      phx-click="get_pickup_recommendations"
                      disabled={@loading or is_nil(@selected_team_id)}
                      class="btn btn-lg btn-primary w-full"
                    >
                      <%= if @loading do %>
                        <span class="loading loading-spinner loading-sm mr-2"></span>
                        Analyzing Free Agents...
                      <% else %>
                        Get Pickup Recommendations
                      <% end %>
                    </button>
                    <%= if is_nil(@selected_team_id) do %>
                      <div class="alert alert-warning mt-4">
                        <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
                        </svg>
                        <span class="text-sm">Please select a league and team to get recommendations.</span>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if @recommendation_type == :keepers do %>
                  <div class="mb-6 p-4 bg-base-200 rounded-lg">
                    <h4 class="font-semibold text-base-content mb-4">Keeper Selection</h4>
                    <p class="text-sm text-base-content opacity-80 mb-4">Optimize your keeper selections based on value, cost, and long-term potential.</p>
                    <div class="space-y-4">
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Number of Keepers (optional)</span>
                        </label>
                        <input
                          type="number"
                          name="keeper_count"
                          min="1"
                          max="16"
                          placeholder="Auto-detect from league settings"
                          class="input input-bordered w-full"
                        />
                      </div>
                      <button
                        phx-click="get_keeper_recommendations"
                        disabled={@loading or is_nil(@selected_team_id)}
                        class="btn btn-lg btn-primary w-full"
                      >
                        <%= if @loading do %>
                          <span class="loading loading-spinner loading-sm mr-2"></span>
                          Optimizing Keepers...
                        <% else %>
                          Get Keeper Recommendations
                        <% end %>
                      </button>
                      <%= if is_nil(@selected_team_id) do %>
                        <div class="alert alert-warning mt-4">
                          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
                        </svg>
                        <span class="text-sm">Please select a league and team to get recommendations.</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%= if @recommendation_type == :dynasty do %>
                  <div class="mb-6 p-4 bg-base-200 rounded-lg">
                    <h4 class="font-semibold text-base-content mb-4">Dynasty Planning</h4>
                    <p class="text-sm text-base-content opacity-80 mb-4">Create a strategic dynasty plan based on your competitive window and roster construction.</p>
                    <div class="space-y-4">
                      <div>
                        <label class="label">
                          <span class="label-text font-medium">Planning Timeline</span>
                        </label>
                        <select name="dynasty_timeline" class="select select-bordered w-full">
                          <option value="immediate">Win Now (1-2 years)</option>
                          <option value="medium" selected>Balanced Approach (2-3 years)</option>
                          <option value="rebuild">Full Rebuild (3+ years)</option>
                        </select>
                      </div>
                      <button
                        phx-click="get_dynasty_plan"
                        disabled={@loading or is_nil(@selected_team_id)}
                        class="btn btn-lg btn-primary w-full"
                      >
                        <%= if @loading do %>
                          <span class="loading loading-spinner loading-sm mr-2"></span>
                          Creating Dynasty Plan...
                        <% else %>
                          Get Dynasty Plan
                        <% end %>
                      </button>
                      <%= if is_nil(@selected_team_id) do %>
                        <div class="alert alert-warning mt-4">
                          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
                        </svg>
                        <span class="text-sm">Please select a league and team to get recommendations.</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%= if @recommendation_type == :chat do %>
                  <div class="mb-6">
                    <div class="p-4 bg-base-200 rounded-lg mb-4">
                      <h4 class="font-semibold text-base-content mb-2">Chat with AI Assistant</h4>
                      <p class="text-sm text-base-content opacity-80">Get personalized advice for your team. Ask about lineups, trades, pickups, or strategy.</p>
                    </div>
                    
                    <!-- Chat History -->
                    <%= if length(@chat_messages) > 0 do %>
                      <div class="mb-4 max-h-96 overflow-y-auto border border-base-300 rounded-lg p-4 space-y-3 bg-base-50">
                        <%= for {message, index} <- Enum.with_index(@chat_messages) do %>
                          <div class={if message.role == :user, do: "chat chat-end", else: "chat chat-start"}>
                            <div class="chat-image avatar">
                              <div class="w-8 h-8 rounded-full bg-primary text-primary-content flex items-center justify-center text-xs font-bold">
                                <%= if message.role == :user, do: "U", else: "AI" %>
                              </div>
                            </div>
                            <div class="chat-header text-xs opacity-70 mb-1">
                              <%= if message.role == :user, do: "You", else: "AI Assistant" %>
                            </div>
                            <div class="chat-bubble max-w-md text-sm leading-relaxed">
                              <%= message.content %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% else %>
                      <div class="text-center p-8 bg-base-100 border-2 border-dashed border-base-300 rounded-lg mb-4">
                        <div class="w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-4">
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                          </svg>
                        </div>
                        <h5 class="text-lg font-medium mb-2 text-base-content">Start a conversation</h5>
                        <p class="text-sm text-base-content opacity-70">Ask questions like:</p>
                        <ul class="text-sm text-base-content opacity-70 mt-2 space-y-1">
                          <li>• "Who should I start this week?"</li>
                          <li>• "Should I accept this trade?"</li>
                          <li>• "What free agents should I target?"</li>
                        </ul>
                      </div>
                    <% end %>

                    <!-- Chat Input -->
                    <form phx-submit="send_chat_message" class="flex gap-2">
                      <input
                        type="text"
                        name="message"
                        value={@chat_input}
                        phx-change="update_chat_input"
                        placeholder="Ask your AI assistant anything about your team..."
                        class="input input-bordered flex-1"
                        disabled={@loading or is_nil(@selected_team_id)}
                      />
                      <button
                        type="submit"
                        disabled={@loading or is_nil(@selected_team_id) or @chat_input == ""}
                        class="btn btn-primary px-6"
                      >
                        <%= if @loading do %>
                          <span class="loading loading-spinner loading-sm"></span>
                        <% else %>
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
                          </svg>
                        <% end %>
                      </button>
                    </form>

                    <%= if is_nil(@selected_team_id) do %>
                      <div class="alert alert-warning mt-4">
                        <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
                        </svg>
                        <span class="text-sm">Please select a league and team to chat with AI about your roster.</span>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <!-- Results Display -->
                <%= if @recommendation_result do %>
                  <div class="mt-8">
                    <div class="divider divider-primary">
                      <span class="text-primary font-semibold">Results</span>
                    </div>
                    <div class="mt-6">
                      <%= case @recommendation_result.type do %>
                        <% :lineup -> %>
                          <%= render_lineup_recommendation(assigns, @recommendation_result.data) %>
                        <% :trade -> %>
                          <%= render_trade_analysis(assigns, @recommendation_result.data) %>
                        <% :pickups -> %>
                          <%= render_pickup_recommendations(assigns, @recommendation_result.data) %>
                        <% :keepers -> %>
                          <%= render_keeper_recommendations(assigns, @recommendation_result.data) %>
                        <% :dynasty -> %>
                          <%= render_dynasty_plan(assigns, @recommendation_result.data) %>
                        <% :connection_test -> %>
                          <%= render_connection_test(assigns, @recommendation_result.data) %>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Render helper functions
  defp render_lineup_recommendation(assigns, result) do
    assigns = assign(assigns, :result, result)
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300">
      <div class="p-6">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 bg-success/10 rounded-lg flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z" />
            </svg>
          </div>
          <h4 class="text-xl font-bold text-base-content">Optimized Lineup</h4>
        </div>
        
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <div>
            <h5 class="font-semibold text-base-content mb-4 text-lg">Starting Lineup</h5>
            <%= if @result[:lineup] && @result[:lineup]["starters"] do %>
              <div class="space-y-3">
                <%= for starter <- @result[:lineup]["starters"] do %>
                  <div class="flex justify-between items-center p-4 bg-success/5 border border-success/20 rounded-lg hover:bg-success/10 transition-colors">
                    <div>
                      <p class="font-semibold text-base-content text-lg"><%= starter["name"] %></p>
                      <p class="text-sm text-base-content opacity-70 font-medium"><%= starter["position"] %></p>
                    </div>
                    <div class="badge badge-success badge-lg">Start</div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-center p-8 bg-base-200 rounded-lg">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 text-base-content opacity-50 mx-auto mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <p class="text-base-content opacity-70">No starting lineup data available.</p>
              </div>
            <% end %>
          </div>

          <div>
            <h5 class="font-semibold text-base-content mb-4 text-lg">Analysis</h5>
            <div class="space-y-6">
              <%= if @result[:confidence] do %>
                <div class="p-4 bg-base-200 rounded-lg">
                  <p class="text-sm font-semibold text-base-content mb-2">Confidence Level</p>
                  <div class="flex items-center gap-3">
                    <div class="flex-1 bg-base-300 rounded-full h-3">
                      <div class="bg-primary h-3 rounded-full transition-all duration-500" style={"width: #{(@result[:confidence] * 100)}%"}></div>
                    </div>
                    <span class="text-sm font-bold text-base-content"><%= Float.round(@result[:confidence] * 100, 1) %>%</span>
                  </div>
                </div>
              <% end %>

              <%= if @result[:risk_level] do %>
                <div class="p-4 bg-base-200 rounded-lg">
                  <p class="text-sm font-semibold text-base-content mb-1">Risk Level</p>
                  <p class="text-base-content badge badge-outline badge-lg"><%= String.capitalize(@result[:risk_level]) %></p>
                </div>
              <% end %>

              <%= if @result[:reasoning] do %>
                <div class="p-4 bg-base-200 rounded-lg">
                  <p class="text-sm font-semibold text-base-content mb-2">AI Reasoning</p>
                  <p class="text-sm text-base-content leading-relaxed"><%= @result[:reasoning] %></p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_trade_analysis(assigns, analysis) do
    assigns = assign(assigns, :analysis, analysis)
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300">
      <div class="p-6">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 bg-warning/10 rounded-lg flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
            </svg>
          </div>
          <h4 class="text-xl font-bold text-base-content">Trade Analysis</h4>
        </div>
        
        <div class="space-y-6">
          <%= if @analysis[:recommendation] do %>
            <div class={"p-6 rounded-lg border-2 #{trade_recommendation_class(@analysis[:recommendation])}"}>
              <div class="flex items-center gap-3 mb-3">
                <%= trade_recommendation_icon(@analysis[:recommendation]) %>
                <h5 class="font-bold text-base-content text-lg">Recommendation</h5>
              </div>
              <p class="text-2xl font-bold mb-2 #{trade_recommendation_text_color(@analysis[:recommendation])}">
                <%= String.upcase(to_string(@analysis[:recommendation])) %>
              </p>
            </div>
          <% end %>

          <%= if @analysis[:analysis] do %>
            <div class="p-4 bg-base-200 rounded-lg">
              <h5 class="font-semibold text-base-content mb-3 flex items-center gap-2">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
                </svg>
                Analysis
              </h5>
              <p class="text-base-content leading-relaxed"><%= @analysis[:analysis] %></p>
            </div>
          <% end %>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <%= if @analysis[:confidence] do %>
              <div class="p-4 bg-base-200 rounded-lg">
                <p class="text-sm font-semibold text-base-content mb-3">Confidence Level</p>
                <div class="flex items-center gap-3">
                  <div class="flex-1 bg-base-300 rounded-full h-3">
                    <div class="bg-primary h-3 rounded-full transition-all duration-500" style={"width: #{(@analysis[:confidence] * 100)}%"}></div>
                  </div>
                  <span class="text-sm font-bold text-base-content"><%= Float.round(@analysis[:confidence] * 100, 1) %>%</span>
                </div>
              </div>
            <% end %>

            <%= if @analysis[:value_assessment] do %>
              <div class="p-4 bg-base-200 rounded-lg">
                <p class="text-sm font-semibold text-base-content mb-2">Value Assessment</p>
                <p class="badge badge-outline badge-lg"><%= String.replace(@analysis[:value_assessment], "_", " ") |> String.capitalize() %></p>
              </div>
            <% end %>
          </div>

          <%= if @analysis[:risk_factors] && length(@analysis[:risk_factors]) > 0 do %>
            <div class="p-4 bg-base-200 rounded-lg">
              <h5 class="font-semibold text-base-content mb-3 flex items-center gap-2">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16c-.77.833.192 2.5 1.732 2.5z" />
                </svg>
                Risk Factors
              </h5>
              <ul class="space-y-2">
                <%= for risk <- @analysis[:risk_factors] do %>
                  <li class="flex items-start gap-2">
                    <span class="w-2 h-2 bg-warning rounded-full mt-2 flex-shrink-0"></span>
                    <span class="text-sm text-base-content"><%= String.replace(risk, "_", " ") |> String.capitalize() %></span>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_connection_test(assigns, response) do
    assigns = assign(assigns, :response, response)
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300">
      <div class="p-6">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 bg-success/10 rounded-lg flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z" />
            </svg>
          </div>
          <h4 class="text-xl font-bold text-base-content">AI Connection Test</h4>
        </div>
        <div class="alert alert-success">
          <svg class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          <div>
            <h5 class="font-semibold">AI Connection Successful</h5>
            <p class="text-sm opacity-80">Your AI assistant is ready to help with fantasy football recommendations.</p>
          </div>
        </div>
        <div class="mt-4 p-4 bg-base-200 rounded-lg">
          <p class="text-xs font-semibold text-base-content opacity-70 mb-2">Response Details:</p>
          <pre class="text-xs text-base-content bg-base-300 p-3 rounded overflow-auto max-h-40"><%= inspect(@response, pretty: true, limit: :infinity) %></pre>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp current_week, do: 1
  defp current_season, do: Date.utc_today().year

  defp load_leagues(socket) do
    case League.read(load: [:fantasy_teams]) do
      {:ok, leagues} ->
        assign(socket, :leagues, leagues)
      {:error, _} ->
        assign(socket, leagues: [], error_message: "Failed to load leagues")
    end
  end

  defp load_teams_for_league(socket, league_id) when league_id != "" do
    league = Enum.find(socket.assigns.leagues, &(&1.id == league_id))
    teams = if league && league.fantasy_teams != %Ash.NotLoaded{} do
      league.fantasy_teams
    else
      []
    end
    assign(socket, :teams, teams)
  end
  defp load_teams_for_league(socket, _), do: assign(socket, :teams, [])

  defp recommendation_color(:accept), do: "bg-green-50 border-green-200"
  defp recommendation_color(:decline), do: "bg-red-50 border-red-200"
  defp recommendation_color(:negotiate), do: "bg-yellow-50 border-yellow-200"
  defp recommendation_color(_), do: "bg-gray-50 border-gray-200"

  defp recommendation_text_color(:accept), do: "text-green-800"
  defp recommendation_text_color(:decline), do: "text-red-800"
  defp recommendation_text_color(:negotiate), do: "text-yellow-800"
  defp recommendation_text_color(_), do: "text-gray-800"

  defp priority_badge_class("high"), do: "badge-error"
  defp priority_badge_class("medium"), do: "badge-warning"
  defp priority_badge_class("low"), do: "badge-info"
  defp priority_badge_class(_), do: "badge-neutral"

  defp trade_recommendation_class(:accept), do: "bg-success/10 border-success/30"
  defp trade_recommendation_class(:decline), do: "bg-error/10 border-error/30"
  defp trade_recommendation_class(:negotiate), do: "bg-warning/10 border-warning/30"
  defp trade_recommendation_class(_), do: "bg-base-200 border-base-300"

  defp trade_recommendation_text_color(:accept), do: "text-success"
  defp trade_recommendation_text_color(:decline), do: "text-error"
  defp trade_recommendation_text_color(:negotiate), do: "text-warning"
  defp trade_recommendation_text_color(_), do: "text-base-content"

  defp trade_recommendation_icon(:accept) do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-success" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="5 13l4 4L19 7" />
    </svg>
    """)
  end
  
  defp trade_recommendation_icon(:decline) do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="6 18L18 6M6 6l12 12" />
    </svg>
    """)
  end
  
  defp trade_recommendation_icon(:negotiate) do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="8 12h.01M12 12h.01M16 12h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    """)
  end
  
  defp trade_recommendation_icon(_) do
    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-base-content" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    """)
  end

  # Chat helper functions
  defp get_chat_response(message, team_id) do
    # For now, provide intelligent mock responses based on the user's message
    response = cond do
      String.contains?(String.downcase(message), ["start", "sit", "lineup"]) ->
        "Based on your current roster and this week's matchups, I'd recommend focusing on players with favorable matchups. Would you like me to run a full lineup optimization for you?"

      String.contains?(String.downcase(message), ["trade"]) ->
        "I can help analyze any trade proposals you're considering. Just let me know which players are involved and I'll evaluate the value for your team's competitive window."

      String.contains?(String.downcase(message), ["pickup", "waiver", "add"]) ->
        "I can recommend some pickup candidates from the waiver wire based on your team's needs. Would you like me to analyze the available free agents for you?"

      String.contains?(String.downcase(message), ["keeper"]) ->
        "Keeper decisions are crucial for long-term success. I can analyze your roster to suggest optimal keeper selections that balance cost and value. Would you like me to run keeper optimization?"

      String.contains?(String.downcase(message), ["dynasty"]) ->
        "Dynasty planning requires balancing immediate competitiveness with long-term value. I can help create a strategic plan based on your team's competitive window and roster construction."

      true ->
        "I understand you want help with: \"#{message}\". I can assist with lineup decisions, trade analysis, waiver pickups, keeper selections, and dynasty planning. What specific aspect would you like me to focus on?"
    end

    {:ok, response}
  end

  defp render_pickup_recommendations(assigns, recommendations) do
    assigns = assign(assigns, :recommendations, recommendations)
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300">
      <div class="p-6">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 bg-info/10 rounded-lg flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-info" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
            </svg>
          </div>
          <h4 class="text-xl font-bold text-base-content">Free Agent Pickup Recommendations</h4>
        </div>
        
        <%= if @recommendations[:pickups] && length(@recommendations[:pickups]) > 0 do %>
          <div class="grid gap-4">
            <%= for pickup <- @recommendations[:pickups] do %>
              <div class="p-4 bg-base-50 border border-base-200 rounded-lg hover:shadow-md transition-all">
                <div class="flex justify-between items-start mb-3">
                  <div class="flex-1">
                    <div class="flex items-center gap-3 mb-2">
                      <h5 class="font-bold text-base-content text-lg"><%= pickup["name"] || "Unknown Player" %></h5>
                      <%= if pickup["priority"] do %>
                        <div class={"badge badge-lg #{priority_badge_class(pickup["priority"])}"}>
                          <%= String.capitalize(pickup["priority"]) %> Priority
                        </div>
                      <% end %>
                    </div>
                    <p class="text-sm text-base-content opacity-70 font-medium mb-2">
                      <span class="badge badge-outline"><%= pickup["position"] || "N/A" %></span>
                      <span class="mx-2">•</span>
                      <span class="badge badge-outline"><%= pickup["team"] || "N/A" %></span>
                    </p>
                    <%= if pickup["reasoning"] do %>
                      <p class="text-sm text-base-content leading-relaxed"><%= pickup["reasoning"] %></p>
                    <% end %>
                  </div>
                </div>
                <%= if pickup["drop_candidate"] do %>
                  <div class="mt-3 p-3 bg-warning/10 border border-warning/20 rounded">
                    <p class="text-sm text-base-content">
                      <span class="font-semibold text-warning">Consider dropping:</span> 
                      <span class="font-medium"><%= pickup["drop_candidate"] %></span>
                    </p>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="text-center p-8 bg-base-200 rounded-lg">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-12 w-12 text-base-content opacity-50 mx-auto mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
            </svg>
            <p class="text-base-content opacity-70">No pickup recommendations available at this time.</p>
          </div>
        <% end %>

        <%= if @recommendations[:reasoning] do %>
          <div class="mt-6 p-4 bg-base-200 rounded-lg">
            <h5 class="font-semibold text-base-content mb-3 flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
              </svg>
              AI Analysis
            </h5>
            <p class="text-sm text-base-content leading-relaxed"><%= @recommendations[:reasoning] %></p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_keeper_recommendations(assigns, recommendations) do
    assigns = assign(assigns, :recommendations, recommendations)
    ~H"""
    <div>
      <h4 class="text-lg font-semibold text-base-content mb-4">Keeper Selection Recommendations</h4>
      
      <%= if @recommendations[:keepers] && length(@recommendations[:keepers]) > 0 do %>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h5 class="font-medium text-base-content mb-3">Recommended Keepers</h5>
            <div class="space-y-2">
              <%= for keeper <- @recommendations[:keepers] do %>
                <div class="flex justify-between items-center p-3 bg-primary/10 border border-primary/20 rounded">
                  <div>
                    <p class="font-medium text-base-content"><%= keeper["name"] || "Unknown Player" %></p>
                    <p class="text-sm text-base-content opacity-70"><%= keeper["position"] || "N/A" %></p>
                  </div>
                  <div class="text-right">
                    <%= if keeper["cost"] do %>
                      <p class="text-sm font-medium text-base-content">$<%= keeper["cost"] %></p>
                    <% end %>
                    <%= if keeper["value_rating"] do %>
                      <p class="text-xs text-base-content opacity-70"><%= keeper["value_rating"] %> Value</p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <div>
            <h5 class="font-medium text-base-content mb-3">Analysis</h5>
            <div class="space-y-4">
              <%= if @recommendations[:total_cost] do %>
                <div>
                  <p class="text-sm font-medium text-base-content">Total Keeper Cost</p>
                  <p class="text-lg font-semibold text-primary">$<%= @recommendations[:total_cost] %></p>
                </div>
              <% end %>

              <%= if @recommendations[:strategy] do %>
                <div>
                  <p class="text-sm font-medium text-base-content">Recommended Strategy</p>
                  <p class="text-sm text-base-content"><%= String.capitalize(@recommendations[:strategy]) %></p>
                </div>
              <% end %>

              <%= if @recommendations[:reasoning] do %>
                <div>
                  <p class="text-sm font-medium text-base-content">AI Reasoning</p>
                  <p class="text-sm text-base-content"><%= @recommendations[:reasoning] %></p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% else %>
        <p class="text-base-content opacity-70">No keeper recommendations available.</p>
      <% end %>
    </div>
    """
  end

  defp render_dynasty_plan(assigns, plan) do
    assigns = assign(assigns, :plan, plan)
    ~H"""
    <div>
      <h4 class="text-lg font-semibold text-base-content mb-4">Dynasty Planning Strategy</h4>
      
      <div class="space-y-6">
        <%= if @plan[:competitive_window] do %>
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-4">
              <h5 class="font-medium text-base-content mb-2">Competitive Window Analysis</h5>
              <p class="text-base-content"><%= @plan[:competitive_window] %></p>
            </div>
          </div>
        <% end %>

        <%= if @plan[:strategy] do %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <h5 class="font-medium text-base-content mb-3">Recommended Strategy</h5>
              <p class="text-base-content"><%= @plan[:strategy] %></p>
            </div>

            <%= if @plan[:timeline] do %>
              <div>
                <h5 class="font-medium text-base-content mb-3">Timeline</h5>
                <p class="text-base-content"><%= @plan[:timeline] %></p>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @plan[:key_players] && length(@plan[:key_players]) > 0 do %>
          <div>
            <h5 class="font-medium text-base-content mb-3">Key Players to Focus On</h5>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <%= for player <- @plan[:key_players] do %>
                <div class="p-3 bg-base-200 border border-base-300 rounded">
                  <div class="flex justify-between items-start">
                    <div>
                      <p class="font-medium text-base-content"><%= player["name"] || "Unknown Player" %></p>
                      <p class="text-sm text-base-content opacity-70"><%= player["position"] || "N/A" %> • Age: <%= player["age"] || "N/A" %></p>
                    </div>
                    <%= if player["action"] do %>
                      <div class="badge badge-secondary"><%= String.capitalize(player["action"]) %></div>
                    <% end %>
                  </div>
                  <%= if player["reasoning"] do %>
                    <p class="text-sm text-base-content opacity-80 mt-2"><%= player["reasoning"] %></p>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if @plan[:trade_targets] && length(@plan[:trade_targets]) > 0 do %>
          <div>
            <h5 class="font-medium text-base-content mb-3">Trade Targets</h5>
            <div class="space-y-2">
              <%= for target <- @plan[:trade_targets] do %>
                <div class="flex justify-between items-center p-3 bg-accent/10 border border-accent/20 rounded">
                  <div>
                    <p class="font-medium text-base-content"><%= target["name"] || "Unknown Player" %></p>
                    <p class="text-sm text-base-content opacity-70"><%= target["rationale"] || "Strategic fit" %></p>
                  </div>
                  <div class="badge badge-accent">Target</div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if @plan[:reasoning] do %>
          <div class="p-4 bg-base-200 rounded-lg">
            <h5 class="font-medium text-base-content mb-2">Strategic Analysis</h5>
            <p class="text-sm text-base-content"><%= @plan[:reasoning] %></p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end