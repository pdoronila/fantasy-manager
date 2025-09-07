defmodule FantasyManager.AI.ClaudeConfig do
  @moduledoc """
  Claude API configuration and error handling for fantasy football AI features.
  
  Provides reliable Claude API integration with proper error handling,
  fallback responses, rate limiting, and structured tool calling.
  """
  
  require Logger
  
  @default_model "claude-3-5-sonnet-20241022"
  @default_max_tokens 4000
  @default_temperature 0.7
  @request_timeout 30_000
  @max_retries 3
  @retry_base_delay 1000
  
  @doc """
  Make a basic Claude API call with error handling and retries.
  
  ## Parameters
  - prompt: The user prompt to send to Claude
  - options: Optional parameters (model, max_tokens, temperature)
  
  ## Returns
  {:ok, response_text} | {:error, reason}
  """
  def call_claude(prompt, options \\ []) do
    model = Keyword.get(options, :model, @default_model)
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)
    temperature = Keyword.get(options, :temperature, @default_temperature)
    
    request_body = %{
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      messages: [
        %{
          role: "user",
          content: prompt
        }
      ]
    }
    
    case make_api_request(request_body) do
      {:ok, response} -> extract_text_response(response)
      {:error, reason} -> handle_api_error(reason, prompt)
    end
  end
  
  @doc """
  Make a Claude API call with tool calling capabilities.
  
  ## Parameters
  - prompt: The user prompt
  - tools: List of tool definitions for Claude to use
  - options: Optional parameters
  
  ## Returns
  {:ok, response} | {:error, reason}
  """
  def call_claude_with_tools(prompt, tools, options \\ []) do
    model = Keyword.get(options, :model, @default_model)
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)
    temperature = Keyword.get(options, :temperature, @default_temperature)
    
    request_body = %{
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      tools: format_tools_for_api(tools),
      messages: [
        %{
          role: "user",
          content: prompt
        }
      ]
    }
    
    case make_api_request(request_body) do
      {:ok, response} -> handle_tool_response(response, tools)
      {:error, reason} -> handle_api_error(reason, prompt)
    end
  end
  
  @doc """
  Test the Claude API connection and authentication.
  """
  def test_connection do
    test_prompt = "Please respond with exactly: 'Claude API connection successful'"
    
    case call_claude(test_prompt, max_tokens: 100) do
      {:ok, response} ->
        if String.contains?(response, "successful") do
          {:ok, %{status: :connected, response: response}}
        else
          {:ok, %{status: :connected_but_unexpected, response: response}}
        end
      
      {:error, reason} ->
        {:error, %{status: :failed, reason: reason}}
    end
  end
  
  @doc """
  Get the current API configuration and limits.
  """
  def get_config_info do
    %{
      model: @default_model,
      max_tokens: @default_max_tokens,
      temperature: @default_temperature,
      timeout: @request_timeout,
      max_retries: @max_retries,
      api_key_configured: api_key_configured?(),
      base_url: get_base_url()
    }
  end
  
  # Private functions
  
  defp make_api_request(request_body) do
    make_api_request_with_retry(request_body, @max_retries)
  end
  
  defp make_api_request_with_retry(request_body, retries_left) when retries_left > 0 do
    case perform_http_request(request_body) do
      {:ok, response} ->
        {:ok, response}
      
      {:error, :rate_limited} when retries_left > 1 ->
        delay = calculate_retry_delay(@max_retries - retries_left + 1)
        Logger.info("Rate limited, retrying in #{delay}ms")
        Process.sleep(delay)
        make_api_request_with_retry(request_body, retries_left - 1)
      
      {:error, :timeout} when retries_left > 1 ->
        delay = calculate_retry_delay(@max_retries - retries_left + 1)
        Logger.warning("Request timeout, retrying in #{delay}ms")
        Process.sleep(delay)
        make_api_request_with_retry(request_body, retries_left - 1)
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp make_api_request_with_retry(_request_body, 0) do
    {:error, :max_retries_exceeded}
  end
  
  defp perform_http_request(request_body) do
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{get_api_key()}"},
      {"anthropic-version", "2023-06-01"}
    ]
    
    body = Jason.encode!(request_body)
    url = "#{get_base_url()}/messages"
    
    case HTTPoison.post(url, body, headers, timeout: @request_timeout, recv_timeout: @request_timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, parsed_response} -> {:ok, parsed_response}
          {:error, _} -> {:error, :invalid_json_response}
        end
      
      {:ok, %HTTPoison.Response{status_code: 400, body: response_body}} ->
        handle_400_error(response_body)
      
      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :unauthorized}
      
      {:ok, %HTTPoison.Response{status_code: 429}} ->
        {:error, :rate_limited}
      
      {:ok, %HTTPoison.Response{status_code: 500}} ->
        {:error, :server_error}
      
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, {:unexpected_status, status_code}}
      
      {:error, %HTTPoison.Error{reason: :timeout}} ->
        {:error, :timeout}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end
  
  defp extract_text_response(%{"content" => [%{"text" => text}]}) do
    {:ok, text}
  end
  
  defp extract_text_response(%{"content" => content}) when is_list(content) do
    text_parts = 
      content
      |> Enum.filter(fn item -> Map.has_key?(item, "text") end)
      |> Enum.map(fn item -> item["text"] end)
      |> Enum.join("\n")
    
    if text_parts == "" do
      {:error, :no_text_in_response}
    else
      {:ok, text_parts}
    end
  end
  
  defp extract_text_response(response) do
    Logger.error("Unexpected response format: #{inspect(response)}")
    {:error, :unexpected_response_format}
  end
  
  defp handle_tool_response(response, _tools) do
    # Handle tool calling responses - this would be more complex in practice
    case extract_text_response(response) do
      {:ok, text} -> {:ok, text}
      error -> error
    end
  end
  
  defp handle_api_error(reason, prompt) do
    Logger.error("Claude API error: #{inspect(reason)} for prompt: #{String.slice(prompt, 0, 100)}...")
    
    case reason do
      :unauthorized ->
        {:error, "Claude API key is invalid or missing"}
      
      :rate_limited ->
        {:error, "Claude API rate limit exceeded, please try again later"}
      
      :timeout ->
        {:error, "Claude API request timed out"}
      
      :server_error ->
        fallback_response = generate_fallback_response(prompt)
        Logger.info("Using fallback response due to server error")
        {:ok, fallback_response}
      
      :max_retries_exceeded ->
        fallback_response = generate_fallback_response(prompt)
        Logger.info("Using fallback response after max retries exceeded")
        {:ok, fallback_response}
      
      _ ->
        {:error, "Claude API error: #{inspect(reason)}"}
    end
  end
  
  defp handle_400_error(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"error" => %{"type" => error_type, "message" => message}}} ->
        {:error, {:bad_request, error_type, message}}
      
      _ ->
        {:error, :bad_request}
    end
  end
  
  defp format_tools_for_api(tools) do
    # Convert Ash.ai tools to Claude API format
    Enum.map(tools, fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        input_schema: %{
          type: "object",
          properties: format_tool_properties(tool.arguments),
          required: get_required_properties(tool.arguments)
        }
      }
    end)
  end
  
  defp format_tool_properties(arguments) do
    Enum.into(arguments, %{}, fn {name, config} ->
      {to_string(name), %{
        type: map_type_to_json_schema(config.type),
        description: config.description
      }}
    end)
  end
  
  defp get_required_properties(arguments) do
    arguments
    |> Enum.filter(fn {_name, config} -> !Map.get(config, :optional, false) end)
    |> Enum.map(fn {name, _config} -> to_string(name) end)
  end
  
  defp map_type_to_json_schema(:string), do: "string"
  defp map_type_to_json_schema(:integer), do: "integer"
  defp map_type_to_json_schema(:float), do: "number"
  defp map_type_to_json_schema(:boolean), do: "boolean"
  defp map_type_to_json_schema({:array, _}), do: "array"
  defp map_type_to_json_schema(_), do: "string"
  
  defp generate_fallback_response(prompt) do
    cond do
      String.contains?(prompt, "lineup") ->
        generate_lineup_fallback()
      
      String.contains?(prompt, "trade") ->
        generate_trade_fallback()
      
      String.contains?(prompt, "projection") ->
        generate_projection_fallback()
      
      true ->
        generate_generic_fallback()
    end
  end
  
  defp generate_lineup_fallback do
    Jason.encode!(%{
      "lineup" => %{
        "starters" => [],
        "bench" => []
      },
      "reasoning" => "AI service temporarily unavailable. Please set lineup manually or try again later.",
      "confidence" => 0.0,
      "risk_level" => "unknown",
      "key_factors" => ["service_unavailable"]
    })
  end
  
  defp generate_trade_fallback do
    Jason.encode!(%{
      "recommendation" => "hold",
      "analysis" => "AI analysis service temporarily unavailable. Please review trade manually.",
      "confidence" => 0.0,
      "value_assessment" => "unknown",
      "risk_factors" => ["service_unavailable"],
      "suggested_counters" => []
    })
  end
  
  defp generate_projection_fallback do
    Jason.encode!(%{
      "projections" => [],
      "note" => "AI projection service temporarily unavailable. Using default projections."
    })
  end
  
  defp generate_generic_fallback do
    "AI service temporarily unavailable. Please try again later or contact support."
  end
  
  defp calculate_retry_delay(attempt) do
    @retry_base_delay * :math.pow(2, attempt - 1) |> round()
  end
  
  defp get_api_key do
    case Application.get_env(:fantasy_manager, :anthropic_api_key) do
      nil -> 
        System.get_env("ANTHROPIC_API_KEY") || 
        raise "ANTHROPIC_API_KEY environment variable is required"
      key -> key
    end
  end
  
  defp get_base_url do
    Application.get_env(:fantasy_manager, :anthropic_base_url, "https://api.anthropic.com/v1")
  end
  
  defp api_key_configured? do
    try do
      get_api_key()
      true
    rescue
      _ -> false
    end
  end
end