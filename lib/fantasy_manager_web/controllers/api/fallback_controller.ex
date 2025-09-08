defmodule FantasyManagerWeb.Api.FallbackController do
  @moduledoc """
  Fallback controller for handling API errors consistently.
  """
  
  use FantasyManagerWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Resource not found"})
  end
  
  def call(conn, {:error, :not_found, message}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: message})
  end

  def call(conn, {:error, :internal_error}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Internal server error"})
  end

  def call(conn, {:error, :internal_error, message}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: message})
  end

  def call(conn, {:error, :service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Service unavailable"})
  end

  def call(conn, {:error, :service_unavailable, message}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: message})
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Bad request"})
  end

  def call(conn, {:error, :bad_request, message}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end

  # Handle generic errors
  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "An unexpected error occurred"})
  end
end