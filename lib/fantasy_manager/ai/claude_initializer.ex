defmodule FantasyManager.AI.ClaudeInitializer do
  @moduledoc """
  Handles initialization of Claude AI backends.
  
  This module determines which Claude backend to use and initializes
  the appropriate resources (FLAME pool for claude-code, API clients, etc.).
  """
  
  require Logger
  
  alias FantasyManager.AI.{ClaudeCode, ClaudeRunner}
  
  @doc """
  Initialize the Claude backend.
  
  Determines which backend is available and starts necessary processes.
  Returns information about what backend was initialized.
  
  ## Returns
  {:ok, backend_info} | {:error, reason}
  """
  def initialize do
    Logger.info("Initializing Claude AI backend...")
    
    cond do
      api_key_available?() ->
        Logger.info("Anthropic API key found, using API backend")
        {:ok, %{backend: :api, status: :ready}}
      
      claude_cli_available?() ->
        Logger.info("Claude CLI available, initializing claude-code backend")
        initialize_claude_code()
      
      true ->
        Logger.warning("No Claude backend available, using mock responses")
        {:ok, %{backend: :mock, status: :ready, message: "Mock responses only"}}
    end
  end
  
  @doc """
  Get current backend status.
  """
  def status do
    backend = determine_backend()
    
    case backend do
      :api ->
        {:ok, %{backend: :api, status: :ready}}
      
      :claude_code ->
        case ClaudeCode.available?() do
          {:ok, version} ->
            pool_status = case ClaudeRunner.pool_status() do
              {:ok, %{status: status}} -> status
              _ -> :unknown
            end
            
            {:ok, %{
              backend: :claude_code, 
              status: :ready,
              version: version,
              pool_status: pool_status
            }}
          
          {:error, reason} ->
            {:error, "Claude CLI not available: #{reason}"}
        end
      
      :mock ->
        {:ok, %{backend: :mock, status: :ready}}
    end
  end
  
  # Private functions
  
  defp initialize_claude_code do
    case ClaudeCode.available?() do
      {:ok, version} ->
        Logger.info("Found claude-code version: #{version}")
        
        # Start FLAME pool
        case ClaudeRunner.start_pool() do
          {:ok, _pid} ->
            Logger.info("FLAME pool started successfully")
            {:ok, %{
              backend: :claude_code,
              status: :ready,
              version: version,
              pool_started: true
            }}
          
          {:error, :claude_not_available} ->
            Logger.warning("Claude CLI became unavailable during initialization")
            {:ok, %{
              backend: :claude_code,
              status: :ready_without_pool,
              version: version,
              pool_started: false,
              message: "Direct execution mode (no FLAME pool)"
            }}
          
          {:error, reason} ->
            Logger.error("Failed to start FLAME pool: #{inspect(reason)}")
            {:ok, %{
              backend: :claude_code,
              status: :ready_without_pool,
              version: version,
              pool_started: false,
              message: "Direct execution mode (FLAME pool failed)"
            }}
        end
      
      {:error, reason} ->
        Logger.error("Claude CLI not available: #{reason}")
        {:error, "Claude CLI initialization failed: #{reason}"}
    end
  end
  
  defp api_key_available? do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil -> false
      "" -> false
      _key -> true
    end
  end
  
  defp claude_cli_available? do
    case ClaudeCode.available?() do
      {:ok, _version} -> true
      {:error, _reason} -> false
    end
  end
  
  defp determine_backend do
    cond do
      api_key_available?() -> :api
      claude_cli_available?() -> :claude_code
      true -> :mock
    end
  end
end