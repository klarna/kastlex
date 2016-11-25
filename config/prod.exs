use Mix.Config

config :kastlex, Kastlex.Endpoint,
  http: [port: 8092],
  code_reloader: false,
  server: true,
  root: "."

config :kastlex, :serve_endpoints, true

config :logger, level: :info

import_config "prod.secret.exs"
