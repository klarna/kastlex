defmodule Kastlex do
  use Application

  @anon "anonymous"

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    endpoint = Application.fetch_env!(:kastlex, Kastlex.Endpoint)
    http = endpoint[:http]
    http = Keyword.put(http, :port, system_env("KASTLEX_HTTP_PORT", http[:port]))
    Application.put_env(:kastlex, Kastlex.Endpoint, Keyword.put(endpoint, :http, http))

    maybe_init_https(System.get_env("KASTLEX_USE_HTTPS"))
    maybe_set_secret_key_base(System.get_env("KASTLEX_SECRET_KEY_BASE"))
    kafka_endpoints = parse_endpoints(System.get_env("KASTLEX_KAFKA_CLUSTER"), [{'localhost', 9092}])

    permissions_file_path = system_env("KASTLEX_PERMISSIONS_FILE_PATH", "permissions.yml")
    passwd_file_path = system_env("KASTLEX_PASSWD_FILE_PATH", "passwd.yml")
    cg_cache_dir = system_env("KASTLEX_CG_CACHE_DIR", :priv)
    cg_exclude_regex = system_env("KASTLEX_CG_EXCLUDE_REGEX", nil)
    Application.put_env(:kastlex, :permissions_file_path, permissions_file_path)
    Application.put_env(:kastlex, :passwd_file_path, passwd_file_path)
    Application.put_env(:kastlex, :cg_cache_dir, cg_cache_dir)
    Application.put_env(:kastlex, :cg_exclude_regex, cg_exclude_regex)

    brod_client_config = [{:allow_topic_auto_creation, false},
                          {:auto_start_producers, true}]
    :ok = :brod.start_client(kafka_endpoints, :kastlex, brod_client_config)

    children = [
      # Start the endpoint when the application starts
      supervisor(Kastlex.Endpoint, []),
      supervisor(Phoenix.PubSub.PG2, [Kastlex.PubSub, []]),
      worker(Kastlex.Users, []),
      supervisor(Kastlex.Collectors, [])
    ]

    opts = [strategy: :one_for_one, name: Kastlex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Kastlex.Endpoint.config_change(changed, removed)
    :ok
  end

  def get_user(name) do
    Kastlex.Users.get_user(name)
  end

  def get_anonymous(), do: get_user(@anon)

  def reload() do
    Kastlex.Users.reload()
  end

  defp maybe_init_https(nil), do: :ok
  defp maybe_init_https("true") do
    port = system_env("KASTLEX_HTTPS_PORT", 8093)
    keyfile = system_env("KASTLEX_KEYFILE", "/etc/kastlex/ssl/server.key")
    certfile = system_env("KASTLEX_CERTFILE", "/etc/kastlex/ssl/server.crt")
    cacertfile = system_env("KASTLEX_CACERTFILE", "/etc/kastlex/ssl/ca-cert.crt")
    config = [port: port, keyfile: keyfile, certfile: certfile, cacertfile: cacertfile]
    endpoint = Application.fetch_env!(:kastlex, Kastlex.Endpoint)
    Application.put_env(:kastlex, Kastlex.Endpoint, Keyword.put(endpoint, :https, config))
  end
  defp maybe_init_https(_), do: :ok

  defp maybe_set_secret_key_base(nil), do: :ok
  defp maybe_set_secret_key_base(secret_key_base) do
    endpoint = Application.fetch_env!(:kastlex, Kastlex.Endpoint)
    Application.put_env(:kastlex, Kastlex.Endpoint, Keyword.put(endpoint, :secret_key_base, secret_key_base))
  end

  defp system_env(variable, default) do
    case System.get_env(variable) do
      nil -> default
      value -> value
    end
  end

  defp parse_endpoints(nil, default), do: default
  defp parse_endpoints(endpoints, _default) do
    endpoints
      |> String.split(",")
      |> Enum.map(&String.split(&1, ":"))
      |> Enum.map(fn([host, port]) -> {:erlang.binary_to_list(host),
                                       :erlang.binary_to_integer(port)} end)
  end

end
