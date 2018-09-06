defmodule Kastlex.API.V2.MessageController do

  require Logger
  require Record

  use Kastlex.Web, :controller

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kafka_message, extract(:kafka_message, from_lib: "kafka_protocol/include/kpro_public.hrl")
  defrecord :kpro_rsp, extract(:kpro_rsp, from_lib: "kafka_protocol/include/kpro.hrl")

  plug Kastlex.Plug.EnsurePermissions

  def produce(conn, params) do
    # forward the call to v1 api
    Kastlex.API.V1.MessageController.produce(conn, params)
  end

  def fetch(%{assigns: %{type: "binary"}} = conn, params) do
    # forward the call to v1 api
    Kastlex.API.V1.MessageController.fetch(conn, params)
  end
  def fetch(%{assigns: %{type: "json"}} = conn, params) do
    case Kastlex.KafkaUtils.fetch("json", params) do
      {:ok, resp} ->
        respond(conn, resp)
      {:error, :unknown_topic_or_partition} ->
        send_json(conn, 404, %{error: :unknown_topic_or_partition})
      {:error, reason} ->
        send_json(conn, 503, %{error: reason})
    end
  end

  defp respond(conn, %{messages: messages, high_watermark: hw_offset}) do
    conn
    |> put_resp_header("x-high-wm-offset", Integer.to_string(hw_offset))
    |> send_json(200, messages)
  end

end

