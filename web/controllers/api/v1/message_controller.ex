defmodule Kastlex.API.V1.MessageController do

  require Logger
  require Record

  use Kastlex.Web, :controller

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kafka_message, extract(:kafka_message, from_lib: "brod/include/brod.hrl")


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

  def fetch(%{assigns: %{type: type}} = conn, params) do
    topic = params["topic"]
    {partition, _} = Integer.parse(params["partition"])
    orig_offset = Map.get(params, "offset", "latest")
    case :brod_client.get_partitions_count(Kastlex.get_brod_client_id(), topic) do
      {:ok, partitions_cnt} when partition >= 0 and partition < partitions_cnt ->
        case :brod_client.get_leader_connection(Kastlex.get_brod_client_id(), topic, partition) do
          {:ok, pid} ->
            case resolve_offset(pid, topic, partition, orig_offset) do
              {:ok, offset} ->
                {max_wait_time, _} = Integer.parse(Map.get(params, "max_wait_time", "1000"))
                {min_bytes, _} = Integer.parse(Map.get(params, "min_bytes", "1"))
                {max_bytes, _} = Integer.parse(Map.get(params, "max_bytes", "104857600")) # 100 kB
                req_fun =
                fn(max_bytes_try) ->
                  :kpro.fetch_request(topic, partition, offset, max_wait_time, min_bytes, max_bytes_try)
                end
                resp = do_fetch(pid, req_fun, max_bytes, offset, type)
                respond(conn, resp, type)
              {:error, :no_offsets} ->
                send_json(conn, 404, %{error: "No messages at the requested offset #{orig_offset}"})
              other ->
                Logger.error "Cannot resolve logical offset #{orig_offset}: #{inspect other}"
                send_json(conn, 503, %{error: "Cannot resolve logical offset #{orig_offset}"})
            end
          {:error, :UnknownTopicOrPartition} = error ->
            send_json(conn, 404, Map.new([error]))
          {:error, :LeaderNotAvailable} = error ->
            send_json(conn, 503, Map.new([error]))
        end
      {:error, :UnknownTopicOrPartition} = error ->
        send_json(conn, 404, Map.new([error]))
      {:error, _} = error ->
        send_json(conn, 503, Map.new([error]))
    end
  end

  defp do_fetch(sock_pid, req_fun, max_bytes, offset, type) do
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
            do_fetch(sock_pid, req_fun, size, offset, type)
          messages when type == "json" ->
            resp = %{highWmOffset: highWmOffset,
                     size: size,
                     messages: messages_to_map(messages)
                    }
            {:ok, resp}
          messages when type == "binary" ->
            resp = %{highWmOffset: highWmOffset,
                     size: size,
                     content: undefined_to_null(kafka_message(hd(messages), :value))
                    }
            {:ok, resp}
        end
    end
  end

  defp respond(conn, {:ok, resp}, "json"), do: json(conn, resp)
  defp respond(conn, {:ok, resp}, "binary") do
    conn
    |> put_resp_content_type("application/binary")
    |> put_resp_header("x-high-wm-offset", Integer.to_string(resp.highWmOffset))
    |> put_resp_header("x-message-size", Integer.to_string(resp.size))
    |> send_resp(200, resp.content)
  end
  defp respond(conn, {:error, reason}, "json") do
    send_json(conn, 503, %{error: reason})
  end
  defp respond(conn, {:error, reason}, "binary") do
    send_resp(conn, 503, "error: #{inspect reason}")
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

  defp resolve_offset(pid, t, p, orig_offset) do
    offset = Kastlex.KafkaUtils.parse_logical_offset(orig_offset)
    case offset < 0 do
      true ->
        do_resolve_offset(pid, t, p, offset)
      false ->
        {:ok, offset}
    end
  end

  defp do_resolve_offset(pid, t, p, logical_offset) do
    case :brod_utils.fetch_offsets(pid, t, p, logical_offset, 1) do
      {:ok, [offset]} ->
        case logical_offset == -1 do # latest
          true -> {:ok, offset-1}
          false -> {:ok, offset}
        end
      {:ok, []} ->
        {:error, :no_offsets}
      other ->
        other
    end
  end

end

