defmodule Kastlex.KafkaUtils do
  require Logger
  require Record

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kafka_message, extract(:kafka_message, from_lib: "kafka_protocol/include/kpro_public.hrl")

  def resolve_offset(pid, t, p, "last") do
    case {resolve_offset(pid, t, p, "earliest"),
          resolve_offset(pid, t, p, "latest")} do
      {{:ok, e}, {:ok, l}} when l > e ->
        {:ok, l - 1};
      {{:ok, e}, {:ok, e}} ->
        {:error, "partition is empty"}
      {{:error, reason}, _} ->
        {:error, reason}
      {_, {:error, reason}} ->
        {:error, reason}
    end
  end
  def resolve_offset(pid, t, p, "earliest") do
    :brod_utils.resolve_offset(pid, t, p, :earliest)
  end
  def resolve_offset(pid, t, p, "latest") do
    :brod_utils.resolve_offset(pid, t, p, :latest)
  end
  def resolve_offset(pid, t, p, offset) do
    case Integer.parse(offset) do
      {num, _} -> resolve_numeric_offset(pid, t, p, num)
      :error -> {:error, "invalid offset"}
    end
  end

  def fetch(type, params) do
    topic = params["topic"]
    {partition, _} = Integer.parse(params["partition"])
    orig_offset = Map.get(params, "offset", "last")
    try do
      pid = get_leader_connection(topic, partition)
      case resolve_offset(pid, topic, partition, orig_offset) do
        {:ok, offset} ->
          {max_wait_time, _} = Integer.parse(Map.get(params, "max_wait_time", "1000"))
          {min_bytes, _} = Integer.parse(Map.get(params, "min_bytes", "1"))
          {max_bytes, _} = Integer.parse(Map.get(params, "max_bytes", "104857600")) # 100 kB
          fetch_opts = %{max_wait_time: max_wait_time,
                         min_bytes: min_bytes,
                         max_bytes: max_bytes}
          :brod.fetch(pid, topic, partition, offset, fetch_opts)
          |> handle_fetch_response(type)
        error ->
          Logger.error "Failed to resolve offset for topic #{topic}-#{partition} #{inspect orig_offset}: #{inspect error}"
          {:error, "Cannot resolve logical offset #{orig_offset}"}
      end
    catch
      :throw, reason ->
        {:error, reason}
    end
  end

  defp get_leader_connection(topic, partition) do
    case :brod_client.get_partitions_count(Kastlex.get_brod_client_id(), topic) do
      {:ok, partitions_cnt} when partition >= 0 and partition < partitions_cnt ->
        case :brod_client.get_leader_connection(Kastlex.get_brod_client_id(), topic, partition) do
          {:ok, pid} -> pid
          {:error, reason} -> throw(reason)
        end
      {:ok, _} -> throw(:unknown_topic_or_partition)
      {:error, reason} -> throw(reason)
    end
  end

  defp handle_fetch_response({:error, _} = error, _type), do: error
  defp handle_fetch_response({:ok, {hw_offset, messages}}, type) do
    resp = case type do
      "json" ->
        %{messages: messages |> Enum.map(&transform_kafka_message/1),
          high_watermark: hw_offset
         }
      "binary" when messages == [] ->
        %{headers: nil,
          payload: "",
          high_watermark: hw_offset
         }
      "binary" ->
        message = messages |> hd |> transform_kafka_message
        %{headers: message.headers |> to_json,
          payload: message.value,
          offset: message.offset,
          ts_type: message.ts_type,
          ts: message.ts,
          high_watermark: hw_offset
         }
    end
    {:ok, resp}
  end

  defp to_json(map) do
    {:ok, json} = Poison.encode(map)
    json
  end

  defp transform_kafka_message(raw_msg) do
    msg = kafka_message(raw_msg)
    %{key: empty_to_nil(msg[:key]),
      value: empty_to_nil(msg[:value]),
      offset: msg[:offset],
      headers: Map.new(msg[:headers]),
      ts_type: undef_to_nil(msg[:ts_type]),
      ts: undef_to_nil(msg[:ts])
     }
  end

  defp undef_to_nil(:undefined), do: nil
  defp undef_to_nil(x),          do: x

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(x),  do: x

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
