defmodule Kastlex.API.V1.ConsumerController do

  require Logger

  use Kastlex.Web, :controller

  plug Kastlex.Plug.EnsurePermissions

  def list_groups(conn, _params) do
    groups = Kastlex.CgCache.get_groups()
    json(conn, groups)
  end

  def show_group(conn, %{"group_id" => group_id}) do
    case Kastlex.CgCache.get_group(group_id) do
      false -> send_json(conn, 404, %{error: "unknown group"})
      group -> json(conn, fix_user_data(group) |> fix_offset_metadata)
    end
  end

  ## Fix user_data fields to base64 if not valid utf8 text
  defp fix_user_data(group) do
    fix_fun = fn(meta) ->
      user_data = Map.get(meta, :user_data)
      case is_null(user_data) do
        true ->
          meta
            |> Map.put(:user_data, "")
            |> Map.put(:user_data_encoding, :text)
        false ->
          case String.valid?(user_data) do
            true ->
              Map.put(meta, :user_data_encoding, :text)
            false ->
              meta
                |> Map.put(:user_data, Base.encode64(user_data))
                |> Map.put(:user_data_encoding, :base64)
          end
      end
    end
    case Map.get(group, :status) do
      status when is_map(status) ->
        members =
          Map.get(status, :members)
            |> Enum.map(fn(member) ->
                  member
                    |> Map.update!(:subscription, fix_fun)
                    |> Map.update!(:assignment, fix_fun)
               end)
        status = Map.put(status, :members, members)
        Map.put(group, :status, status)
      _ ->
        group
    end
  end

  defp fix_offset_metadata(group) do
    offsets = Map.get(group, :offsets)
    fix_fun = fn(offset) ->
      meta = Map.get(offset, :metadata)
      case is_null(meta) or String.printable?(meta) do
        true ->
          Map.put(offset, :metadata_encoding, :text)
        false ->
          offset
          |> Map.put(:metadata_encoding, :base64)
          |> Map.put(:metadata, Base.encode64(meta))
      end
    end
    Map.put(group, :offsets, map_nullable_list(offsets, fix_fun))
  end

  defp is_null(nil) do true end
  defp is_null(:undefined) do true end
  defp is_null(_) do false end

  defp map_nullable_list(list, map_fun) do
    case is_null(list) do
      true ->
        list
      false ->
        Enum.map(list, map_fun)
    end
  end
end

