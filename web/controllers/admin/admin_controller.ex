defmodule Kastlex.Admin.AdminController do
  use Kastlex.Web, :controller
  plug Kastlex.Plug.EnsurePermissions

  def reload(conn, _params) do
    Kastlex.reload()
    send_resp(conn, 204, "")
  end

  def revoke(conn, %{"username" => user}) do
    :ok = Kastlex.TokenStorage.revoke("user:#{user}")
    send_resp(conn, 204, "")
  end
end
