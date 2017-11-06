defmodule Kastlex.API.V1.TopicController do

  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions

  def list_topics(conn, _params) do
    topics = Kastlex.MetadataCache.get_topics() |> Enum.map(fn(x) -> x.topic end)
    json(conn, topics)
  end

  def show_topic(conn, %{"topic" => name}) do
    topics = Kastlex.MetadataCache.get_topics()
    case Enum.find(topics, nil, fn(x) -> x.topic == name end) do
      nil ->
        send_json(conn, 404, %{error: "Unknown topic"})
      topic ->
        json(conn, topic)
    end
  end
end
