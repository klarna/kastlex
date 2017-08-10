defmodule Kastlex.OffsetsCache do
  require Logger

  use GenServer

  @table :offsets
  @server __MODULE__
  @refresh :refresh
  @default_refresh_timeout_ms 10000

  def get_hwm_offset(topic, partition) do
    case :ets.lookup(@table, {topic, partition}) do
      [{_, offset}] -> offset
      [] -> -1
    end
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, [name: @server])
  end

  def init(options) do
    :ets.new(@table, [:set, :protected, :named_table, {:read_concurrency, true}])
    env = Application.get_env(:kastlex, __MODULE__, [])
    refresh_timeout_ms = Keyword.get(env, :refresh_offsets_timeout_ms, @default_refresh_timeout_ms)
    :erlang.send_after(0, Kernel.self(), @refresh)
    {:ok, %{brod_client_id: options.brod_client_id, refresh_timeout_ms: refresh_timeout_ms}}
  end

  def handle_info(@refresh, state) do
    brod = state.brod_client_id
    {:ok, topics} = Kastlex.MetadataCache.get_topics()
    Enum.each(topics,
              fn(t) ->
                Enum.map(t.partitions,
                         fn(p) ->
                           refresh_offsets(brod, t.topic, p.partition)
                         end)
              end)
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

  defp refresh_offsets(brod, topic, partition) do
    case :brod_client.get_leader_connection(brod, topic, partition) do
      {:ok, pid} ->
        res = :brod_utils.resolve_offset(pid, topic, partition, :latest)
        save_offset(topic, partition, res)
      {:error, _} ->
        # don't care about errors
        :ok
    end
  end

  defp save_offset(_topic, _partition, {:error, _}), do: :ok
  defp save_offset(topic, partition, {:ok, offset}) do
    :ets.insert(@table, {{topic, partition}, offset})
  end

end
