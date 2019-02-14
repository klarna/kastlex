defmodule Kastlex.TestConsumer do
  require Logger

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kafka_message, extract(:kafka_message, from_lib: "brod/include/brod.hrl")

  def init(_group_id, state) do
    send state.parent, :init
    {:ok, state}
  end

  def handle_message(_topic, _partition, message, state) do
    kafka_message(key: key, value: value, offset: offset) = message
    Logger.debug("Got message #{key}:#{value}@#{offset}")
    send state.parent, {key, value, offset}
    {:ok, :ack, state}
  end

  def start(client_id, topic, group_id) do
    group_config = [offset_commit_policy: :commit_to_kafka_v2,
                    offset_commit_interval_seconds: 1
                   ]
    consumer_config = [begin_offset: :latest]
    :brod.start_link_group_subscriber(client_id, group_id, [topic],
      group_config, consumer_config, __MODULE__, %{:parent => Kernel.self()})
  end
end
