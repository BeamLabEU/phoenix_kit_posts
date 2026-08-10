defmodule PhoenixKitPosts.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/BeamLabEU/phoenix_kit_posts"

  def project do
    [
      app: :phoenix_kit_posts,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description:
        "Social posts module for PhoenixKit — user posts, threaded comments, tags, boards, likes/dislikes, media, mentions, and scheduling",
      package: package(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:phoenix_kit],
        ignore_warnings: ".dialyzer_ignore.exs",
        # Fail once a filter stops matching, so entries covering a
        # not-yet-released core API don't outlive the release that adds it.
        list_unused_filters: true
      ],

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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"],
      precommit: [
        "compile --force --warnings-as-errors",
        "deps.unlock --check-unused",
        # Scan for retired Hex deps. Run via `cmd` so Hex bootstraps in a fresh
        # process — the hex.* archive tasks aren't resolvable via Mix.Task.run
        # inside an alias.
        "cmd mix hex.audit",
        "quality.ci"
      ]
    ]
  end

  defp deps do
    [
      # PhoenixKit provides the Module behaviour and Settings API.
      {:phoenix_kit, "~> 2.0"},
      # Comments module for post detail page comments section. 0.2.6 is the
      # floor: `Web.Details` does `use PhoenixKitComments.Embed`, which that
      # release first published. The `use` is unguarded, so 0.2.0–0.2.5 fails
      # to compile in the consumer's build.
      {:phoenix_kit_comments, "~> 0.3"},

      # LiveView is needed for the admin pages.
      {:phoenix_live_view, "~> 1.1"},

      # Markdown rendering for the post detail page. Declared directly because
      # phoenix_kit dropped its transitive (now-retired) earmark dep in 1.7.161.
      {:mdex, "~> 0.13"},

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
      # `priv` ships the module's own gettext catalogs (priv/gettext/**/*.po).
      # PhoenixKitPosts.Gettext is a compile-time backend, so the consuming app
      # compiles these catalogs from the tarball — omit `priv` and every non-English
      # translation silently falls back to the msgid. Mirrors phoenix_kit core.
      files: ~w(lib priv .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "PhoenixKitPosts",
      # Tags in this repo are bare version numbers, not v-prefixed — a "v" ref
      # points at a tag that does not exist and 404s every HexDocs source link.
      source_ref: @version
    ]
  end
end
