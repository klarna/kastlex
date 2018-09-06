defmodule Kastlex.API.V1.MessageController do
  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions

  def produce(conn, %{"topic" => topic, "partition" => partition} = params) do
    {partition, _} = Integer.parse(partition)
    key = Map.get(params, "key", "")
    {value, conn} = read_value(conn)
    try_produce(conn, topic, [partition], key, value, nil)
  end

  # no partition, use random partitioner
  def produce(conn, %{"topic" => topic} = params) do
    key = Map.get(params, "key", "")
    {value, conn} = read_value(conn)
    case :brod_client.get_partitions_count(:kastlex, topic) do
      {:ok, partitions_cnt} ->
        partitions = 0..partitions_cnt - 1 |> Enum.shuffle
        try_produce(conn, topic, partitions, key, value, nil)
      {:error, :unknown_topic_or_partition} = error ->
        Logger.error("#{inspect error}")
        send_json(conn, 404, Map.new([error]))
      {:error, _} = error ->
        Logger.error("#{inspect error}")
        send_json(conn, 503, Map.new([error]))
    end
  end

  def fetch(%{assigns: %{type: type}} = conn, params) do
    case Kastlex.KafkaUtils.fetch(type, params) do
      {:ok, %{messages: messages,
              high_watermark: hw_offset}} ->
        data = %{error_code: :no_error, # compatibility
                 size: nil, # compatibility
                 highWmOffset: hw_offset,
                 messages: messages}
        json(conn, data)
      {:ok, %{headers: headers,
              high_watermark: hw_offset,
              payload: payload
             }} ->
        conn
        |> put_resp_content_type("application/binary")
        |> put_resp_header("x-high-wm-offset", Integer.to_string(hw_offset))
        |> maybe_put_message_headers(headers)
        |> send_resp(200, payload)
      {:error, :unknown_topic_or_partition} ->
        send_json(conn, 404, %{error: :unknown_topic_or_partition})
      {:error, reason} ->
        send_json(conn, 503, %{error: reason})
    end
  end

  defp read_value(conn) do
    {:ok, value, conn} = read_body(conn)
    headers = read_headers(conn)
    {%{value: value, headers: headers}, conn}
  end

  defp read_headers(conn) do
    case get_req_header(conn, "x-message-headers") do
      [] -> []
      json ->
        {:ok, map} = Poison.decode(json)
        Map.to_list(map)
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

  defp maybe_put_message_headers(conn, nil), do: conn
  defp maybe_put_message_headers(conn, headers) do
    put_resp_header(conn, "x-message-headers", headers)
  end
end

