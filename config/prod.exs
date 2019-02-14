use Mix.Config

config :kastlex, Kastlex.Endpoint,
  http: [port: 8092],
  code_reloader: false,
  server: true,
  root: "."

config :kastlex, :serve_endpoints, true

config :logger,
  backends: [{LoggerFileBackend, :kastlex}, :console]

config :logger, :kastlex,
  path: "/var/log/kastlex/kastlex.log",
  level: :info,
  format: "$time [$level] $message $metadata\n",
  metadata: [:request_id, :remote_ip, :module, :function, :line],
  handle_otp_reports: true,
  handle_sasl_reports: true

config :guardian, Guardian,
  allowed_algos: ["HS512"],
  verify_module: Guardian.JWT,
  issuer: "Kastlex",
  ttl: { 30, :days },
  verify_issuer: true,
  secret_key_file: "/etc/kastlex/jwk.pem",
  serializer: Kastlex.GuardianSerializer
