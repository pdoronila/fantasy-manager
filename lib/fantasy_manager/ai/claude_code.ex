defmodule FantasyManager.AI.ClaudeCode do
  @moduledoc """
  Integration with local claude-code CLI for AI features.
  
  This module provides a wrapper around the claude CLI tool to enable
  AI functionality without requiring an Anthropic API key. Uses your
  local Claude Max subscription through claude-code.
  """
  
  require Logger
  
  @claude_cmd "claude"
  @default_timeout 60_000  # Increased to 60s as claude can take longer for complex requests
  @json_format "json"
  @text_format "text"
  
  @doc """
  Check if claude CLI is available on the system.
  
  ## Returns
  {:ok, version} | {:error, reason}
  """
  def available? do
    # Check if our SDK wrapper is available
    wrapper_path = Path.join(File.cwd!(), "claude_sdk_wrapper.js")
    
    case File.exists?(wrapper_path) do
      true ->
        # Test if the wrapper can run
        case System.cmd("node", [wrapper_path, "test"], stderr_to_stdout: true) do
          {_output, 0} -> 
            Process.put(:claude_path, wrapper_path)
            {:ok, "claude-sdk-wrapper"}
          {error_output, _exit_code} ->
            if String.contains?(error_output, "authentication") do
              {:error, "Claude SDK wrapper available but needs API key configuration"}
            else
              {:error, "Claude SDK wrapper failed: #{error_output}"}
            end
        end
      false ->
        {:error, "Claude SDK wrapper not found at #{wrapper_path}"}
    end
  end
  
  defp try_claude_paths([]), do: :error
  
  defp try_claude_paths([path | rest]) do
    # Handle Node.js files differently
    {cmd, args} = if String.ends_with?(path, ".js") do
      {"node", [path, "--version"]}
    else
      {path, ["--version"]}
    end
    
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} ->
        version = String.trim(output)
        {:ok, path, version}
      
      _ ->
        try_claude_paths(rest)
    end
  rescue
    _ -> try_claude_paths(rest)
  end
  
  @doc """
  Execute a prompt using claude CLI with JSON output.
  
  ## Parameters
  - prompt: String prompt to send to Claude
  - options: Keyword list of options
    - :timeout - Command timeout in milliseconds (default: 30_000)
    - :format - Output format "json" or "text" (default: "json")
    - :context - Additional context to prepend to prompt
  
  ## Returns
  {:ok, response} | {:error, reason}
  """
  def call_claude(prompt, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    format = Keyword.get(options, :format, @json_format)
    context = Keyword.get(options, :context)
    
    # Prepare the full prompt with context if provided
    full_prompt = if context do
      """
      #{context}
      
      #{prompt}
      """
    else
      prompt
    end
    
    # Build command arguments - append the prompt as the last argument
    args = ["-p", "--output-format", to_string(format), full_prompt]
    
    Logger.debug("Calling claude CLI with prompt length: #{String.length(full_prompt)}")
    
    # Use cached path or try to find it
    claude_path = Process.get(:claude_path) || find_claude_path()
    
    # Debug: Check environment
    Logger.debug("Claude path: #{claude_path}")
    Logger.debug("HOME env: #{System.get_env("HOME")}")
    Logger.debug("USER env: #{System.get_env("USER")}")
    Logger.debug("CWD: #{File.cwd!()}")
    
    # Use Task with timeout to prevent hanging
    task = Task.async(fn ->
      # Set up environment with claude-specific variables and shell variables
      env = [
        {"HOME", System.get_env("HOME")},
        {"USER", System.get_env("USER")},
        {"CLAUDE_CODE_ENTRYPOINT", "cli"},
        {"CLAUDECODE", "1"},
        {"PATH", System.get_env("PATH", "")},
        {"SHELL", System.get_env("SHELL", "/bin/bash")},
        {"TERM", System.get_env("TERM", "xterm-256color")}
      ]
      |> Enum.filter(fn {_k, v} -> v end)  # Remove nil values
      
      Logger.debug("Running claude with environment: #{inspect(env)}")
      Logger.debug("Command: #{claude_path} #{Enum.join(args, " ")}")
      
      # Use SDK wrapper instead of claude CLI
      wrapper_args = case format do
        @json_format -> [claude_path, full_prompt]
        @text_format -> [claude_path, "--output-format", "text", full_prompt]
        _ -> [claude_path, full_prompt]
      end
      
      Logger.debug("SDK wrapper execution - cmd: node, args: #{inspect(wrapper_args)}")
      
      # Capture stderr separately to avoid mixing with JSON output
      result = System.cmd("node", wrapper_args, 
                         stderr_to_stdout: false,  # Don't mix stderr with stdout
                         env: env, 
                         cd: File.cwd!())
      
      case result do
        {stdout, stderr, 0} -> 
          # 3-tuple format: Log any stderr messages but don't include in output
          if stderr != "", do: Logger.debug("Claude SDK stderr: #{stderr}")
          {stdout, 0}
        {stdout, stderr, exit_code} ->
          # 3-tuple format with error
          Logger.error("Claude SDK failed with exit code #{exit_code}, stderr: #{stderr}")
          {stdout, exit_code}
        {stdout, 0} ->
          # 2-tuple format: success case
          {stdout, 0}
        {stdout, exit_code} ->
          # 2-tuple format: error case
          Logger.error("Claude SDK failed with exit code #{exit_code}")
          {stdout, exit_code}
      end
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        parse_response(output, format)
        
      {:ok, {error_output, exit_code}} ->
        Logger.error("Claude CLI failed with exit code #{exit_code}: #{error_output}")
        {:error, "Claude CLI failed: #{error_output}"}
      
      nil ->
        Logger.error("Claude CLI timed out after #{timeout}ms")
        {:error, "Claude CLI request timed out. This may indicate authentication is required. Try running 'claude setup-token' to set up authentication."}
    end
  rescue
    error ->
      Logger.error("Claude CLI execution error: #{Exception.message(error)}")
      {:error, "Claude CLI execution failed: #{Exception.message(error)}"}
  end
  
  @doc """
  Call claude with fantasy football context for better responses.
  
  ## Parameters
  - prompt: The specific fantasy football question or request
  - fantasy_context: Map containing relevant fantasy data (team, league, players, etc.)
  - options: Additional options (same as call_claude/2)
  
  ## Returns
  {:ok, response} | {:error, reason}
  """
  def call_claude_with_fantasy_context(prompt, fantasy_context, options \\ []) do
    context = build_fantasy_context(fantasy_context)
    updated_options = Keyword.put(options, :context, context)
    
    call_claude(prompt, updated_options)
  end
  
  @doc """
  Test the claude CLI connection and functionality.
  
  ## Returns
  {:ok, %{status: "connected", version: version, test_response: response}} | {:error, reason}
  """
  def test_connection do
    with {:ok, version} <- available?(),
         {:ok, response} <- call_claude("What is 2+2? Please respond with just the number.", 
                                      format: "text", 
                                      timeout: 8_000) do
      {:ok, %{
        status: "connected",
        version: version,
        test_response: String.trim(response)
      }}
    else
      {:error, reason} -> 
        # For now, if claude-code is detected but not working, show a helpful message
        case available?() do
          {:ok, version} ->
            {:error, "Claude CLI (#{version}) detected but connection failed. Run 'claude setup-token' to authenticate with your Claude subscription."}
          {:error, _} ->
            {:error, reason}
        end
    end
  end
  
  # Private helper functions
  
  defp find_claude_path do
    # Try to find claude path if not cached (same order as available?)
    claude_paths = [
      "/Users/#{System.get_env("USER")}/.claude/local/node_modules/@anthropic-ai/claude-code/cli.js",
      "#{System.get_env("HOME")}/.claude/local/node_modules/@anthropic-ai/claude-code/cli.js",
      "/Users/#{System.get_env("USER")}/.claude/local/claude",
      System.find_executable("claude"),
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
      "#{System.get_env("HOME")}/.claude/local/claude"
    ]
    |> Enum.filter(& &1)
    
    case try_claude_paths(claude_paths) do
      {:ok, path, _version} -> 
        Process.put(:claude_path, path)
        path
      :error -> 
        @claude_cmd  # fallback to original command
    end
  end
  
  defp parse_response(output, @json_format) do
    case Jason.decode(output) do
      {:ok, %{"result" => result} = full_response} ->
        Logger.debug("Claude SDK wrapper JSON response parsed successfully")
        {:ok, Map.merge(full_response, %{"response" => result})}
        
      {:ok, %{"type" => "result", "subtype" => "success", "result" => result} = full_response} ->
        Logger.debug("Claude SDK wrapper success response parsed")
        {:ok, Map.merge(full_response, %{"response" => result})}
        
      {:ok, %{"type" => "result", "subtype" => "error", "error" => error}} ->
        Logger.error("Claude SDK wrapper returned error: #{error}")
        {:error, "Claude SDK error: #{error}"}
        
      {:ok, json_response} ->
        Logger.debug("Claude SDK returned JSON without expected fields: #{inspect(json_response)}")
        {:ok, json_response}
        
      {:error, decode_error} ->
        Logger.error("Failed to parse Claude SDK JSON response: #{inspect(decode_error)}")
        Logger.debug("Raw output: #{output}")
        {:error, "Failed to parse JSON response from Claude SDK"}
    end
  end
  
  defp parse_response(output, @text_format) do
    {:ok, String.trim(output)}
  end
  
  defp build_fantasy_context(fantasy_context) when is_map(fantasy_context) do
    context_parts = []
    
    context_parts = if team = fantasy_context[:team] do
      [format_team_context(team) | context_parts]
    else
      context_parts
    end
    
    context_parts = if league = fantasy_context[:league] do
      [format_league_context(league) | context_parts]
    else
      context_parts
    end
    
    context_parts = if players = fantasy_context[:players] do
      [format_players_context(players) | context_parts]
    else
      context_parts
    end
    
    context_parts = if week = fantasy_context[:week] do
      ["Current Week: #{week}" | context_parts]
    else
      context_parts
    end
    
    context_parts = if season = fantasy_context[:season] do
      ["Season: #{season}" | context_parts]
    else
      context_parts
    end
    
    base_context = """
    You are a fantasy football AI assistant. Please provide helpful, accurate advice based on the following context.
    Always format your responses as valid JSON when requested.
    """
    
    if Enum.empty?(context_parts) do
      base_context
    else
      base_context <> "\n\nContext:\n" <> Enum.join(Enum.reverse(context_parts), "\n\n")
    end
  end
  
  defp format_team_context(team) do
    """
    Team Information:
    - Name: #{team.name}
    - Owner: #{team.owner_name || "Unknown"}
    - Record: #{team.wins || 0}-#{team.losses || 0}
    - Competitive Window: #{team.competitive_window || "Neutral"}
    """
  end
  
  defp format_league_context(league) do
    """
    League Information:
    - Name: #{league.name}
    - Type: #{league.league_type}
    - Scoring: #{league.scoring_format}
    - Season: #{league.season}
    """
  end
  
  defp format_players_context(players) when is_list(players) do
    player_list = players
    |> Enum.take(10) # Limit to avoid huge context
    |> Enum.map(fn player -> 
      "- #{player.name} (#{player.position}) - #{player.nfl_team || "Free Agent"}"
    end)
    |> Enum.join("\n")
    
    """
    Relevant Players:
    #{player_list}
    """
  end
end