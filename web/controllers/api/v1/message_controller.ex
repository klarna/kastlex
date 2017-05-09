defmodule Kastlex.API.V1.MessageController do

  require Logger

  use Kastlex.Web, :controller

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
      {:error, :UnknownTopicOrPartition} = error ->
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
      {:error, :UnknownTopicOrPartition} = error ->
        Logger.error("#{inspect error}")
        # does not make sense to try other partitions
        send_json(conn, 404, Map.new([error]))
      {:error, {:producer_not_found, _topic}} = error ->
        Logger.error("#{inspect error}")
        # does not make sense to try other partitions
        send_json(conn, 404, Map.new([{:error, :UnknownTopicOrPartition}]))
      {:error, {:producer_not_found, _topic, _p}} = error ->
        Logger.error("#{inspect error}")
        # does not make sense to try other partitions
        send_json(conn, 404, Map.new([{:error, :UnknownTopicOrPartition}]))
      {:error, :LeaderNotAvailable} = error ->
        Logger.error("#{inspect error}")
        try_produce(conn, topic, partitions, key, value, error)
      {:error, :NotLeaderForPartition} = error ->
        Logger.error("#{inspect error}")
        try_produce(conn, topic, partitions, key, value, error)
      error ->
        Logger.error("#{inspect error}")
        send_json(conn, 503, Map.new([error]))
    end
  end

  def fetch(conn, %{"topic" => topic, "partition" => partition, "offset" => offset} = params) do
    {partition, _} = Integer.parse(partition)
    {offset, _} = Integer.parse(offset)
    {max_wait_time, _} = Integer.parse(Map.get(params, "max_wait_time", "1000"))
    {min_bytes, _} = Integer.parse(Map.get(params, "min_bytes", "1"))
    {max_bytes, _} = Integer.parse(Map.get(params, "max_bytes", "104857600")) # 100 kB
    case :brod_client.get_leader_connection(:kastlex, topic, partition) do
      {:ok, pid} ->
        req_fun =
          fn(max_bytes_try) ->
            :kpro.fetch_request(topic, partition, offset, max_wait_time, min_bytes, max_bytes_try)
          end
        case do_fetch(pid, req_fun, max_bytes, offset) do
          {:ok, resp} ->
            json(conn, resp)
          {:error, reason} ->
            send_json(conn, 503, %{error: reason})
        end
      {:error, :UnknownTopicOrPartition} ->
        send_json(conn, 404, %{error: "Unknown topic or partition"})
      {:error, :LeaderNotAvailable} ->
        send_json(conn, 404, %{error: "Leader not available"})
    end
  end

  defp messages_to_map(messages), do: messages_to_map(messages, [])

  defp messages_to_map([], acc), do: acc
  defp messages_to_map([msg | tail], acc) do
    {:kafka_message, offset, _magic_byte, _attributes, key, value, crc} = msg
    key = undefined_to_null(key)
    value = undefined_to_null(value)
    messages_to_map(tail, [%{offset: offset, crc: crc, key: key, value: value} | acc])
  end

  defp undefined_to_null(:undefined), do: nil
  defp undefined_to_null(x),          do: x

  defp do_fetch(sock_pid, req_fun, max_bytes, offset) do
    request = req_fun.(max_bytes)
    ## infinity here because brod_sock has a global 'request_timeout' option
    {:ok, response} = :brod_sock.request_sync(sock_pid, request, :infinity)
    {:kpro_FetchResponse, [topicFetchData]} = response
    {:kpro_FetchResponseTopic, _, [partitionFetchData]} = topicFetchData
    {:kpro_FetchResponsePartition, _, errorCode, highWmOffset, size, messages} = partitionFetchData
    case :kpro_ErrorCode.is_error(errorCode) do
      true ->
        {:error, :kpro_ErrorCode.desc(errorCode)}
      false ->
        case :brod_utils.map_messages(offset, messages) do
          {:incomplete_message, size} ->
            true = size > max_bytes # assert
            ## fetched back an incomplete message
            ## try again with the exact message size
            do_fetch(sock_pid, req_fun, size, offset)
          messages ->
            resp = %{errorCode: errorCode,
                     highWmOffset: highWmOffset,
                     size: size,
                     messages: messages_to_map(messages)
                    }
            {:ok, resp}
        end
    end
  end
end

