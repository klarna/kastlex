defmodule Kastlex.PageController do
  use Kastlex.Web, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end

