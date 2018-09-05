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

  def init(_options) do
    :ets.new(@table, [:set, :protected, :named_table, {:read_concurrency, true}])
    env = Application.get_env(:kastlex, __MODULE__, [])
    refresh_timeout_ms = Keyword.get(env, :refresh_offsets_timeout_ms, @default_refresh_timeout_ms)
    :erlang.send_after(0, Kernel.self(), @refresh)
    client_config = Kastlex.get_brod_client_config(_logconfg = false)
    {:ok, %{refresh_timeout_ms: refresh_timeout_ms,
            client_config: client_config}}
  end

  def handle_info(@refresh, %{client_config: client_config} = state) do
    Kastlex.MetadataCache.partitions_by_leader() |> Enum.each(fn(x) -> refresh_leader_offsets(client_config, x) end)
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

  def refresh_leader_offsets(client_config, {id, topics}) do
    leader = Kastlex.MetadataCache.get_brokers |> Enum.find(fn(x) -> x.id == id end)
    case leader do
      nil ->
        Logger.error("Error refresing offsets for node #{id}: not found in broker metadata")
      _ ->
        refresh_leader_offsets(client_config, leader, topics)
    end
  end

  def refresh_leader_offsets(client_config, leader, topics) do
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
    request = :kpro.make_request(:list_offsets, 0, request_fields)
    endpoints = [{String.to_charlist(leader.host), leader.port}]
    do_fun = fn(connection) ->
      {:ok, response} = :kpro.request_sync(connection, request, 10_000)
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
    end
    try do
      :kpro_brokers.with_connection(endpoints, client_config, do_fun)
    catch
      _, reason ->
        Logger.error("Error refresing offsets for #{leader.host}: #{inspect reason}")
    end
  end
end
