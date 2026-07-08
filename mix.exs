defmodule CFONB.MixProject do
  use Mix.Project

  @version "0.1.0"
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
    "Parser for CFONB bank files (French banking standard). Starts with the " <>
      "120-character account statement (relevé de compte)."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Inspired by (Ruby)" => "https://github.com/pennylane-hq/cfonb"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "FORMAT.md"]
    ]
  end
end
