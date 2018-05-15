defmodule Kastlex.CgLib do
  require Logger

  import Record, only: [defrecord: 2, extract: 2]
  defrecord :kpro_rsp, extract(:kpro_rsp, from_lib: "kafka_protocol/include/kpro.hrl")

  @timeout 30_000

  def list_groups() do
    Kastlex.MetadataCache.get_brokers()
    |> Kastlex.Parallel.pmap(fn(b) -> list_groups(b.host, b.port) end, @timeout)
    |> List.flatten()
  end

  def list_groups(host, port) do
    client_id = Kastlex.get_brod_client_id()
    {:ok, conn} = :brod_client.get_connection(client_id, String.to_charlist(host), port)
    request = :brod_kafka_request.list_groups(conn)
    {:ok, rsp} = :kpro.request_sync(conn, request, @timeout)
    Enum.map(rsp[:groups], fn(g) -> g[:group_id] end)
  end

  def describe_group(group_id) do
    client_id = Kastlex.get_brod_client_id()
    {:ok, {{host, port}, _ConnCfg}} = :brod_client.get_group_coordinator(client_id, group_id)
    {:ok, conn} = :brod_client.get_connection(client_id, host, port)
    vsn = :brod_kafka_apis.pick_version(conn, :describe_groups)
    request = :kpro.make_request(:describe_groups, vsn, [group_ids: [group_id]])
    {:ok, kpro_rsp(msg: msg)} = :kpro.request_sync(conn, request, @timeout)
    [group] = msg[:groups]
    request = :brod_kafka_request.offset_fetch(conn, group_id, [])
    {:ok, kpro_rsp(msg: msg)} = :kpro.request_sync(conn, request, @timeout)
    Map.put(group, :committed_offsets, msg[:responses])
  end

  def init_connections() do
    client_id = Kastlex.get_brod_client_id()
    # not doing this in parallel because get_connection is a gen_server:call
    Kastlex.MetadataCache.get_brokers()
    |> Enum.each(
        fn(b) ->
          case :brod_client.get_connection(client_id, b.host, b.port) do
            {:ok, _pid} ->
              :ok
            {:error, error} ->
              Logger.error "Error establishing connection to #{b.host}:#{b.port}: #{inspect error}"
          end
        end)
    :ok
  end

  def to_maps({k, [x | _] = v}) when is_list(x), do: {k, :lists.map(&to_maps/1, v)}
  def to_maps({k, [x | _] = v}) when is_tuple(x), do: {k, Map.new(v, &to_maps/1)}
  def to_maps([{_, _} | _] = x), do: Map.new(:lists.map(&to_maps/1, x))
  def to_maps({k, v}), do: {k, maybe_nil(v)}

  defp maybe_nil(:undefined), do: nil
  defp maybe_nil(value), do: value

end
