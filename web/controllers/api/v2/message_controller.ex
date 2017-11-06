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
                fetch = :brod_utils.make_fetch_fun(pid, topic, partition, max_wait_time, min_bytes, max_bytes)
                response = fetch.(offset) |> handle_fetch_response(type)
                respond(conn, response, type)
              error ->
                Logger.error "Cannot resolve logical offset #{orig_offset}: #{inspect error}"
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

  defp handle_fetch_response({:error, _} = error, _type), do: error
  defp handle_fetch_response({:ok, messages}, type) do
    case type do
      "json" ->
        messages = messages |>
          Enum.map(&to_kafka_message/1) |>
          Enum.map(fn(x) -> Enum.map(x, &undef_to_nil/1) end) |>
          Enum.map(&Map.new/1)
        {:ok, messages}
      "binary" ->
        payload = messages |> hd |> kafka_message(:value) |> undef_to_empty
        {:ok, payload}
    end
  end

  defp to_kafka_message(x), do: kafka_message(x)

  defp undef_to_nil({k, :undefined}), do: {k, nil}
  defp undef_to_nil({k, v}),          do: {k, v}

  defp undef_to_empty(:undefined), do: ""
  defp undef_to_empty(v),          do: v

  defp respond(conn, {:ok, messages}, "json") do
    send_json(conn, 200, messages)
  end
  defp respond(conn, {:ok, payload}, "binary") do
    conn
    |> put_resp_content_type("application/binary")
    |> send_resp(200, payload)
  end
  defp respond(conn, {:error, reason}, "json") do
    send_json(conn, 503, %{error: reason})
  end
  defp respond(conn, {:error, reason}, "binary") do
    send_resp(conn, 503, "error: #{inspect reason}")
  end

  # "latest" offset in offset request means "high watermark",
  # there is no message at this offset in kafka.
  # We are compensating for this by subtracting 1 from the result of
  # resolving "latest" offset
  defp resolve_offset(pid, t, p, "latest") do
    case :brod_utils.resolve_offset(pid, t, p, :latest) do
      {:ok, latest} -> {:ok, latest - 1}
      {:error, _} = error -> error
    end
  end
  defp resolve_offset(pid, t, p, "earliest") do
    :brod_utils.resolve_offset(pid, t, p, :earliest)
  end
  defp resolve_offset(pid, t, p, offset) do
    case Integer.parse(offset) do
      {num, _} -> resolve_numeric_offset(pid, t, p, num)
      :error -> {:error, "invalid offset"}
    end
  end

  defp resolve_numeric_offset(pid, t, p, offset) when offset < 0 do
    case :brod_utils.resolve_offset(pid, t, p, :latest) do
      {:ok, latest} -> {:ok, latest + offset}
      {:error, _} = error -> error
    end
  end
  defp resolve_numeric_offset(pid, t, p, offset) do
    :brod_utils.resolve_offset(pid, t, p, offset)
  end

end

