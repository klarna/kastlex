defmodule Kastlex.Mixfile do
  use Mix.Project

  def project do
    [app: :kastlex,
     description: "Apache Kafka REST Proxy",
     version: "1.7.1",
     elixir: "~> 1.7",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix, :gettext] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     aliases: aliases()]
  end

  defp aliases do
    [c: "compile",
     rpm: &rpm/1,
     version: &version/1,
     hashpw: &hashpw/1,
     verify: &verify/1, # verify jwt
     shell: &shell/1,
    ]
  end

  def application do
    [
      mod: {Kastlex, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  defp deps do
    [
      {:phoenix, "~> 1.4.0"},
      {:phoenix_pubsub, "~> 1.1"},
      {:phoenix_html, "~> 2.10"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:plug_cowboy, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:mock, "~> 0.3.2", only: :test},
      {:briefly, "~> 0.3.0", only: :test},
      {:logger_file_backend, "0.0.10"},
      {:observer_cli, "~> 1.3.4"},
      {:recon, "~> 2.3.6"},
      {:yaml_elixir, "~> 2.1.0"},
      {:brod, "~> 3.7.1"},
      {:distillery, "~> 2.0.10"},
      {:guardian, "~> 0.14.0"},
      {:comeonin, "~> 4.1.1"},
      {:bcrypt_elixir, "~> 1.0"}
    ]
  end

  defp rpm(args) do
    release = case Integer.parse(:erlang.list_to_binary(args)) do
                :error -> 1
                {x, _} -> x
              end
    args = Enum.join(["--define \"_sourcedir $(pwd)\"",
                      "--define \"_builddir $(pwd)\"",
                      "--define \"_rpmdir $(pwd)\"",
                      "--define \"_topdir $(pwd)\"",
                      "--define \"_name #{Mix.Project.config()[:app]}\"",
                      "--define \"_description #{Mix.Project.config()[:description]}\"",
                      "--define \"_version #{Mix.Project.config()[:version]}\"",
                      "--define \"_release_version #{release}\""
                     ], " ")
    Mix.shell.cmd "rpmbuild -v -bb #{args} rpm/kastlex.spec"
  end

  defp version(args) do
    case Integer.parse(:erlang.list_to_binary(args)) do
      :error -> :ok
      {x, _} ->
        Mix.shell.info("#{x}")
    end
    Mix.shell.info("#{Mix.Project.config()[:version]}")
  end

  defp hashpw(args) do
    Mix.Tasks.Loadpaths.run(args)
    Mix.shell.info("#{Comeonin.Bcrypt.hashpwsalt(to_string(args))}")
  end

  defp verify(args) do
    Mix.Tasks.Loadpaths.run(args)
    # first arg is path to KASTLEX_JWK_FILE
    # second arg is JWT to verify
    jwk = JOSE.JWK.from_pem_file(Enum.at(args,0))
    token = Enum.at(args, 1)
    {valid, jwt, _jws} = JOSE.JWT.verify_strict(jwk, ["ES512"], token)
    Mix.shell.info("Token is valid: #{inspect valid}")
    Mix.shell.info("#{Poison.encode_to_iodata!(jwt, pretty: true)}")
  end

  defp shell(args) do
    Mix.Tasks.Loadpaths.run(args)
  end

end
