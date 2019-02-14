use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kastlex, Kastlex.Endpoint,
  http: [port: 4001],
  server: false

# Print only warnings and errors during test
#config :logger, level: :warn
config :logger,
  backends: [:console],
  compile_time_purge_level: :debug

config :bcrypt_elixir, :log_rounds, 4
