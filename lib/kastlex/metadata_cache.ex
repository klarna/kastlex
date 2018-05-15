defmodule Kastlex.MetadataCache do
  require Logger

  use GenServer

  @table __MODULE__
  @server __MODULE__
  @refresh :refresh
  @sync :sync
  @leaders_table :leader_partitions

  def sync() do
    GenServer.call(@server, @sync)
  end

  def get_ts() do
    [{:ts, ts}] = :ets.lookup(@table, :ts)
    ts
  end

  def get_brokers() do
    [{:brokers, brokers}] = :ets.lookup(@table, :brokers)
    brokers
  end

  def get_leader(id) do
    case Enum.find(get_brokers(), nil, fn(x) -> x.node_id == id end) do
      nil -> false
      leader -> leader
    end
  end

  def existing_partition?(t, p) do
    case Enum.find(get_topics(), nil, fn(x) -> x.topic == t end) do
      nil -> false
      topic ->
        Enum.any?(topic[:partitions], fn(y) -> y.partition == p end)
    end
  end

  def get_topics() do
    [{:topics, topics}] = :ets.lookup(@table, :topics)
    topics
  end

  def get_leader_ids() do
    :ets.select(@leaders_table, [{{:"$1", :_}, [], [:"$1"]}])
  end

  def get_leader_partitions(node_id) do
    [{_, partitions}] = :ets.lookup(@leaders_table, node_id)
    partitions
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [], [name: @server])
  end

  def init(_) do
    :ets.new(@table, [:set, :protected, :named_table])
    :ets.insert(@table, {:ts, :erlang.system_time()})
    :ets.insert(@table, {:brokers, []})
    :ets.insert(@table, {:topics, []})
    :ets.new(@leaders_table, [:set, :protected, :named_table])
    do_refresh()
    env = Application.get_env(:kastlex, __MODULE__)
    refresh_timeout_ms = env[:refresh_timeout_ms]
    :erlang.send_after(refresh_timeout_ms, Kernel.self(), @refresh)
    {:ok, %{refresh_timeout_ms: refresh_timeout_ms}}
  end

  def handle_call(@sync, _, state) do
    {:reply, :ok, state}
  end

  def handle_info(@refresh, state) do
    do_refresh()
    :erlang.send_after(state.refresh_timeout_ms, Kernel.self(), @refresh)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error "Unexpected msg: #{msg}"
    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.info "#{inspect Kernel.self} is terminating: #{inspect reason}"
  end

  defp do_refresh() do
    Logger.info "refreshing metadata"
    case :brod_client.get_metadata(Kastlex.get_brod_client_id(), :all) do
      {:ok, meta} ->
        :ets.insert(@table, {:ts, :erlang.system_time()})
        # convert kewords to maps
        brokers = Enum.map(meta[:brokers], &Map.new/1)
        :ets.insert(@table, {:brokers, brokers})
        # init leader_partitions
        leader_partitions = Map.new(Enum.map(brokers, fn(broker) -> {broker.node_id, %{}} end))
        {topics, leader_partitions} = Enum.map_reduce(meta[:topic_metadata],
          leader_partitions,
          &map_topic_meta/2)
        :ets.insert(@table, {:topics, topics})
        :ets.insert(@leaders_table, Map.to_list(leader_partitions))
      {:error, reason} ->
        Logger.error "Error fetching metadata: #{inspect reason}"
    end
  end

  defp map_topic_meta(tm, leader_partitions) do
    topic = tm[:topic]
    map_partition_meta = fn(pm, lps) ->
      leader = pm[:leader]
      partition = pm[:partition]
      p = %{isr: Enum.sort(pm[:isr]),
            leader: leader,
            partition: partition,
            replicas: Enum.sort(pm[:replicas])}
      lps = Kernel.update_in(lps[leader][topic],
                             fn nil -> [partition]
                                x   -> [partition | x]
                             end)
      {p, lps}
    end
    {partitions, leader_partitions} = Enum.map_reduce(tm[:partition_metadata],
                                                      leader_partitions,
                                                      map_partition_meta)
    topic = %{topic: topic,
              partitions: partitions}
    {topic, leader_partitions}
  end

end
