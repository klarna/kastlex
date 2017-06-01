use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kastlex, Kastlex.Endpoint,
  http: [port: 4001],
  server: false

config :guardian, Guardian,
  secret_key: "yCWR+HlWNjnBzh1UsGducT9Irq8zmAWxMbPUV+e3S70cPXeJRMz62y5xDtB3qCRL"

# Print only warnings and errors during test
#config :logger, level: :warn
config :logger,
  backends: [:console],
  compile_time_purge_level: :debug

config :comeonin, :bcrypt_log_rounds, 4
config :comeonin, :pbkdf2_rounds, 1
