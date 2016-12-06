use Mix.Config

config :kastlex, Kastlex.Endpoint,
  http: [port: 8092],
  code_reloader: false,
  server: true,
  root: "."

config :kastlex, :serve_endpoints, true

config :logger,
  backends: [{LoggerFileBackend, :kastlex}]

config :logger, :kastlex,
  path: "/var/log/kastlex/kastlex.log",
  level: :info,
  format: "$time [$level] $metadata $message\n",
  metadata: [:request_id, :remote_ip],
  handle_otp_reports: true,
  handle_sasl_reports: true

