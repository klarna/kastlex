defmodule Kastlex.API.V1.BrokerController do

  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions
  plug Plug.Statsd

  def list_brokers(conn, _params) do
    {:ok, brokers} = Kastlex.MetadataCache.get_brokers()
    json(conn, brokers)
  end

  def show_broker(conn, %{"broker" => id}) do
    {:ok, brokers} = Kastlex.MetadataCache.get_brokers()
    {id, _} = Integer.parse(id)
    case Enum.find(brokers, nil, fn(x) -> x.id == id end) do
      nil ->
        send_json(conn, 404, %{error: "unknown broker id"})
      broker ->
        json(conn, broker)
    end
  end

end
