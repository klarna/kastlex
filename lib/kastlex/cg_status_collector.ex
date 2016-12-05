defmodule Kastlex.CgStatusCollector do
  require Logger
  require Record
  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kafka_message,
             extract(:kafka_message, from_lib: "brod/include/brod.hrl")

  @behaviour :brod_topic_subscriber

  @topic "__consumer_offsets"

  def start_link(options) do
    client = options.brod_client_id
    Kastlex.MetadataCache.sync()
    {:ok, topics} = Kastlex.MetadataCache.get_topics()
    case Enum.find(topics, nil, fn(x) -> x.topic == @topic end) do
      nil ->
        Logger.info "#{@topic} topic not found, skip cg_status_collector"
        :ignore
      _ ->
        cache_dir = Application.get_env(:kastlex, :cg_cache_dir, :priv)
        :ok = Kastlex.CgCache.init(cache_dir)
        consumer_config = [{:begin_offset, :earliest},
                           {:max_bytes, 1000},
                           {:prefetch_count, 100}
                          ]
        ## start a topic subscriber which will spawn one consumer process
        ## for each partition, and subscribe to all partition consumers
        :brod_topic_subscriber.start_link(client, @topic, _partitions = :all,
                                          consumer_config, __MODULE__, nil)
    end
  end

  def init(@topic, _) do
    committed_offsets = Kastlex.CgCache.get_progress()
    {:ok, committed_offsets, %{}}
  end

  def handle_message(partition, msg, state) do
    key_bin = kafka_message(msg, :key)
    value_bin = kafka_message(msg, :value)
    offset = kafka_message(msg, :offset)
    {tag, key, value} = :kpro_consumer_group.decode(key_bin, value_bin)
    case tag do
      :offset -> Kastlex.CgCache.committed_offset(key, value)
      :group -> Kastlex.CgCache.new_cg_status(key, value)
    end
    Kastlex.CgCache.update_progress(partition, offset)
    {:ok, :ack, state}
  end

end

