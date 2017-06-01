defmodule Kastlex.Accept do
  import Plug.Conn
  require Logger

  @types Application.get_env(:mime, :types)

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "accept") do
      [accept] ->
        type = Map.fetch(@types, accept)
        _call(conn, type)
      [] ->
        _call(conn, {:ok, ["json"]})
    end
  end

  defp _call(conn, {:ok, [type]}) do
    assign(conn, :type, type)
  end
  defp _call(conn, _) do
    conn
    |> send_resp(404, "Not found")
    |> halt()
  end
end
