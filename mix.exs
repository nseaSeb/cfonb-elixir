defmodule CFONB.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/nseaSeb/cfonb-elixir"

  def project do
    [
      app: :cfonb,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "CFONB",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:decimal, "~> 2.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Parser and emitter for CFONB bank files (French banking standard): parses " <>
      "the 120-character account statement (relevé de compte) and generates " <>
      "160-character transfer orders (ordres de virement)."
  end

  defp package do
    [
      licenses: ["MIT"],
      files:
        ~w(lib mix.exs .formatter.exs README.md FORMAT.md FORMAT-VIREMENT.md CHANGELOG.md LICENSE),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "Inspired by (Ruby)" => "https://github.com/pennylane-hq/cfonb"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "FORMAT.md", "FORMAT-VIREMENT.md", "CHANGELOG.md"]
    ]
  end
end
