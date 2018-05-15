defmodule Kastlex.LoginController do
  use Kastlex.Web, :controller

  require Logger

  def login(conn, %{"username" => name, "password" => password}) do
    case Kastlex.get_user(name) do
      false ->
        Comeonin.Bcrypt.dummy_checkpw() # security ftw
        Logger.warn "user #{name} not found"
        send_json(conn, 401, %{error: "invalid username or password"})
      user ->
        case Comeonin.Bcrypt.checkpw(password, user[:password_hash]) do
          false ->
            Logger.warn "password check for user #{name} failed"
            send_json(conn, 401, %{error: "invalid username or password"})
          true ->
            {:ok, token, _} = Guardian.encode_and_sign(%{user: name})
            json(conn, %{token: token})
        end
    end
  end

end
