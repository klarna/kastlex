defmodule Kastlex.OffsetsCache do
  require Logger

  use GenServer
  @table :offsets
  @server __MODULE__
  @refresh :refresh
  @default_refresh_timeout_ms 10000

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kpro_rsp, extract(:kpro_rsp, from_lib: "kafka_protocol/include/kpro.hrl")

  def get_hwm_offset(topic, partition) do
    case :ets.lookup(@table, {topic, partition}) do
      [{_, offset}] -> offset
      [] -> -1
    end
  end

  def get_offsets do
    :ets.tab2list(@table)
    |> Enum.map(fn({{topic, partition}, offset}) ->
      %{topic: topic, partition: partition, offset: offset}
    end)
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, [name: @server])
  end

  def init(options) do
    :ets.new(@table, [:set, :protected, :named_table, {:read_concurrency, true}])
    env = Application.get_env(:kastlex, __MODULE__, [])
    refresh_timeout_ms = Keyword.get(env, :refresh_offsets_timeout_ms, @default_refresh_timeout_ms)
    :erlang.send_after(0, Kernel.self(), @refresh)
    {:ok, %{brod_client_id: options.brod_client_id, refresh_timeout_ms: refresh_timeout_ms}}
  end

  def handle_info(@refresh, state) do
    client_id = state.brod_client_id
    Kastlex.MetadataCache.partitions_by_leader() |> Enum.each(fn(x) -> refresh_leader_offsets(x, client_id) end)
    :erlang.send_after(state.refresh_timeout_ms, Kernel.self(), @refresh)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error "Unexpected msg: #{inspect msg}"
    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.info "#{inspect Kernel.self} is terminating: #{inspect reason}"
  end

  def refresh_leader_offsets({id, topics}, client_id) do
    leader = Kastlex.MetadataCache.get_brokers |> Enum.find(fn(x) -> x.id == id end)
    case leader do
      nil ->
        Logger.error("Error refresing offsets for node #{id}: not found in broker metadata")
      _ ->
        refresh_leader_offsets(leader, topics, client_id)
    end
  end

  def refresh_leader_offsets(leader, topics, client_id) do
    topics = Enum.reduce(topics, [],
                         fn({t, partitions}, acc) ->
                           partition_fields = Enum.reduce(partitions, [],
                                                          fn(p, acc2) ->
                                                            [[partition: p,
                                                              timestamp: -1,
                                                              max_num_offsets: 1] | acc2]
                                                          end)
                           [[topic: t, partitions: partition_fields] | acc]
                         end)
    request_fields = [replica_id: -1, topics: topics]
    request = :kpro.req(:offsets_request, 0, request_fields)
    {:ok, pid} = :brod_client.get_connection(client_id, String.to_charlist(leader.host), leader.port)
    case :brod_sock.request_sync(pid, request, 10000) do
      {:ok, response} ->
        responses = kpro_rsp(response)[:msg][:responses]
        Enum.each(responses,
                  fn(tr) ->
                    Enum.each(tr[:partition_responses],
                              fn(pr) ->
                                try do
                                  [offset] = pr[:offsets]
                                  :ets.insert(@table, {{tr[:topic], pr[:partition]}, offset})
                                  rescue _e ->
                                    :ok
                                end
                              end)
                  end)
      {:error, reason} ->
        Logger.error("Error refresing offsets for #{leader.host}: #{inspect reason}")
    end
  end

end
