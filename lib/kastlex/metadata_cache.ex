defmodule Kastlex.MetadataCache do
  require Logger

  use GenServer

  # TODO: use zk watchers to reduce IO

  @table __MODULE__
  @server __MODULE__
  @refresh :refresh
  @sync :sync

  @brokers_path "/brokers/ids"
  @topics_path "/brokers/topics"
  @topics_config_path "/config/topics"

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

  def partitions_by_leader() do
    acc = Enum.reduce(get_brokers(), %{}, fn(b, acc) -> Map.put(acc, b.id, %{}) end)
    List.foldl(get_topics(), acc,
               fn(topic, acc) ->
                 List.foldl(topic.partitions, acc,
                            fn(p, acc2) ->
                              leader_topics = acc2[p.leader]
                              leader_partitions = [p.partition | Map.get(leader_topics, topic.topic, [])]
                              leader_topics = Map.put(leader_topics, topic.topic, leader_partitions)
                              Map.put(acc2, p.leader, leader_topics)
                            end)
               end)
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, [name: @server])
  end

  def init(options) do
    :ets.new(@table, [:set, :protected, :named_table])
    :ets.insert(@table, {:ts, :erlang.system_time()})
    :ets.insert(@table, {:brokers, []})
    :ets.insert(@table, {:topics, []})
    env = Application.get_env(:kastlex, __MODULE__)
    refresh_timeout_ms = Keyword.fetch!(env, :refresh_timeout_ms)
    zk_cluster = options.zk_cluster
    zk_session_timeout = Keyword.fetch!(env, :zk_session_timeout)
    zk_chroot = Keyword.fetch!(env, :zk_chroot)
    {:ok, zk} = :erlzk.connect(zk_cluster, zk_session_timeout, [chroot: zk_chroot])
    state = %{refresh_timeout_ms: refresh_timeout_ms,
              zk: zk,
              zk_cluster: zk_cluster,
              zk_session_timeout: zk_session_timeout,
              zk_chroot: zk_chroot}
    do_refresh(state)
    :erlang.send_after(state.refresh_timeout_ms, Kernel.self(), @refresh)
    {:ok, state}
  end

  def handle_call(@sync, _, state) do
    {:reply, :ok, state}
  end

  def handle_info(@refresh, state) do
    do_refresh(state)
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

  defp do_refresh(state) do
    try do
      {:ok, topic_names} = :erlzk.get_children(state.zk, @topics_path)
      {:ok, topics} = get_topics_meta(state.zk, topic_names, [])
      {:ok, broker_ids} = :erlzk.get_children(state.zk, @brokers_path)
      {:ok, brokers} = get_brokers_meta(state.zk, broker_ids, [])
      :ets.insert(@table, {:ts, :erlang.system_time()})
      :ets.insert(@table, {:topics, topics})
      :ets.insert(@table, {:brokers, brokers})
    rescue
      e -> Logger.error "Skipping refresh: #{Exception.message(e)}"
    end
  end

  defp get_topics_meta(_zk, [], topics), do: {:ok, topics}
  defp get_topics_meta(zk, [t_name | tail], acc) do
    {:ok, topic} = get_topic_meta(zk, t_name)
    get_topics_meta(zk, tail, [topic | acc])
  end

  defp get_topic_meta(zk, t_name) do
    topic = :erlang.list_to_binary(t_name)
    data_path = Enum.join([@topics_path, topic], "/")
    config_path = Enum.join([@topics_config_path, topic], "/")
    {:ok, {data_json, _}} = :erlzk.get_data(zk, data_path)
    {:ok, {config_json, _}} = :erlzk.get_data(zk, config_path)
    %{"partitions" => assignments} = Poison.decode!(data_json)
    {:ok, partitions} = get_partitions_meta(zk, topic, Map.to_list(assignments), [])
    %{"config" => config} = Poison.decode!(config_json)
    {:ok, %{topic: topic, config: config,
            partitions: Enum.sort(partitions, &(&1.partition < &2.partition))}}
  end

  defp get_partitions_meta(_zk, _topic, [], acc), do: {:ok, acc}
  defp get_partitions_meta(zk, topic, [a | tail], acc) do
    {:ok, partition} = get_partition_meta(zk, topic, a)
    get_partitions_meta(zk, topic, tail, [partition | acc])
  end

  defp get_partition_meta(zk, topic, {partition, replicas}) do
    path = Enum.join([@topics_path, topic, "partitions", partition, "state"], "/")
    {:ok, {json, _stat}} = :erlzk.get_data(zk, path)
    %{"isr" => isr, "leader" => leader} = Poison.decode!(json)
    {:ok, %{partition: :erlang.binary_to_integer(partition),
            leader: leader,
            replicas: Enum.sort(replicas),
            isr: Enum.sort(isr)}}
  end

  defp get_brokers_meta(_zk, [], brokers), do: {:ok, brokers}
  defp get_brokers_meta(zk, [id | tail], acc) do
    path = Enum.join([@brokers_path, id], "/")
    {:ok, {json, _stat}} = :erlzk.get_data(zk, path)
    %{"endpoints" => endpoints, "host" => host, "port" => port} = Poison.decode!(json)
    id = :erlang.list_to_integer(id)
    broker = %{id: id, endpoints: endpoints, host: host, port: port}
    get_brokers_meta(zk, tail, [broker | acc])
  end

end
