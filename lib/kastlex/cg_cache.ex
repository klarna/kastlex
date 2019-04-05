defmodule Kastlex.CgCache do
  @compile if Mix.env == :test, do: :export_all
  require Logger

  ## ets tables
  @offsets :cg_cache_offsets # ets table for offsets
  @cgs :cg_cache_cgs # ets table for cg status
  @progress :cg_cache_progress # ets table for cg data collection progress

  ## return all (active/inactive consumer groups)
  def get_groups() do
    ## return all active consumer groups
    cg_keys = :ets.select(@cgs, [{{:"$1", :_}, [], [:"$1"]}]) |> :gb_sets.from_list
    ## return also inactive consumer groups (when committed offsets are found)
    offset_keys = :ets.select(@offsets, [{{:"$1", :_}, [], [:"$1"]}]) |> :gb_sets.from_list
    :gb_sets.union(cg_keys, offset_keys) |> :gb_sets.to_list
  end

  def get_group(group_id) do
    committed_offsets =
      lookup(@offsets, group_id, %{}) |>
      Enum.map(fn({{topic, partition}, details}) ->
                 offset = fetch!(details, :offset)
                 [ {:topic, topic},
                   {:partition, partition},
                   {:lagging, get_lagging(topic, partition, offset)}
                 | to_list(details)] |> Kastlex.CgLib.to_maps
               end)
    case lookup(@cgs, group_id, false) do
      false ->
        %{:group_id => group_id,
          :offsets => committed_offsets,
          :status => :inactive
         }
      value ->
        Kastlex.CgLib.to_maps([{:status, value}]) |>
        put(:group_id, group_id) |>
        put(:offsets, committed_offsets)
    end
  end

  ## Returns all consumer groups with their committed offsets
  def get_consumer_groups_offsets() do
    :ets.select(@offsets, [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn({group_id, topics}) ->
      topics
      |> Enum.map(fn({{topic, partition}, details}) ->
        offset =  fetch!(details, :offset)
        %{group_id: group_id, topic: topic, partition: partition, offset: offset}
      end)
    end)
  end

  def committed_offset(key, value) do
    group_id = ets_key = key[:group_id]
    map_key = {key[:topic], key[:partition]}
    group = lookup(@offsets, ets_key, %{})
    group = case value do
              [] -> delete(group, map_key)
              _  -> put(group, map_key, value)
            end
    case group === %{} do
      :true  -> :ets.delete(@offsets, group_id)
      :false -> :ets.insert(@offsets, {group_id, group})
    end
  end

  def new_cg_status(key, []) do
    group_id = key[:group_id]
    :ets.delete(@cgs, group_id)
  end
  def new_cg_status(key, value) do
    group_id = key[:group_id]
    :ets.insert(@cgs, {group_id, value})
  end

  def update_progress(partition, offset) do
    :ets.insert(@progress, {partition, offset})
  end

  def get_progress(partition) do
    case :ets.lookup(@progress, partition) do
      [{_, offset}] -> offset
      _             -> false
    end
  end

  def init() do
    opts = [:named_table, :set, :public, {:write_concurrency, true}, {:read_concurrency, true}]
    :ets.new(@offsets, opts)
    :ets.new(@cgs, opts)
    :ets.new(@progress, opts)
    :ok
  end

  def maybe_delete_excluded(nil), do: :ok
  def maybe_delete_excluded(exc) do
    Enum.each(get_groups(),
      fn(group_id) ->
        case exc.(group_id) do
          true ->
            :ets.delete(@cgs, group_id)
            :ets.delete(@offsets, group_id)
          false ->
            :ok
        end
      end)
  end

  defp lookup(table, key, default) do
    case :ets.lookup(table, key) do
      [] -> default
      [{_, value}] -> value
    end
  end

  defp delete(x, key) when is_map(x), do: Map.delete(x, key)
  defp delete(x, key) when is_list(x), do: Keyword.delete(x, key)

  defp fetch!(x, key) when is_map(x), do: Map.fetch!(x, key)
  defp fetch!(x, key) when is_list(x), do: Keyword.fetch!(x, key)

  defp put(x, key, val) when is_map(x), do: Map.put(x, key, val)
  defp put(x, key, val) when is_list(x), do: Keyword.put(x, key, val)

  defp to_list(l) when is_list(l), do: l
  defp to_list(m) when is_map(m), do: Map.to_list(m)

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
        -1
      -2 ->
        -2
      n when n >= offset ->
        n - offset
      _ ->
        # high-watermark offset is not up-to-date
        0
    end
  end
end

