import Config

config :logger, level: :warning

# Integration tests run against a real PostgreSQL database. Create it with:
#   createdb phoenix_kit_posts_test
config :phoenix_kit_posts, ecto_repos: [PhoenixKitPosts.Test.Repo]

config :phoenix_kit_posts, PhoenixKitPosts.Test.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "phoenix_kit_posts_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# `PhoenixKit.RepoHelper` resolves this. Without it every context-layer DB call
# in this module raises into its own rescue and hands back a plausible nothing,
# so a test would be asserting the rescue rather than the behaviour.
config :phoenix_kit, repo: PhoenixKitPosts.Test.Repo
