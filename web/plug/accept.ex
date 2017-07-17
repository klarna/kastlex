defmodule Kastlex.Accept do
  import Plug.Conn
  require Logger

  @types Application.get_env(:mime, :types)

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "accept") do
      [accept] ->
        accept = String.split(accept, ",")
        type = fetch_first_available(@types, accept)
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

  defp fetch_first_available(_types, []), do: :error
  defp fetch_first_available(types, [t | accept]) do
    case Map.fetch(types, t) do
      {:ok, type} ->
        {:ok, type}
      _ ->
        fetch_first_available(types, accept)
    end
  end
end
