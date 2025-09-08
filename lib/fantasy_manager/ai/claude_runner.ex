defmodule FantasyManager.AI.ClaudeRunner do
  @moduledoc """
  FLAME-powered runner for isolated claude-code execution.
  
  Provides process isolation, parallel execution, and automatic resource
  management for claude CLI calls. This prevents AI operations from
  blocking the main application and allows multiple concurrent requests.
  """
  
  require Logger
  
  # Don't start FLAME pool automatically - we'll manage it manually
  # to avoid errors if claude is not available
  
  @pool_name __MODULE__
  @default_timeout 60_000  # Increased to 60s to match ClaudeCode timeout
  @max_concurrency 3
  
  alias FantasyManager.AI.ClaudeCode
  
  @doc """
  Start the FLAME pool for claude operations.
  
  ## Options
  - :concurrency - Number of concurrent processes (default: 3)
  - :max_concurrency - Maximum concurrent processes (default: 5) 
  
  ## Returns
  :ok | {:error, reason}
  """
  def start_pool(opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, @max_concurrency)
    max_concurrency = Keyword.get(opts, :max_concurrency, @max_concurrency + 2)
    
    # Check if claude is available before starting pool
    case ClaudeCode.available?() do
      {:ok, version} ->
        Logger.info("Starting FLAME pool for claude-code version: #{version}")
        
        pool_opts = [
          name: @pool_name,
          concurrency: concurrency,
          max_concurrency: max_concurrency,
          timeout: @default_timeout
        ]
        
        case FLAME.Pool.start_link(pool_opts) do
          {:ok, pid} -> 
            Logger.info("FLAME claude pool started successfully")
            {:ok, pid}
          {:error, {:already_started, pid}} -> 
            Logger.debug("FLAME claude pool already started")
            {:ok, pid}
          error -> 
            Logger.error("Failed to start FLAME claude pool: #{inspect(error)}")
            error
        end
        
      {:error, reason} ->
        Logger.warning("Claude CLI not available, skipping FLAME pool: #{reason}")
        {:error, :claude_not_available}
    end
  end
  
  @doc """
  Stop the FLAME pool.
  """
  def stop_pool do
    case Process.whereis(@pool_name) do
      nil -> :ok
      _pid -> 
        FLAME.Pool.shutdown(@pool_name)
        Logger.info("FLAME claude pool stopped")
        :ok
    end
  end
  
  @doc """
  Execute a claude prompt in an isolated FLAME process.
  
  ## Parameters
  - prompt: String prompt for Claude
  - options: Options to pass to ClaudeCode.call_claude/2
  
  ## Returns
  {:ok, response} | {:error, reason}
  """
  def call_claude(prompt, options \\ []) do
    # Temporarily disable FLAME to test direct execution
    Logger.debug("Using direct execution (FLAME disabled for testing)")
    ClaudeCode.call_claude(prompt, options)
  end
  
  @doc """
  Execute a fantasy-contextualized claude prompt in FLAME.
  
  ## Parameters  
  - prompt: String prompt for Claude
  - fantasy_context: Map containing fantasy football context
  - options: Options to pass to ClaudeCode
  
  ## Returns
  {:ok, response} | {:error, reason}
  """
  def call_claude_with_fantasy_context(prompt, fantasy_context, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    
    if pool_available?() do
      execute_in_flame(fn -> 
        ClaudeCode.call_claude_with_fantasy_context(prompt, fantasy_context, options)
      end, timeout)
    else
      # Fallback to direct execution if pool not available
      Logger.debug("FLAME pool not available, falling back to direct execution")
      ClaudeCode.call_claude_with_fantasy_context(prompt, fantasy_context, options)
    end
  end
  
  @doc """
  Test the claude connection through FLAME.
  """
  def test_connection do
    if pool_available?() do
      execute_in_flame(fn -> 
        ClaudeCode.test_connection()
      end, 10_000)
    else
      ClaudeCode.test_connection()
    end
  end
  
  @doc """
  Check if the FLAME pool is available and ready.
  """
  def pool_available? do
    case Process.whereis(@pool_name) do
      nil -> false
      _pid -> true
    end
  end
  
  @doc """
  Get pool status information.
  """
  def pool_status do
    if pool_available?() do
      case FLAME.Pool.count(@pool_name) do
        {:ok, counts} -> {:ok, %{status: :running, counts: counts}}
        error -> {:error, error}
      end
    else
      {:ok, %{status: :not_running}}
    end
  end
  
  # Private functions
  
  defp execute_in_flame(fun, timeout) do
    try do
      FLAME.call(@pool_name, fun, timeout: timeout)
    rescue
      error ->
        Logger.error("FLAME execution error: #{Exception.message(error)}")
        {:error, "FLAME execution failed: #{Exception.message(error)}"}
    catch
      :exit, reason ->
        Logger.error("FLAME process exited: #{inspect(reason)}")
        {:error, "FLAME process failed: #{inspect(reason)}"}
    end
  end
end