defmodule Kastlex.MetricsController do
  @moduledoc """
    Entrypoint for Prometheus metrics collector.

    Only topics with consumer groups are reported.
  """
  require Logger
  use Kastlex.Web, :controller

  def fetch(conn, _params) do
    metrics = Enum.join(offsets(), "\n")

    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, metrics)
  end

  defp offsets do
    off = Enum.concat(cg_offsets(), topic_offsets())
    Enum.concat([
      "# TYPE kafka_consumer_group_offset gauge",
      "# TYPE kafka_topic_offset gauge"
    ], off)
  end

  defp cg_offsets do
    Kastlex.CgCache.get_groups()
    |> Enum.flat_map(fn(group_id) ->
      Kastlex.CgCache.get_group(group_id)
      |> Map.get(:offsets)
      |> Enum.map(fn(offset) ->
        cg_offset_to_prometheus(group_id, offset)
      end)
    end)
  end

  defp topic_offsets do
    Kastlex.OffsetsCache.get_offsets()
    |> Enum.map(fn(topic_offset) ->
      topic_offset_to_prometheus(topic_offset)
    end)
  end

  defp cg_offset_to_prometheus(group_id, cg_offset) do
    %{topic: topic, partition: partition, offset: offset} = cg_offset

    ~s(kafka_consumer_group_offset{consumer_group="#{group_id}", topic="#{topic}", partition="#{partition}"} #{offset})
  end

  defp topic_offset_to_prometheus(topic_offset) do
    %{topic: topic, partition: partition, offset: offset} = topic_offset

    ~s(kafka_topic_offset{topic="#{topic}", partition="#{partition}"} #{offset})
  end
end
