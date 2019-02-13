defmodule Kastlex.Helper do

  import Plug.Conn

  def send_json(conn, code, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, Jason.encode!(data))
  end

end
