defmodule Kastlex.OffsetsCache do
  require Logger

  use GenServer
  @table :offsets
  @server __MODULE__
  @refresh :refresh
  @default_refresh_timeout_ms 10_000
  @default_list_offsets_timeout_ms 10_000

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

  def start_link() do
    GenServer.start_link(__MODULE__, [], [name: @server])
  end

  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, {:read_concurrency, true}])
    env = Application.get_env(:kastlex, __MODULE__, [])
    refresh_timeout_ms = Keyword.get(env, :refresh_offsets_timeout_ms, @default_refresh_timeout_ms)
    list_offsets_timeout_ms = Keyword.get(env, :list_offsets_timeout_ms, @default_list_offsets_timeout_ms)
    :erlang.send_after(0, Kernel.self(), @refresh)
    {:ok, %{client_id: Kastlex.get_brod_client_id(),
            refresh_timeout_ms: refresh_timeout_ms,
            list_offsets_timeout_ms: list_offsets_timeout_ms,
            cached_leaders: [],
            kafka_requests: %{},
            generation: 1
           }}
  end

  def handle_info({@refresh, id, generation}, %{generation: generation} = state) do
    refresh_leader_offsets(id, generation, state.refresh_timeout_ms)
    {:noreply, state}
  end
  def handle_info({@refresh, _id, _generation}, state) do
    # wrong generation, drop the message
    {:noreply, state}
  end

  def handle_info(@refresh, state) do
    leaders = Kastlex.MetadataCache.get_leader_ids()
    state = case Enum.sort(leaders) == state.cached_leaders do
              true -> state
              false ->
                Logger.info "resetting requests and leaders cache. " <>
                  "Leaders = #{inspect leaders}, " <>
                  "cached leaders = #{inspect state.cached_leaders}"
                # bump generation
                generation = state.generation + 1
                Enum.each(leaders,fn(id) ->
                  refresh_leader_offsets(id, generation, state.refresh_timeout_ms) end)
                %{state | :cached_leaders => Enum.sort(leaders), :generation => generation}
            end
    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.info "terminating: #{inspect reason}"
  end

  def refresh_leader_offsets(id, generation, refresh_timeout_ms) do
    parent = self()
    Kernel.spawn(
      fn ->
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
        client_id = Kastlex.get_brod_client_id()
        leader = Kastlex.MetadataCache.get_leader(id)
        {:ok, conn} = :brod_client.get_connection(client_id, String.to_charlist(leader.host), leader.port)
        vsn = :brod_kafka_apis.pick_version(conn, :list_offsets)
        request_fields = [replica_id: -1, topics: topics]
        request = :kpro.make_request(:list_offsets, vsn, request_fields)
        {:ok, kpro_rsp(msg: msg)} = :kpro.request_sync(conn, request, 10_000)
        handle_offsets_response(msg[:responses])
        :erlang.send_after(refresh_timeout_ms, parent, {@refresh, id, generation})
      end)
  end

  defp handle_offsets_response(responses) do
    Enum.each(responses,
              fn(tr) ->
                Enum.each(tr[:partition_responses],
                          fn(pr) ->
                            t = tr[:topic]
                            p = pr[:partition]
                            [offset] = pr[:offsets]
                            :ets.insert(@table, {{t, p}, offset})
                          end)
              end)
  end

end
