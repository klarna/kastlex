defmodule Kastlex.Accept do
  import Plug.Conn
  require Logger

  @types Application.get_env(:mime, :types)

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "accept") do
      [accept] ->
        Logger.debug "accept header: #{inspect accept}"
        accept_options =
          String.split(accept, ",") |>
          Enum.map(fn(x) -> String.replace(x, ~r/;.*/, "") end)
        type = fetch_first_available(@types, accept_options)
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

  defp fetch_first_available(types, []) do
    Map.fetch(types, "*/*")
  end
  defp fetch_first_available(types, [t | accept_options]) do
    case Map.fetch(types, t) do
      {:ok, type} ->
        {:ok, type}
      _ ->
        fetch_first_available(types, accept_options)
    end
  end
end
