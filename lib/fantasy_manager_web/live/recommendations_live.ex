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
  def handle_event("league_changed", %{"league_id" => league_id}, socket) do
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
      socket = assign(socket, loading: true, error_message: nil)
      
      case RecommendationEngine.optimize_lineup(
        socket.assigns.selected_team_id,
        socket.assigns.week,
        socket.assigns.season
      ) do
        {:ok, result} ->
          socket =
            socket
            |> assign(:loading, false)
            |> assign(:recommendation_result, %{type: :lineup, data: result})

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:loading, false)
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
      %RuntimeError{message: "ANTHROPIC_API_KEY environment variable is required"} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error_message, "AI connection failed: ANTHROPIC_API_KEY environment variable is not configured. Please set your Claude API key to enable AI features.")

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
    {:noreply, assign(socket, recommendation_result: nil, error_message: nil)}
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
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

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <!-- Controls Panel -->
          <div class="lg:col-span-1">
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body space-y-6">
                <h3 class="card-title text-base-content">Settings</h3>
              
              <!-- League Selection -->
              <div>
                <label for="league-select" class="label">
                  <span class="label-text">League</span>
                </label>
                <select
                  id="league-select"
                  phx-change="league_changed"
                  class="select select-bordered w-full"
                >
                  <option value="">Select League...</option>
                  <%= for league <- @leagues do %>
                    <option value={league.id} selected={league.id == @selected_league_id}>
                      <%= league.name %> (<%= league.season %>)
                    </option>
                  <% end %>
                </select>
              </div>

              <!-- Team Selection -->
              <%= if @selected_league_id do %>
                <div>
                  <label for="team-select" class="label">
                    <span class="label-text">Team</span>
                  </label>
                  <select
                    id="team-select"
                    phx-change="team_changed"
                    class="select select-bordered w-full"
                  >
                    <option value="">Select Team...</option>
                    <%= for team <- @teams do %>
                      <option value={team.id} selected={team.id == @selected_team_id}>
                        <%= team.name %>
                      </option>
                    <% end %>
                  </select>
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
            <div class="card bg-base-100 shadow-xl mt-6">
              <div class="card-body">
                <h4 class="card-title text-base-content">AI Connection</h4>
                <button
                  phx-click="test_ai_connection"
                  disabled={@loading}
                  class="btn btn-secondary w-full"
                >
                  <%= if @loading, do: "Testing...", else: "Test AI Connection" %>
                </button>
              </div>
            </div>
          </div>

          <!-- Recommendation Panel -->
          <div class="lg:col-span-2">
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <div class="flex justify-between items-center mb-6">
                  <h3 class="card-title text-base-content">
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
                    <button phx-click="clear_results" class="btn btn-ghost btn-sm">
                      Clear Results
                    </button>
                  <% end %>
                </div>

              <%= if @recommendation_type == :lineup do %>
                <div class="mb-6">
                  <button
                    phx-click="get_lineup_recommendation"
                    disabled={@loading or is_nil(@selected_team_id)}
                    class="btn btn-primary"
                  >
                    <span class={@loading && "loading loading-spinner"}></span>
                    <%= if @loading, do: "Optimizing...", else: "Get Lineup Recommendation" %>
                  </button>
                  <%= if is_nil(@selected_team_id) do %>
                    <p class="text-sm text-base-content opacity-70 mt-2">Select a league and team to get recommendations.</p>
                  <% end %>
                </div>
              <% end %>

              <%= if @recommendation_type == :trade do %>
                <form phx-submit="analyze_trade" class="mb-6">
                  <div class="space-y-4">
                    <div>
                      <label class="label">
                        <span class="label-text">Players to Give (comma-separated player IDs)</span>
                      </label>
                      <textarea
                        name="trade[give_players]"
                        rows="2"
                        placeholder="Enter player IDs separated by commas"
                        class="textarea textarea-bordered w-full"
                      ></textarea>
                    </div>
                    <div>
                      <label class="label">
                        <span class="label-text">Players to Receive (comma-separated player IDs)</span>
                      </label>
                      <textarea
                        name="trade[receive_players]"
                        rows="2"
                        placeholder="Enter player IDs separated by commas"
                        class="textarea textarea-bordered w-full"
                      ></textarea>
                    </div>
                    <button
                      type="submit"
                      disabled={@loading or is_nil(@selected_team_id)}
                      class="btn btn-primary"
                    >
                      <span class={@loading && "loading loading-spinner"}></span>
                      <%= if @loading, do: "Analyzing...", else: "Analyze Trade" %>
                    </button>
                  </div>
                </form>
              <% end %>

              <%= if @recommendation_type == :pickups do %>
                <div class="mb-6">
                  <button
                    phx-click="get_pickup_recommendations"
                    disabled={@loading or is_nil(@selected_team_id)}
                    class="btn btn-primary"
                  >
                    <span class={@loading && "loading loading-spinner"}></span>
                    <%= if @loading, do: "Analyzing Free Agents...", else: "Get Pickup Recommendations" %>
                  </button>
                  <%= if is_nil(@selected_team_id) do %>
                    <p class="text-sm text-base-content opacity-70 mt-2">Select a league and team to get pickup recommendations.</p>
                  <% end %>
                </div>
              <% end %>

              <%= if @recommendation_type == :keepers do %>
                <div class="mb-6">
                  <div class="space-y-4">
                    <div>
                      <label class="label">
                        <span class="label-text">Number of Keepers (optional)</span>
                      </label>
                      <input
                        type="number"
                        name="keeper_count"
                        min="1"
                        max="16"
                        placeholder="Auto-detect from league"
                        class="input input-bordered w-full"
                      />
                    </div>
                    <button
                      phx-click="get_keeper_recommendations"
                      disabled={@loading or is_nil(@selected_team_id)}
                      class="btn btn-primary"
                    >
                      <span class={@loading && "loading loading-spinner"}></span>
                      <%= if @loading, do: "Optimizing Keepers...", else: "Get Keeper Recommendations" %>
                    </button>
                    <%= if is_nil(@selected_team_id) do %>
                      <p class="text-sm text-base-content opacity-70 mt-2">Select a league and team to get keeper recommendations.</p>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @recommendation_type == :dynasty do %>
                <div class="mb-6">
                  <div class="space-y-4">
                    <div>
                      <label class="label">
                        <span class="label-text">Planning Timeline</span>
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
                      class="btn btn-primary"
                    >
                      <span class={@loading && "loading loading-spinner"}></span>
                      <%= if @loading, do: "Creating Dynasty Plan...", else: "Get Dynasty Plan" %>
                    </button>
                    <%= if is_nil(@selected_team_id) do %>
                      <p class="text-sm text-base-content opacity-70 mt-2">Select a league and team to get dynasty planning advice.</p>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%= if @recommendation_type == :chat do %>
                <div class="mb-6">
                  <!-- Chat History -->
                  <%= if length(@chat_messages) > 0 do %>
                    <div class="mb-4 max-h-96 overflow-y-auto border border-base-300 rounded-lg p-4 space-y-3">
                      <%= for {message, index} <- Enum.with_index(@chat_messages) do %>
                        <div class={if message.role == :user, do: "chat chat-end", else: "chat chat-start"}>
                          <div class="chat-image avatar">
                            <div class="w-10 rounded-full bg-primary text-primary-content flex items-center justify-center text-sm">
                              <%= if message.role == :user, do: "U", else: "AI" %>
                            </div>
                          </div>
                          <div class="chat-header text-xs opacity-70">
                            <%= if message.role == :user, do: "You", else: "AI Assistant" %>
                            <time class="text-xs opacity-50"><%= message.timestamp %></time>
                          </div>
                          <div class="chat-bubble">
                            <%= message.content %>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="text-center p-8 text-base-content opacity-70">
                      <h5 class="text-lg font-medium mb-2">Start a conversation with your AI Assistant</h5>
                      <p class="text-sm">Ask questions like "Who should I start this week?" or "Should I accept this trade?"</p>
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
                      class="btn btn-primary"
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
                    <p class="text-sm text-base-content opacity-70 mt-2">Select a league and team to chat with AI about your roster.</p>
                  <% end %>
                </div>
              <% end %>

              <!-- Results Display -->
              <%= if @recommendation_result do %>
                <div class="divider"></div>
                <div class="pt-6">
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
              <% end %>
              </div>
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
    <div>
      <h4 class="text-lg font-semibold text-gray-900 mb-4">Optimized Lineup</h4>
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <h5 class="font-medium text-gray-900 mb-3">Starting Lineup</h5>
          <%= if @result[:lineup] && @result[:lineup]["starters"] do %>
            <div class="space-y-2">
              <%= for starter <- @result[:lineup]["starters"] do %>
                <div class="flex justify-between items-center p-3 bg-green-50 border border-green-200 rounded">
                  <div>
                    <p class="font-medium text-gray-900"><%= starter["name"] %></p>
                    <p class="text-sm text-gray-500"><%= starter["position"] %></p>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-gray-500">No starting lineup data available.</p>
          <% end %>
        </div>

        <div>
          <h5 class="font-medium text-gray-900 mb-3">Analysis</h5>
          <div class="space-y-4">
            <%= if @result[:confidence] do %>
              <div>
                <p class="text-sm font-medium text-gray-700">Confidence Level</p>
                <div class="mt-1 bg-gray-200 rounded-full h-2">
                  <div class="bg-indigo-600 h-2 rounded-full" style={"width: #{(@result[:confidence] * 100)}%"}></div>
                </div>
                <p class="text-xs text-gray-500 mt-1"><%= Float.round(@result[:confidence] * 100, 1) %>%</p>
              </div>
            <% end %>

            <%= if @result[:risk_level] do %>
              <div>
                <p class="text-sm font-medium text-gray-700">Risk Level</p>
                <p class="text-sm text-gray-600"><%= String.capitalize(@result[:risk_level]) %></p>
              </div>
            <% end %>

            <%= if @result[:reasoning] do %>
              <div>
                <p class="text-sm font-medium text-gray-700">AI Reasoning</p>
                <p class="text-sm text-gray-600 mt-1"><%= @result[:reasoning] %></p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_trade_analysis(assigns, analysis) do
    assigns = assign(assigns, :analysis, analysis)
    ~H"""
    <div>
      <h4 class="text-lg font-semibold text-gray-900 mb-4">Trade Analysis</h4>
      
      <div class="space-y-6">
        <%= if @analysis[:recommendation] do %>
          <div class={"p-4 rounded-lg #{recommendation_color(@analysis[:recommendation])}"}>
            <h5 class="font-medium text-gray-900 mb-2">Recommendation</h5>
            <p class={"text-lg font-semibold #{recommendation_text_color(@analysis[:recommendation])}"}>
              <%= String.upcase(to_string(@analysis[:recommendation])) %>
            </p>
          </div>
        <% end %>

        <%= if @analysis[:analysis] do %>
          <div>
            <h5 class="font-medium text-gray-900 mb-2">Analysis</h5>
            <p class="text-gray-700"><%= @analysis[:analysis] %></p>
          </div>
        <% end %>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%= if @analysis[:confidence] do %>
            <div>
              <p class="text-sm font-medium text-gray-700 mb-1">Confidence Level</p>
              <div class="bg-gray-200 rounded-full h-2">
                <div class="bg-indigo-600 h-2 rounded-full" style={"width: #{(@analysis[:confidence] * 100)}%"}></div>
              </div>
              <p class="text-xs text-gray-500 mt-1"><%= Float.round(@analysis[:confidence] * 100, 1) %>%</p>
            </div>
          <% end %>

          <%= if @analysis[:value_assessment] do %>
            <div>
              <p class="text-sm font-medium text-gray-700">Value Assessment</p>
              <p class="text-sm text-gray-600"><%= String.replace(@analysis[:value_assessment], "_", " ") |> String.capitalize() %></p>
            </div>
          <% end %>
        </div>

        <%= if @analysis[:risk_factors] && length(@analysis[:risk_factors]) > 0 do %>
          <div>
            <h5 class="font-medium text-gray-900 mb-2">Risk Factors</h5>
            <ul class="list-disc list-inside space-y-1">
              <%= for risk <- @analysis[:risk_factors] do %>
                <li class="text-sm text-gray-600"><%= String.replace(risk, "_", " ") |> String.capitalize() %></li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_connection_test(assigns, response) do
    assigns = assign(assigns, :response, response)
    ~H"""
    <div>
      <h4 class="text-lg font-semibold text-gray-900 mb-4">AI Connection Test</h4>
      <div class="bg-green-50 border border-green-200 rounded p-4">
        <div class="flex items-center">
          <svg class="h-5 w-5 text-green-400 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          <p class="text-green-800 font-medium">AI Connection Successful</p>
        </div>
        <pre class="mt-2 text-sm text-green-700 bg-green-100 p-2 rounded overflow-auto"><%= inspect(@response, pretty: true) %></pre>
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
    teams = if league && league.fantasy_teams != %Ash.NotLoaded{}, do: league.fantasy_teams, else: []
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
    <div>
      <h4 class="text-lg font-semibold text-base-content mb-4">Free Agent Pickup Recommendations</h4>
      
      <%= if @recommendations[:pickups] && length(@recommendations[:pickups]) > 0 do %>
        <div class="space-y-4">
          <%= for pickup <- @recommendations[:pickups] do %>
            <div class="card bg-base-200 border border-base-300">
              <div class="card-body p-4">
                <div class="flex justify-between items-start">
                  <div>
                    <h5 class="font-medium text-base-content"><%= pickup["name"] || "Unknown Player" %></h5>
                    <p class="text-sm text-base-content opacity-70"><%= pickup["position"] || "N/A" %> • <%= pickup["team"] || "N/A" %></p>
                    <%= if pickup["reasoning"] do %>
                      <p class="text-sm text-base-content mt-2"><%= pickup["reasoning"] %></p>
                    <% end %>
                  </div>
                  <%= if pickup["priority"] do %>
                    <div class="badge badge-primary"><%= String.capitalize(pickup["priority"]) %> Priority</div>
                  <% end %>
                </div>
                <%= if pickup["drop_candidate"] do %>
                  <div class="mt-2 text-sm text-base-content opacity-70">
                    <strong>Consider dropping:</strong> <%= pickup["drop_candidate"] %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-base-content opacity-70">No pickup recommendations available.</p>
      <% end %>

      <%= if @recommendations[:reasoning] do %>
        <div class="mt-6 p-4 bg-base-200 rounded-lg">
          <h5 class="font-medium text-base-content mb-2">AI Analysis</h5>
          <p class="text-sm text-base-content"><%= @recommendations[:reasoning] %></p>
        </div>
      <% end %>
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