defmodule Kastlex.Plug.EnsurePermissions do
  require Logger
  import Plug.Conn
  @behaviour Plug

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    user = Guardian.Plug.current_resource(conn)
    check_permissions(user, conn, opts)
  end

  defp check_permissions(nil, conn, opts) do
    check_permissions(Kastlex.get_anonymous(), conn, opts)
  end
  defp check_permissions(user, conn, opts) do
    action = Phoenix.Controller.action_name(conn)
    case has_permissions?(action, conn.method, user, conn.params) do
      true ->
        conn
      false ->
        handle_perms_error(user, conn, opts)
    end
  end

  defp has_permissions?(:list_topics = action, "GET", user, _), do: user[action] == true
  defp has_permissions?(:show_topic = action, "GET", user, %{"topic" => topic}) do
    has_2nd_level_permissions?(action, user, topic)
  end
  defp has_permissions?(:list_brokers = action, "GET", user, _), do: user[action] == true
  defp has_permissions?(:show_broker = action, "GET", user, %{"broker" => id}) do
    has_2nd_level_permissions?(action, user, id)
  end
  defp has_permissions?(:show_offsets = action, "GET", user, %{"topic" => topic}) do
    has_2nd_level_permissions?(action, user, topic)
  end
  defp has_permissions?(:produce = action, "POST", user, %{"topic" => topic}) do
    has_2nd_level_permissions?(action, user, topic)
  end
  defp has_permissions?(:fetch = action, "GET", user, %{"topic" => topic}) do
    has_2nd_level_permissions?(action, user, topic)
  end
  defp has_permissions?(:list_urps = action, "GET", user, _), do: user[action] == true
  defp has_permissions?(:show_urps = action, "GET", user, %{"topic" => topic}) do
    has_2nd_level_permissions?(action, user, topic)
  end
  defp has_permissions?(:list_groups = action, "GET", user, _), do: user[action] == true
  defp has_permissions?(:show_group = action, "GET", user, %{"group_id" => group_id}) do
    has_2nd_level_permissions?(action, user, group_id)
  end
  defp has_permissions?(:reload = action, "GET", user, _), do: user[action] == true
  defp has_permissions?(:revoke = action, "DELETE", user, _), do: user[action] == true
  defp has_permissions?(_, _, _, _), do: false

  defp has_2nd_level_permissions?(action, user, item) do
    user[action] == "all" or
    (:erlang.is_list(user[action]) and :lists.member(item, user[action]))
  end

  defp handle_perms_error(user, conn, _opts) do
    action = Phoenix.Controller.action_name(conn)
    Logger.error "Unathorized: user=#{inspect user} action=#{action} method=#{conn.method} params=#{inspect conn.params}"
    conn = conn |> assign(:guardian_failure, :forbidden) |> halt
    params = Map.merge(conn.params, %{reason: :forbidden})
    Kastlex.AuthErrorHandler.unauthorized(conn, params)
  end

end
