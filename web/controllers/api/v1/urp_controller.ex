defmodule Kastlex.API.V1.UrpController do

  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions

  def list_urps(conn, _params) do
    topics = Kastlex.MetadataCache.get_topics()
    urp = List.foldl(topics, [],
                     fn (t, acc) ->
                       urp = get_urp(t.partitions)
                       case urp do
                         []    -> acc
                         [_|_] ->
                           [%{topic: t.topic, urp: urp} | acc]
                       end
                     end)
    case urp do
      []    -> send_resp(conn, 204, "")
      [_|_] -> json(conn, urp)
    end
  end

  def show_urps(conn, %{"topic" => name}) do
    topics = Kastlex.MetadataCache.get_topics()
    case Enum.find(topics, nil, fn(x) -> x.topic == name end) do
      nil ->
        send_json(conn, 404, %{error: "unknown topic"})
      topic ->
        urp = get_urp(topic.partitions)
        case urp do
          []    -> send_resp(conn, 204, "")
          [_|_] -> json(conn, %{topic: topic.topic, urp: urp})
        end
    end
  end

  defp get_urp(partitions), do: get_urp(partitions, [])

  defp get_urp([], acc), do: acc
  defp get_urp([p | tail], acc) do
    case p.replicas != p.isr do
      true -> get_urp(tail, [p | acc])
      false -> get_urp(tail, acc)
    end
  end

end
