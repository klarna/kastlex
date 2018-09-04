defmodule Kastlex.API.V2.MessageController do

  require Logger
  require Record

  use Kastlex.Web, :controller

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kafka_message, extract(:kafka_message, from_lib: "kafka_protocol/include/kpro_public.hrl")
  defrecord :kpro_rsp, extract(:kpro_rsp, from_lib: "kafka_protocol/include/kpro.hrl")

  plug Kastlex.Plug.EnsurePermissions

  def produce(conn, %{"topic" => topic, "partition" => partition} = params) do
    {partition, _} = Integer.parse(partition)
    key = Map.get(params, "key", "")
    {:ok, value, conn} = read_body(conn)
    try_produce(conn, topic, [partition], key, value, nil)
  end

  # no partition, use random partitioner
  def produce(conn, %{"topic" => topic} = params) do
    key = Map.get(params, "key", "")
    {:ok, value, conn} = read_body(conn)
    case :brod_client.get_partitions_count(:kastlex, topic) do
      {:ok, partitions_cnt} ->
        partitions = :lists.seq(0, partitions_cnt - 1) |> Enum.shuffle
        try_produce(conn, topic, partitions, key, value, nil)
      {:error, :unknown_topic_or_partition} = error ->
        Logger.error("#{inspect error}")
        send_json(conn, 404, Map.new([error]))
      {:error, _} = error ->
        Logger.error("#{inspect error}")
        send_json(conn, 503, Map.new([error]))
    end
  end

  defp try_produce(conn, _topic, [], _key, _value, error) do
    Logger.error("#{inspect error}")
    send_json(conn, 503, Map.new([error]))
  end
  defp try_produce(conn, topic, [p | partitions], key, value, _last_error) do
    case :brod.produce_sync(:kastlex, topic, p, key, value) do
      :ok ->
        send_resp(conn, 204, "")
      {:error, :unknown_topic_or_partition} = error ->
        Logger.error("#{inspect error}")
        # does not make sense to try other partitions
        send_json(conn, 404, Map.new([error]))
      {:error, {:producer_not_found, _topic}} = error ->
        Logger.error("#{inspect error}")
        # does not make sense to try other partitions
        send_json(conn, 404, %{error: :unknown_topic_or_partition})
      {:error, {:producer_not_found, _topic, _p}} = error ->
        Logger.error("#{inspect error}")
        # does not make sense to try other partitions
        send_json(conn, 404, %{error: :unknown_topic_or_partition})
      {:error, :leader_not_available} = error ->
        Logger.error("#{inspect error}")
        try_produce(conn, topic, partitions, key, value, error)
      {:error, :not_leader_for_partition} = error ->
        Logger.error("#{inspect error}")
        try_produce(conn, topic, partitions, key, value, error)
      error ->
        Logger.error("#{inspect error}")
        send_json(conn, 503, Map.new([error]))
    end
  end

  def fetch(%{assigns: %{type: type}} = conn, params) do
    case Kastlex.API.Common.fetch(type, params) do
      {:ok, resp} ->
        respond(conn, resp, type)
      {:error, :unknown_topic_or_partition} ->
        send_json(conn, 404, %{error: :unknown_topic_or_partition})
      {:error, reason} ->
        send_json(conn, 503, %{error: reason})
    end
  end

  defp respond(conn, %{messages: messages, high_watermark: hw_offset}, "json") do
    conn
    |> put_resp_header("x-high-wm-offset", Integer.to_string(hw_offset))
    |> send_json(200, messages)
  end
  defp respond(conn, resp, "binary") do
    %{headers: headers, payload: payload, high_watermark: hw_offset} = resp
    conn
    |> put_resp_content_type("application/binary")
    |> put_resp_header("x-high-wm-offset", Integer.to_string(hw_offset))
    |> maybe_put_message_headers(headers)
    |> send_resp(200, payload)
  end

  defp maybe_put_message_headers(conn, nil), do: conn
  defp maybe_put_message_headers(conn, headers) do
    put_resp_header(conn, "x-message-headers", headers)
  end
end

