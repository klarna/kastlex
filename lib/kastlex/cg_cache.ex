defmodule Kastlex.CgCache do
  require Logger

  ## dets tables
  @offsets :cg_cache_offsets # dets table for offsets
  @cgs :cg_cache_cgs # dets table for cg status
  @progress :cg_cache_progress # dets table for cg data collection progress

  ## return all (active/inactive consumer groups)
  def get_groups() do
    ## return all active consumer groups
    cg_keys = :dets.select(@cgs, [{{:"$1", :"_"}, [], [:"$1"]}]) |> :gb_sets.from_list
    ## return also inactive consumer groups (when committed offsets are found)
    offset_keys = :dets.select(@offsets, [{{:"$1", :"_"}, [], [:"$1"]}]) |> :gb_sets.from_list
    :gb_sets.union(cg_keys, offset_keys) |> :gb_sets.to_list
  end

  def get_group(group_id) do
    committed_offsets =
      lookup(@offsets, group_id, %{}) |>
      Enum.map(fn({{topic, partition}, details}) ->
                 offset = Keyword.fetch!(details, :offset)
                 [ {:topic, topic},
                   {:partition, partition},
                   {:lagging, get_lagging(topic, partition, offset)}
                 | details] |> to_maps
               end)
    case lookup(@cgs, group_id, false) do
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

  ## Returns all consumer groups with their committed offsets
  def get_consumer_groups_offsets() do
    :dets.select(@offsets, [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn({group_id, topics}) ->
      topics
      |> Enum.map(fn({{topic, partition}, details}) ->
        offset =  Keyword.fetch!(details, :offset)
        %{group_id: group_id, topic: topic, partition: partition, offset: offset}
      end)
    end)
  end

  def committed_offset(key, value) do
    group_id = ets_key = key[:group_id]
    map_key = {key[:topic], key[:partition]}
    group = lookup(@offsets, ets_key, %{})
    group = case value do
              [] -> Map.delete(group, map_key)
              _  -> Map.put(group, map_key, value)
            end
    case group === %{} do
      :true  -> :dets.delete(@offsets, group_id)
      :false -> :dets.insert(@offsets, {group_id, group})
    end
  end

  def new_cg_status(key, []) do
    group_id = key[:group_id]
    :dets.delete(@cgs, group_id)
  end
  def new_cg_status(key, value) do
    group_id = key[:group_id]
    :dets.insert(@cgs, {group_id, value})
  end

  def update_progress(partition, offset) do
    :dets.insert(@progress, {partition, offset})
  end

  def get_progress(partition) do
    case :dets.lookup(@progress, partition) do
      [{_, offset}] -> offset
      _             -> false
    end
  end

  def init(:priv), do: init(:code.priv_dir(:kastlex))
  def init(dir) do
    f_offsets  = :erlang.binary_to_list(:filename.join(dir, "offsets.dets"))
    f_cgs      = :erlang.binary_to_list(:filename.join(dir, "cgs.dets"))
    f_progress = :erlang.binary_to_list(:filename.join(dir, "progress.dets"))
    common_open_args = [{:access, :read_write}]
    {:ok, _} = :dets.open_file(@offsets, [{:file, f_offsets} | common_open_args])
    {:ok, _} = :dets.open_file(@cgs, [{:file, f_cgs} | common_open_args])
    {:ok, _} = :dets.open_file(@progress, [{:file, f_progress} | common_open_args])
    :ok
  end

  def close() do
    _ = :dets.close(@offsets)
    _ = :dets.close(@cgs)
    _ = :dets.close(@progress)
  end

  def maybe_delete_excluded(nil), do: :ok
  def maybe_delete_excluded(exc) do
    Enum.each(get_groups(),
      fn(group_id) ->
        case exc.(group_id) do
          true ->
            :dets.delete(@cgs, group_id)
            :dets.delete(@offsets, group_id)
          false ->
            :ok
        end
      end)
  end

  defp lookup(table, key, default) do
    case :dets.lookup(table, key) do
      [] -> default
      [{_, value}] -> value
    end
  end

  defp to_maps({k, [x | _] = v}) when is_list(x), do: {k, :lists.map(&to_maps/1, v)}
  defp to_maps({k, [x | _] = v}) when is_tuple(x), do: {k, Map.new(v, &to_maps/1)}
  defp to_maps([{_, _} | _] = x), do: Map.new(:lists.map(&to_maps/1, x))
  defp to_maps({k, v}), do: {k, maybe_nil(v)}

  defp maybe_nil(:undefined), do: nil
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
        -1
      -2 ->
        -2
      n when n > offset ->
        n - offset - 1
      _ ->
        0
    end
  end
end

