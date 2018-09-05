defmodule Kastlex.MetadataCache do
  require Logger

  use GenServer

  # TODO: use zk watchers to reduce IO

  @table __MODULE__
  @server __MODULE__
  @refresh :refresh
  @sync :sync

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
                              leader_topics = Map.get(acc2, p.leader, %{})
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
    case :brod_client.get_metadata(Kastlex.get_brod_client_id(), :all) do
      {:ok, meta} ->
        :ets.insert(@table, {:ts, :erlang.system_time()})
        brokers = meta[:brokers] |> Enum.map(fn(x) ->
                                               %{host: x[:host], port: x[:port], id: x[:node_id]}
                                             end)
        :ets.insert(@table, {:brokers, brokers})
        topics = Enum.map(meta[:topic_metadata],
                          fn(tm) ->
                            partitions = Enum.map(tm[:partition_metadata],
                                                  fn(x) ->
                                                    %{isr: Enum.sort(x[:isr]),
                                                      leader: x[:leader],
                                                      partition: x[:partition],
                                                      replicas: Enum.sort(x[:replicas])}
                                                  end)
                            config = get_topic_config(state.zk, tm[:topic])
                            %{topic: tm[:topic],
                              config: config,
                              partitions: partitions}
                          end)
        :ets.insert(@table, {:topics, topics})
      {:error, reason} ->
        Logger.error "Error fetching metadata: #{inspect reason}"
    end
  end

  defp get_topic_config(zk, topic) do
    config_path = Enum.join([@topics_config_path, topic], "/")
    {:ok, {config_json, _}} = :erlzk.get_data(zk, config_path)
    %{"config" => config} = Poison.decode!(config_json)
    config
  end

end
