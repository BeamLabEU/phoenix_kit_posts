defmodule PhoenixKitPosts.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mdon/phoenix_kit_posts"

  def project do
    [
      app: :phoenix_kit_posts,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description:
        "Posts module for PhoenixKit — blog posts, tags, groups, likes, media, and scheduling",
      package: package(),

      # Dialyzer
      dialyzer: [plt_add_apps: [:phoenix_kit]],

      # Docs
      name: "PhoenixKitPosts",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :phoenix_kit]
    ]
  end

  defp deps do
    [
      # PhoenixKit provides the Module behaviour and Settings API.
      # For local development, use: {:phoenix_kit, path: "../phoenix_kit"}
      {:phoenix_kit, path: "../phoenix_kit"},

      # Comments module for post detail page comments section.
      {:phoenix_kit_comments, path: "../phoenix_kit_comments"},

      # LiveView is needed for the admin pages.
      {:phoenix_live_view, "~> 1.0"},

      # Optional: add ex_doc for generating documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
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
      main: "PhoenixKitPosts",
      source_ref: "v#{@version}"
    ]
  end
end
