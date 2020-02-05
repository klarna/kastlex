defmodule Kastlex do
  use Application

  require Logger

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # http endpoint
    endpoint = Application.fetch_env!(:kastlex, Kastlex.Endpoint)
    http = endpoint[:http]
    port = system_env("KASTLEX_HTTP_PORT", http[:port])
    Logger.info "HTTP port: #{port}"
    http = Keyword.put(http, :port, port)
    Application.put_env(:kastlex, Kastlex.Endpoint, Keyword.put(endpoint, :http, http))
    maybe_init_https(system_env("KASTLEX_USE_HTTPS", false, &s2b/1))
    maybe_set_secret_key_base(system_env("KASTLEX_SECRET_KEY_BASE"))
    maybe_set_guardian_secret_key(system_env("KASTLEX_JWK_FILE"))

    # authentication/authorization
    permission_file_default_path = Path.join(File.cwd!(), "permissions.yml")
    permissions_file_path = system_env("KASTLEX_PERMISSIONS_FILE_PATH", permission_file_default_path)
    Logger.info "Permissions file path: #{permissions_file_path}"
    Application.put_env(:kastlex, :permissions_file_path, permissions_file_path)
    passwd_file_default_path = Path.join(File.cwd!(), "passwd.yml")
    passwd_file_path = system_env("KASTLEX_PASSWD_FILE_PATH", passwd_file_default_path)
    Logger.info "Passwd file path: #{passwd_file_path}"
    Application.put_env(:kastlex, :passwd_file_path, passwd_file_path)

    # consumer groups
    cg_exclude_regex = system_env("KASTLEX_CG_EXCLUDE_REGEX", nil)
    maybe_log_parameter("Consumer groups exclude regexp", cg_exclude_regex)
    Application.put_env(:kastlex, :cg_exclude_regex, cg_exclude_regex)

    # token storage
    maybe_configure_token_storage(system_env("KASTLEX_ENABLE_TOKEN_STORAGE", false, &s2b/1))
    maybe_set_token_ttl(system_env("KASTLEX_TOKEN_TTL_SECONDS"))

    # kafka connection
    kafka_cluster = system_env("KASTLEX_KAFKA_CLUSTER", [{'localhost', 9092}], &parse_endpoints/1)
    Logger.info "Kafka cluster: #{inspect kafka_cluster}"

    brod_client_config = get_brod_client_config(true)
    :ok = :brod.start_client(kafka_cluster, :kastlex, brod_client_config)

    children = [
      worker(Kastlex.Users, []),
      worker(Kastlex.TokenStorage, []),
      supervisor(Kastlex.Collectors, []),
      supervisor(Kastlex.Endpoint, []),
      supervisor(Phoenix.PubSub.PG2, [Kastlex.PubSub, []]),
    ]

    opts = [strategy: :one_for_one, name: Kastlex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def get_brod_client_id(), do: :kastlex

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Kastlex.Endpoint.config_change(changed, removed)
    :ok
  end

  def get_user(name), do: Kastlex.Users.get_user(name)

  def get_anonymous(), do: Kastlex.Users.get_anonymous()

  def reload() do
    Kastlex.Users.reload()
  end

  def token_storage_enabled?() do
    guardian = Application.fetch_env!(:guardian, Guardian)
    guardian[:hooks] == Kastlex.TokenStorage
  end

  defp maybe_init_https(true) do
    Logger.info "Using HTTPS"
    port = system_env("KASTLEX_HTTPS_PORT", 8093)
    Logger.info "HTTPS port: #{port}"
    keyfile = system_env("KASTLEX_KEYFILE", "/etc/kastlex/ssl/server.key")
    Logger.info "Keyfile: #{keyfile}"
    certfile = system_env("KASTLEX_CERTFILE", "/etc/kastlex/ssl/server.crt")
    Logger.info "certfile: #{certfile}"
    cacertfile = system_env("KASTLEX_CACERTFILE", "/etc/kastlex/ssl/ca-cert.crt")
    Logger.info "cacertfile: #{cacertfile}"
    config = [port: port, keyfile: keyfile, certfile: certfile, cacertfile: cacertfile]
    endpoint = Application.fetch_env!(:kastlex, Kastlex.Endpoint)
    Application.put_env(:kastlex, Kastlex.Endpoint, Keyword.put(endpoint, :https, config))
  end
  defp maybe_init_https(_), do: :ok

  defp maybe_set_secret_key_base(nil), do: :ok
  defp maybe_set_secret_key_base(secret_key_base) do
    Logger.info "Using custom secret key base from file: #{secret_key_base}"
    endpoint = Application.fetch_env!(:kastlex, Kastlex.Endpoint)
    Application.put_env(:kastlex, Kastlex.Endpoint,
                        Keyword.put(endpoint, :secret_key_base, secret_key_base))
  end

  defp maybe_set_guardian_secret_key(nil) do
    init_secret_key(Application.get_env(:guardian, Guardian)[:secret_key_file])
  end
  defp maybe_set_guardian_secret_key(file) do
    init_secret_key(file)
  end

  defp init_secret_key(file) do
    Logger.info "Reading secret key from #{file}"
    jwk = JOSE.JWK.from_pem_file(file)
    guardian = Application.fetch_env!(:guardian, Guardian)
    Application.put_env(:guardian, Guardian,
                        Keyword.put(guardian, :secret_key, jwk))
  end

  defp maybe_configure_token_storage(true) do
    Logger.info "OS env override: enabling token storage"
    guardian = Application.fetch_env!(:guardian, Guardian)
    Application.put_env(:guardian, Guardian,
                        Keyword.put(guardian, :hooks, Kastlex.TokenStorage))
    case System.get_env("KASTLEX_TOKEN_STORAGE_TOPIC") do
      nil -> :ok
      topic ->
        Application.put_env(:kastlex, Kastlex.TokenStorage, [topic: topic])
        Logger.info "Custom token storage topic: #{topic}"
    end
  end
  defp maybe_configure_token_storage(_), do: :ok

  defp maybe_set_token_ttl(nil), do: :ok
  defp maybe_set_token_ttl(ttl) do
    Logger.info "Using custom token ttl: #{ttl} seconds"
    {ttl, _} = Integer.parse(ttl)
    guardian = Application.fetch_env!(:guardian, Guardian)
    Application.put_env(:guardian, Guardian,
                        Keyword.put(guardian, :ttl, {ttl, :seconds}))
  end

  def get_brod_client_config(maybe_log \\ false) do
    log = case maybe_log do
      true -> fn(x) -> Logger.info(x) end
      false -> fn(_) -> :ok end
    end
    ssl_config =
    []
      |> maybe_put(:cacertfile, system_env("KASTLEX_KAFKA_CACERTFILE"))
      |> maybe_put(:certfile, system_env("KASTLEX_KAFKA_CERTFILE"))
      |> maybe_put(:keyfile, system_env("KASTLEX_KAFKA_KEYFILE"))

    ssl = case ssl_config do
            [] -> system_env("KASTLEX_KAFKA_USE_SSL", false, &s2b/1)
            kw -> kw
          end
    producer_config =
    []
      |> maybe_put(:required_acks, system_env("KASTLEX_PRODUCER_REQUIRED_ACKS", nil, &s2i/1))
      |> maybe_put(:ack_timeout, system_env("KASTLEX_PRODUCER_ACK_TIMEOUT", nil, &s2i/1))
      |> maybe_put(:partition_buffer_limit, system_env("KASTLEX_PRODUCER_PARTITION_BUFFER_LIMIT", nil, &s2i/1))
      |> maybe_put(:partition_onwire_limit, system_env("KASTLEX_PRODUCER_PARTITION_ONWIRE_LIMIT", nil, &s2i/1))
      |> maybe_put(:max_batch_size, system_env("KASTLEX_PRODUCER_MAX_BATCH_SIZE", nil, &s2i/1))
      |> maybe_put(:max_retries, system_env("KASTLEX_PRODUCER_MAX_RETRIES", nil, &s2i/1))
      |> maybe_put(:retry_backoff_ms, system_env("KASTLEX_PRODUCER_RETRY_BACKOFF_MS", nil, &s2i/1))
      |> maybe_put(:max_linger_ms, system_env("KASTLEX_PRODUCER_MAX_LINGER_MS", nil, &s2i/1))
      |> maybe_put(:max_linger_count, system_env("KASTLEX_PRODUCER_MAX_LINGER_COUNT", nil, &s2i/1))

    log.("brod producer config: #{inspect producer_config}")
    log.("brod ssl config: #{inspect ssl}")

    sasl = get_brod_sasl_config(system_env("KASTLEX_KAFKA_SASL_FILE"))
    case sasl do
      {mechanism, username, _password} ->
        log.("sasl #{mechanism} username: #{username}")
      _ ->
        log.("not using sasl auth")
    end

    [allow_topic_auto_creation: false,
     auto_start_producers: true,
     default_producer_config: producer_config,
     ssl: ssl,
     sasl: sasl]
  end

  # Example file format (yaml):
  # username: "foo",
  # password: "bar"
  # mechanism: "plain" # or scram_sha_256 or scram_sha_512
  defp get_brod_sasl_config(nil), do: :undefined
  defp get_brod_sasl_config(file) do
    try do
      {:ok, config} = YamlElixir.read_from_file(file)
      {sasl_mechanism(config), config["username"], config["password"]}
    rescue
      e in RuntimeError ->
        Logger.error("Error loading sasl config file: " <> e.message)
        :undefined
    catch
      _code, value ->
        Logger.error("Error loading sasl config file: #{inspect value}")
        :undefined
    end
  end

  defp sasl_mechanism(config) do
    case config["mechanism"] do
      nil             -> :plain
      "plain"         -> :plain
      "scram_sha_256" -> :scram_sha_256
      "scram_sha_512" -> :scram_sha_512
    end
  end

  defp maybe_put(kw, _key, nil),  do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)

  defp system_env(variable) do
    system_env(variable, nil)
  end

  defp system_env(variable, default) do
    system_env(variable, default, fn(x) -> x end)
  end

  defp system_env(variable, default, convert) do
    case System.get_env(variable) do
      nil -> default
      ""  -> default
      value -> convert.(value)
    end
  end

  defp maybe_log_parameter(_desc, nil), do: :ok
  defp maybe_log_parameter(desc, variable) do
    Logger.info "#{desc}: #{variable}"
  end

  defp parse_endpoints(endpoints) do
    endpoints
      |> String.split(",")
      |> Enum.map(&String.split(&1, ":"))
      |> Enum.map(fn([host, port]) -> {:erlang.binary_to_list(host),
                                       :erlang.binary_to_integer(port)} end)
  end

  defp s2b("true"), do: true
  defp s2b("1"),    do: true
  defp s2b(_),      do: false

  defp s2i(s), do: :erlang.binary_to_integer(s)

end
