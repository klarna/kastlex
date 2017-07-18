defmodule Kastlex.Accept do
  import Plug.Conn
  require Logger

  @types Application.get_env(:mime, :types)

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "accept") do
      [accept] ->
        accept_options =
          String.split(accept, ",") |>
          Enum.map(fn(x) -> String.replace(x, ~r/;.*/, "") end)
        type = find_accept_header(accept_options, @types)
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

  defp find_accept_header([], _map), do: "*/*"
  defp find_accept_header([h | tail], map) do
    case Map.has_key?(map, h) do
      true -> Map.fetch(map, h)
      false -> find_accept_header(tail, map)
    end
  end
end
