defmodule Kastlex.API.V1.OffsetController do

  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions

  def show_offsets(conn, %{"topic" => topic, "partition" => partition} = params) do
    {partition, _} = Integer.parse(partition)
    at = Kastlex.KafkaUtils.parse_logical_offset(Map.get(params, "at", "latest"))
    case :brod_client.get_leader_connection(:kastlex, topic, partition) do
      {:ok, pid} ->
        case :brod_utils.resolve_offset(pid, topic, partition, at) do
          {:ok, offset} ->
            json(conn, %{offset: offset})
          {:error, _} = error ->
            send_resp(conn, 503, error)
        end
      {:error, :UnknownTopicOrPartition} ->
        {:ok, msg} = Poison.encode(%{error: "unknown topic or partition"})
        send_resp(conn, 404, msg)
      {:error, :LeaderNotAvailable} ->
        {:ok, msg} = Poison.encode(%{error: "unknown topic/partition or no leader for partition"})
        send_resp(conn, 404, msg)
      {:error, {:no_leader, _}} ->
        {:ok, msg} = Poison.encode(%{error: "unknown topic/partition or no leader for partition"})
        send_resp(conn, 404, msg)
    end
  end

end
