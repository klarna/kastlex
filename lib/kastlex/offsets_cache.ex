defmodule Kastlex.OffsetsCache do
  require Logger

  use GenServer
  @table :offsets
  @server __MODULE__
  @refresh :refresh
  @default_refresh_timeout_ms 10000

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kpro_req, extract(:kpro_req, from_lib: "kafka_protocol/include/kpro.hrl")
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

  def refresh_leader_offsets(id) do
    GenServer.cast(@server, {@refresh, id})
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, [name: @server])
  end

  def init(_options) do
    :ets.new(@table, [:set, :protected, :named_table, {:read_concurrency, true}])
    env = Application.get_env(:kastlex, __MODULE__, [])
    refresh_timeout_ms = Keyword.get(env, :refresh_offsets_timeout_ms, @default_refresh_timeout_ms)
    :erlang.send_after(0, Kernel.self(), @refresh)
    {:ok, %{client_id: Kastlex.get_brod_client_id(),
            client_config: Kastlex.get_brod_client_config(_logconfg = false),
            refresh_timeout_ms: refresh_timeout_ms,
            cached_leaders: [],
            kafka_requests: %{},
           }}
  end

  def handle_info({@refresh, id}, state) do
    state = refresh_leader_offsets(id, state)
    {:noreply, state}
  end

  def handle_info(@refresh, state) do
    leaders = Kastlex.MetadataCache.get_leader_ids()
    state = case Enum.sort(leaders) == state.cached_leaders do
              true -> state
              false ->
                Logger.info "Kastlex.OffsetsCache is resetting requests and leaders cache. " <>
                  "Leaders = #{inspect leaders}, " <>
                  "cached leaders = #{inspect state.cached_leaders}"
                Enum.each(leaders, fn(id) -> send(Kernel.self(), {@refresh, id}) end)
                %{state | :kafka_requests => %{}, :cached_leaders => Enum.sort(leaders)}
            end
    {:noreply, state}
  end

  def handle_info({:msg, pid, kpro_rsp(api: :list_offsets, ref: ref, msg: msg)}, state) do
    case Map.pop(state.kafka_requests, {pid, ref}) do
      {nil, _} ->
        Logger.info "Kastlex.OffsetsCache skipped response due to changes in metadata"
        {:noreply, state}
      {leader, new_map} ->
        handle_offsets_response(msg)
        :erlang.send_after(state.refresh_timeout_ms, Kernel.self(), {@refresh, leader})
        {:noreply, %{state | :kafka_requests => new_map}}
    end
  end

  def terminate(reason, _state) do
    Logger.info "terminating: #{inspect reason}"
  end

  def refresh_leader_offsets(id, state) do
    lps = Kastlex.MetadataCache.get_leader_partitions(id)
    topics = Enum.reduce(lps, [],
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
    request = :kpro.make_request(:list_offsets, 0, request_fields)
    leader = Kastlex.MetadataCache.get_leader(id)
    endpoints = [{String.to_charlist(leader.host), leader.port}]
    do_fun = fn(connection) ->
      :kpro.request_async(connection, request)
    end
    try do
      :kpro_brokers.with_connection(endpoints, state.client_config, do_fun)
    catch
      _, reason ->
        Logger.error("Error refresing offsets for #{leader.host}: #{inspect reason}")
    end
    kpro_req(ref: ref) = request
    new_map = Map.put(state.kafka_requests, ref, leader.node_id)
    %{state | :kafka_requests => new_map}
  end

  defp handle_offsets_response(msg) do
    responses = msg[:responses]
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
  end

end
