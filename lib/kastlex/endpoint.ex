defmodule Kastlex.Endpoint do
  use Phoenix.Endpoint, otp_app: :kastlex

  socket "/socket", Kastlex.UserSocket

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/", from: :kastlex, gzip: false,
    only: ~w(favicon.ico robots.txt js)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Kastlex.Plug.RequestMeta
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart],
    pass: ["*/*"]

  plug Plug.MethodOverride
  plug Plug.Head

  plug Kastlex.Router
end
