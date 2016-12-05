defmodule Kastlex.CgCache do
  require Logger

  @server __MODULE__

  ## ets tables
  @offsets :cg_cache_offsets # ets table for offsets
  @cgs :cg_cache_cgs # ets table for cg status

  ## message tags
  @offset :offset
  @cg :cg

  def start_link() do
    GenServer.start_link(__MODULE__, [], [name: @server])
  end

  ## return all (active/inactive consumer groups)
  def get_groups() do
    ## return all active consumer groups
    cg_keys = :ets.select(@cgs, [{{:"$1", :"_"}, [], [:"$1"]}]) |> :gb_sets.from_list
    ## return also inactive consumer groups (when committed offsets are found)
    offset_keys = :ets.select(@offsets, [{{:"$1", :"_"}, [], [:"$1"]}]) |> :gb_sets.from_list
    :gb_sets.union(cg_keys, offset_keys) |> :gb_sets.to_list
  end

  def get_group(group_id) do
    committed_offsets =
      ets_lookup(@offsets, group_id, %{}) |>
      Enum.map(fn({{topic, partition}, details}) ->
                 offset = Keyword.fetch!(details, :offset)
                 [ {:topic, topic},
                   {:partition, partition},
                   {:lagging, get_lagging(topic, partition, offset)}
                 | details] |> to_maps
               end)
    case ets_lookup(@cgs, group_id, false) do
      false ->
        %{:group_id => group_id,
          :offsets => committed_offsets,
          :status => :inactive
         }
      value ->
        to_maps([{:status, value}]) |>
        Map.put(:group_id, group_id) |>
        Map.put(:offsets, committed_offsets)
    end
  end

  def committed_offset(key, value) do
    GenServer.cast(@server, {@offset, key, value})
  end

  def new_cg_status(key, value) do
    GenServer.cast(@server, {@cg, key, value})
  end

  def init(_options) do
    :ets.new(@offsets, [:set, :protected, :named_table, {:read_concurrency, true}])
    :ets.new(@cgs, [:set, :protected, :named_table, {:read_concurrency, true}])
    {:ok, %{}}
  end

  def handle_cast({@offset, key, value}, state) do
    group_id = ets_key = key[:group_id]
    map_key = {key[:topic], key[:partition]}
    group = ets_lookup(@offsets, ets_key, %{})
    group = case value do
              [] -> Map.delete(group, map_key)
              _  -> Map.put(group, map_key, value)
            end
    case group === %{} do
      :true  -> :ets.delete(@offsets, group_id)
      :false -> :ets.insert(@offsets, {group_id, group})
    end
    {:noreply, state}
  end

  def handle_cast({@cg, key, []}, state) do
    group_id = key[:group_id]
    :ets.delete(@cgs, group_id)
    {:noreply, state}
  end
  def handle_cast({@cg, key, value}, state) do
    group_id = key[:group_id]
    :ets.insert(@cgs, {group_id, value})
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error "Unexpected msg: #{msg}"
    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.info "#{inspect Kernel.self} is terminating: #{inspect reason}"
  end

  defp ets_lookup(table, key, default) do
    case :ets.lookup(table, key) do
      [] -> default
      [{_, value}] -> value
    end
  end

  defp to_maps({k, [x | _] = v}) when is_list(x), do: {k, :lists.map(&to_maps/1, v)}
  defp to_maps({k, [x | _] = v}) when is_tuple(x), do: {k, Map.new(v, &to_maps/1)}
  defp to_maps([{_, _} | _] = x), do: Map.new(:lists.map(&to_maps/1, x))
  defp to_maps({k, v}), do: {k, maybe_nil(v)}

  defp maybe_nil(:undefined), do: :nil
  defp maybe_nil(value), do: value

  defp get_lagging(topic, partition, offset) do
    offset_hwm =
      try do
        # returns -1 in case not found in offsets cache
        Kastlex.OffsetsCache.get_hwm_offset(topic, partition)
      rescue _ ->
        # when offset cache does not exist or when offsets_cache is restarting
        -2
      end
    case offset_hwm do
      -1 ->
        "no-hw-offset"
      -2 ->
        "no-offset-cache"
      n when n > offset ->
        n - offset - 1
      _ ->
        "0"
    end
  end
end

