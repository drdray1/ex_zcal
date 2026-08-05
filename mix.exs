defmodule ExZcal.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/drdray1/ex_zcal"

  def project do
    [
      app: :ex_zcal,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [threshold: 86, summary: [threshold: 86]],

      # Hex
      description:
        "Elixir client for zcal scheduling — webhook verification and parsing, booking links, and embeds",
      package: package(),

      # Docs
      name: "ExZcal",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # No runtime dependencies: zcal has no REST API, so this library is pure
  # functions over payloads you already have (`:crypto` for the webhook HMAC,
  # `URI` for the links). Jason is test-only, used to decode the captured
  # sample payloads.
  defp deps do
    [
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExZcal",
      extras: ["README.md"],
      groups_for_modules: [
        Webhooks: [
          ExZcal.Webhook
        ],
        Payload: [
          ExZcal.Event,
          ExZcal.Attendee,
          ExZcal.Answer,
          ExZcal.Host,
          ExZcal.Invite,
          ExZcal.Location,
          ExZcal.Team
        ],
        Links: [
          ExZcal.Link
        ]
      ]
    ]
  end
end
