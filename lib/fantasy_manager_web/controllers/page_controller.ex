defmodule FantasyManagerWeb.PageController do
  use FantasyManagerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
