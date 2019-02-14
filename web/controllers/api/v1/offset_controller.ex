defmodule Kastlex.API.V1.OffsetController do

  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions

  def show_offsets(conn, %{"topic" => topic, "partition" => partition} = params) do
    {partition, _} = Integer.parse(partition)
    at = Map.get(params, "at", "latest")
    client_id = Kastlex.get_brod_client_id()
    case :brod_client.get_leader_connection(client_id, topic, partition) do
      {:ok, pid} ->
        case Kastlex.KafkaUtils.resolve_offset(pid, topic, partition, at) do
          {:ok, offset} ->
            json(conn, %{offset: offset})
          {:error, _} = error ->
            send_resp(conn, 503, error)
        end
      {:error, :unknown_topic_or_partition} ->
        send_resp(conn, 404, Jason.encode!(%{error: "unknown topic or partition"}))
      {:error, :leader_not_available} ->
        send_resp(conn, 404, Jason.encode!(%{error: "unknown topic/partition or no leader for partition"}))
      {:error, reason} when is_binary(reason) ->
        send_resp(conn, 503, Jason.encode!(%{error: reason}))
      {:error, reason} ->
        send_resp(conn, 503, Jason.encode!(%{error: "#{inspect reason}"}))
    end
  end
end
