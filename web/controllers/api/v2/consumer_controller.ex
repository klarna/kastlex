defmodule Kastlex.API.V2.ConsumerController do

  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions

  def list_groups(conn, _params) do
    groups = Kastlex.CgCache.get_groups()
    json(conn, groups)
  end

  def show_group(conn, %{"group_id" => group_id}) do
    # TODO: find a way to figure out if the consumer group does not exist
    # and return 404
    case Kastlex.CgLib.describe_group(group_id) do
      {:error, error} -> send_json(conn, 500, %{error: "#{inspect error}"})
      group ->
        group = group |> fix_user_data |> fix_offset_metadata
        json(conn, group)
    end
  end

  ## Fix user_data fields to base64 if not valid utf8 text
  defp fix_user_data(group) do
    fix_fun = fn(assignment) ->
      user_data = Map.get(assignment, :user_data)
      case is_null(user_data) do
        true ->
          assignment
            |> Map.put(:user_data, "")
            |> Map.put(:user_data_encoding, :text)
        false ->
          case String.printable?(user_data) do
            true ->
              Map.put(assignment, :user_data_encoding, :text)
            false ->
              assignment
                |> Map.put(:user_data, Base.encode64(user_data))
                |> Map.put(:user_data_encoding, :base64)
          end
      end
    end
    members =
      Map.get(group, :members)
      |> Enum.map(&(Map.update!(&1, :member_assignment, fix_fun)))
      |> Enum.map(&(Map.update!(&1, :member_metadata, fix_fun)))
    Map.put(group, :members, members)
  end

  defp fix_offset_metadata(group) do
    fix_fun = fn(partition) ->
      meta = Map.get(partition, :metadata)
      case is_null(meta) or String.printable?(meta) do
        true ->
          Map.put(partition, :metadata_encoding, :text)
        false ->
          partition
          |> Map.put(:metadata_encoding, :base64)
          |> Map.put(:metadata, Base.encode64(meta))
      end
    end
    offsets =
      Map.get(group, :committed_offsets)
      |> Enum.map(fn(topic) ->
                    responses =
                      Map.get(topic, :partition_responses)
                      |> Enum.map(fix_fun)
                      |> Enum.map(&(add_lag(&1, topic[:topic])))
                    Map.put(topic, :partition_responses, responses)
                  end)
    Map.put(group, :committed_offsets, offsets)
  end

  defp add_lag(partition, topic) do
    hwm = Kastlex.OffsetsCache.get_hwm_offset(topic, partition[:partition])
    Map.put(partition, :lag, hwm - partition[:offset])
  end

  defp is_null(nil) do true end
  defp is_null(:undefined) do true end
  defp is_null(_) do false end

end

