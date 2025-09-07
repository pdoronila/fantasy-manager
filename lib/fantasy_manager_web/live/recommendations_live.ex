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
  end

  def handle_event("clear_results", _params, socket) do
    {:noreply, assign(socket, recommendation_result: nil, error_message: nil)}
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
    <div class="min-h-screen bg-gray-50">
      <div class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center py-6">
            <div class="flex items-center">
              <h1 class="text-3xl font-bold text-gray-900">
                AI Recommendations
              </h1>
            </div>
            <div class="flex items-center space-x-4">
              <.link navigate={~p"/dashboard"} class="btn-secondary">
                ← Back to Dashboard
              </.link>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @error_message do %>
          <div class="bg-red-50 border border-red-200 rounded-md p-4 mb-6">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                </svg>
              </div>
              <div class="ml-3">
                <p class="text-sm text-red-800"><%= @error_message %></p>
              </div>
            </div>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <!-- Controls Panel -->
          <div class="lg:col-span-1">
            <div class="bg-white shadow rounded-lg p-6 space-y-6">
              <h3 class="text-lg font-medium text-gray-900">Settings</h3>
              
              <!-- League Selection -->
              <div>
                <label for="league-select" class="block text-sm font-medium text-gray-700 mb-2">
                  League
                </label>
                <select
                  id="league-select"
                  phx-change="league_changed"
                  class="w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
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
                  <label for="team-select" class="block text-sm font-medium text-gray-700 mb-2">
                    Team
                  </label>
                  <select
                    id="team-select"
                    phx-change="team_changed"
                    class="w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
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
                  <label for="week" class="block text-sm font-medium text-gray-700 mb-2">
                    Week
                  </label>
                  <input
                    type="number"
                    id="week"
                    min="1"
                    max="18"
                    value={@week}
                    phx-change="week_changed"
                    class="w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                  />
                </div>
                <div>
                  <label for="season" class="block text-sm font-medium text-gray-700 mb-2">
                    Season
                  </label>
                  <input
                    type="number"
                    id="season"
                    min="2020"
                    max="2030"
                    value={@season}
                    phx-change="season_changed"
                    class="w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                  />
                </div>
              </div>

              <!-- Recommendation Type -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Recommendation Type
                </label>
                <div class="space-y-2">
                  <label class="flex items-center">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="lineup"
                      checked={@recommendation_type == :lineup}
                      phx-click="recommendation_type_changed"
                      phx-value-type="lineup"
                      class="text-indigo-600 focus:ring-indigo-500"
                    />
                    <span class="ml-2 text-sm text-gray-700">Lineup Optimization</span>
                  </label>
                  <label class="flex items-center">
                    <input
                      type="radio"
                      name="recommendation_type"
                      value="trade"
                      checked={@recommendation_type == :trade}
                      phx-click="recommendation_type_changed"
                      phx-value-type="trade"
                      class="text-indigo-600 focus:ring-indigo-500"
                    />
                    <span class="ml-2 text-sm text-gray-700">Trade Analysis</span>
                  </label>
                </div>
              </div>
            </div>

            <!-- AI Connection Test -->
            <div class="bg-white shadow rounded-lg p-6 mt-6">
              <h4 class="text-md font-medium text-gray-900 mb-4">AI Connection</h4>
              <button
                phx-click="test_ai_connection"
                disabled={@loading}
                class="btn-secondary w-full"
              >
                <%= if @loading, do: "Testing...", else: "Test AI Connection" %>
              </button>
            </div>
          </div>

          <!-- Recommendation Panel -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow rounded-lg p-6">
              <div class="flex justify-between items-center mb-6">
                <h3 class="text-lg font-medium text-gray-900">
                  <%= case @recommendation_type do %>
                    <% :lineup -> %> Lineup Optimization
                    <% :trade -> %> Trade Analysis
                    <% _ -> %> AI Recommendations
                  <% end %>
                </h3>
                <%= if @recommendation_result do %>
                  <button phx-click="clear_results" class="text-gray-500 hover:text-gray-700">
                    Clear Results
                  </button>
                <% end %>
              </div>

              <%= if @recommendation_type == :lineup do %>
                <div class="mb-6">
                  <button
                    phx-click="get_lineup_recommendation"
                    disabled={@loading or is_nil(@selected_team_id)}
                    class="btn-primary"
                  >
                    <%= if @loading, do: "Optimizing...", else: "Get Lineup Recommendation" %>
                  </button>
                  <%= if is_nil(@selected_team_id) do %>
                    <p class="text-sm text-gray-500 mt-2">Select a league and team to get recommendations.</p>
                  <% end %>
                </div>
              <% end %>

              <%= if @recommendation_type == :trade do %>
                <form phx-submit="analyze_trade" class="mb-6">
                  <div class="space-y-4">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-2">
                        Players to Give (comma-separated player IDs)
                      </label>
                      <textarea
                        name="trade[give_players]"
                        rows="2"
                        placeholder="Enter player IDs separated by commas"
                        class="w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                      ></textarea>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-2">
                        Players to Receive (comma-separated player IDs)
                      </label>
                      <textarea
                        name="trade[receive_players]"
                        rows="2"
                        placeholder="Enter player IDs separated by commas"
                        class="w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                      ></textarea>
                    </div>
                    <button
                      type="submit"
                      disabled={@loading or is_nil(@selected_team_id)}
                      class="btn-primary"
                    >
                      <%= if @loading, do: "Analyzing...", else: "Analyze Trade" %>
                    </button>
                  </div>
                </form>
              <% end %>

              <!-- Results Display -->
              <%= if @recommendation_result do %>
                <div class="border-t pt-6">
                  <%= case @recommendation_result.type do %>
                    <% :lineup -> %>
                      <%= render_lineup_recommendation(assigns, @recommendation_result.data) %>
                    <% :trade -> %>
                      <%= render_trade_analysis(assigns, @recommendation_result.data) %>
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
end