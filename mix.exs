defmodule EvercamMedia.Mixfile do
  use Mix.Project

  def project do
    {result, _exit_code} = System.cmd("git", ["rev-parse", "HEAD"])
    git_sha = String.slice(result, 0, 7)

    [app: :evercam_media,
     version: "1.0.3-#{git_sha}",
     elixir: "~> 1.7",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     compilers: [:phoenix] ++ Mix.compilers,
     aliases: aliases(),
     deps: deps()]
  end

  defp aliases do
    [
      clean: ["clean"],
      swagger: ["phx.swagger.generate priv/static/swagger.json --router EvercamMediaWeb.Router --endpoint EvercamMediaWeb.Endpoint"]
    ]
  end

  def application do
    [mod: {EvercamMedia, []},
     applications: app_list(Mix.env)]
  end

  defp app_list(:dev), do: [:dotenv, :credo | app_list()]
  defp app_list(:test), do: [:dotenv | app_list()]
  defp app_list(_), do: app_list()
  defp app_list, do: [
    :calendar,
    :cf,
    :comeonin,
    :con_cache,
    :connection,
    :cors_plug,
    :cowboy,
    :ecto,
    :geo,
    :httpoison,
    :inets,
    :jsx,
    :mailgun,
    :meck,
    :phoenix,
    :phoenix_ecto,
    :phoenix_html,
    :phoenix_pubsub,
    :porcelain,
    :postgrex,
    :quantum,
    :runtime_tools,
    :timex,
    :tzdata,
    :erlware_commons,
    :uuid,
    :xmerl,
    :html_sanitize_ex,
    :new_relic,
    :gen_stage,
    :elixir_dropbox,
    :ex_aws,
    :configparser_ex,
    :sweet_xml,
    :phoenix_swagger,
    :ex_json_schema,
    :nadia,
    :distillery
  ]

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  defp deps do
    [
      {:calendar, "~> 0.17.4"},
      {:comeonin, "~> 3.0.2"},
      {:con_cache, "~> 0.12.1"},
      {:cors_plug, "~> 1.5"},
      {:cowboy, "~> 1.1.2"},
      {:credo, "~> 0.8.8", only: :dev},
      {:dotenv, "~> 3.0.0", only: [:dev, :test]},
      {:ecto, "~> 2.1.4"},
      {:distillery, "~> 2.0.0-rc.8"},
      {:geo, "~> 1.4"},
      {:httpoison, github: "ijunaid8989/httpoison", override: true},
      {:jsx, "~> 2.8.2", override: true},
      {:mailgun, github: "evercam/mailgun"},
      {:nadia, "~> 0.4.4"},
      {:phoenix, "~> 1.3.3", override: true},
      {:phoenix_ecto, "~> 3.2.3"},
      {:phoenix_html, "~> 2.9.3"},
      {:porcelain, "~> 2.0.3"},
      {:postgrex, "~> 0.13.5"},
      {:quantum, "~> 1.9.2"},
      {:uuid, "~> 1.1.7"},
      {:relx, "~> 3.26.0"},
      {:erlware_commons, "~> 1.2.0"},
      {:cf, "~> 0.3.1", override: true},
      {:exvcr, "~> 0.8.9", only: :test},
      {:meck,  "~> 0.8.4", override: :true},
      {:html_sanitize_ex, "~> 1.2.0"},
      {:new_relic, github: "azharmalik3/newrelic-elixir", override: true},
      {:gen_stage, "~> 0.13.1"},
      {:poison, "~> 3.1.0", override: true},
      {:elixir_dropbox, "~> 0.0.7"},
      {:ex_aws, "~> 1.1.5"},
      {:configparser_ex, "~> 0.2.1"},
      {:sweet_xml, "~> 0.6", optional: true},
      {:phoenix_swagger, "~> 0.7.0"},
      {:ex_json_schema, "~> 0.5"}
    ]
  end
end
