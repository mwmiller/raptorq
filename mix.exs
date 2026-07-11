defmodule Raptorq.MixProject do
  use Mix.Project

  def project do
    [
      app: :raptorq,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "RaptorQ forward error correction (RFC 6330) for Elixir.",
      source_url: "https://github.com/mwmiller/raptorq",
      homepage_url: "https://github.com/mwmiller/raptorq",
      package: package(),
      docs: docs(),
      aliases: aliases(),
      usage_rules: usage_rules(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:primacy, "~> 0.1.0"},
      {:ex_doc, "~> 0.38", only: :docs, runtime: false},
      {:makeup, "~> 1.1", only: :docs, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      compile: ["compile --warnings-as-errors", "format", "credo --strict"],
      precommit: ["format --check-formatted", "credo --strict", "compile --warnings-as-errors"]
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [:usage_rules, :elixir]
    ]
  end

  defp package do
    [
      files: ["lib", "priv", "mix.exs", "README.md", "LICENSE.txt", "CHANGELOG.md"],
      maintainers: ["Matt Miller"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/mwmiller/raptorq",
        "RFC 6330" => "https://www.rfc-editor.org/rfc/rfc6330"
      }
    ]
  end

  defp docs do
    [
      main: "Raptorq",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: "https://github.com/mwmiller/raptorq",
      source_ref: "main"
    ]
  end
end
