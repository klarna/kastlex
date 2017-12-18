defmodule Kastlex.Mixfile do
  use Mix.Project

  def project do
    [app: :kastlex,
     description: "Apache Kafka REST Proxy",
     version: "1.5.3",
     elixir: "~> 1.5",
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
    ]
  end

  def application do
    [mod: {Kastlex, []},
     applications: [:logger, :phoenix, :phoenix_pubsub, :phoenix_html, :cowboy,
                    :gettext, :yamerl, :yaml_elixir, :comeonin, :erlzk, :brod,
                    :kafka_protocol, :supervisor3, :snappyer, :guardian, :ssl,
                    :observer, :logger_file_backend, :runtime_tools, :observer_cli,
                    :recon]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  defp deps do
    [{:phoenix, "~> 1.3"},
     {:phoenix_pubsub, "~> 1.0"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},
     {:mock, "~> 0.2", only: :test},
     {:briefly, "~> 0.3", only: :test},
     {:logger_file_backend, "0.0.9"},
     {:observer_cli, "~> 1.0.8"},
     {:recon, "~> 2.3.2"},
     {:gettext, "~> 0.13"},
     {:phoenix_html, "~> 2.8.0"},
     {:cowboy, "~> 1.1"},
     {:yaml_elixir, "~> 1.3"},
     {:brod, "~> 3.0"},
     {:distillery, "~> 0.10"},
     {:guardian, "~> 0.14.5"},
     {:erlzk, "~> 0.6.3"},
     {:comeonin, "~> 2.6"},
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

end
