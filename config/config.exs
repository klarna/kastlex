# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :kastlex, Kastlex.Endpoint,
  root: Path.dirname(__DIR__),
  secret_key_base: "2N8sGXA6wijnGpzmiEl3y6H2YCf7RbeBbi7xgE58txpm6AxDWS+A4TYrUY0jYYGV",
  render_errors: [accepts: ~w(json), default_format: ~w(json)],
  pubsub: [name: Phoenix.PubSub,
           adapter: Phoenix.PubSub.PG2]

config :kastlex, Kastlex.MetadataCache,
  refresh_timeout_ms: 30000

config :kastlex, Kastlex.TokenStorage,
  topic: "_kastlex_tokens"

# Configures Elixir's Logger
config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [:request_id, :remote_ip, :module, :function, :line],
  handle_otp_reports: true,
  handle_sasl_reports: true

# Configure phoenix generators
config :phoenix, :generators,
  migration: true,
  binary_id: false

config :phoenix, :json_library, Jason

config :mime, :types, %{
  "*/*" => ["json"],
  "application/json" => ["json"],
  "application/binary" => ["binary"],
}

config :guardian, Guardian,
  allowed_algos: ["ES512"],
  verify_module: Guardian.JWT,
  issuer: "Kastlex",
  ttl: { 30, :days },
  verify_issuer: true,
  secret_key_file: "priv/jwk.pem",
  serializer: Kastlex.GuardianSerializer

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"

