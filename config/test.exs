import Config

config :logger, level: :warning

# Integration tests run against a real PostgreSQL database. Create it with:
#   createdb phoenix_kit_posts_test
config :phoenix_kit_posts, ecto_repos: [PhoenixKitPosts.Test.Repo]

# `PGDATABASE` lets this suite point at a database the test role isn't allowed
# to CREATE (a shared or managed instance) instead of the name CI provisions for
# itself. Same mechanism as core phoenix_kit's config/test.exs and every sibling
# module's — see core's AGENTS.md for the full rationale. Left unset (CI's case)
# this falls back to the previous hardcoded name, so publishing and CI are
# unaffected.
#
# Without it, the harness this file belongs to is unreachable wherever the role
# lacks CREATEDB — and `test_helper.exs` then EXCLUDES every :integration test
# while the run still exits 0. That is not a neutral gap here: the integration
# half is where the slug and atomic-publish regressions live, so the suite would
# report success having exercised neither.
pg_test_db =
  case System.get_env("PGDATABASE") do
    value when is_binary(value) and value != "" -> String.trim(value)
    _ -> "phoenix_kit_posts_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

# `PGPOOL` bounds the connection pool the same way core does — the default
# (`schedulers_online() * 2`) opens dozens of connections on a many-core box,
# which is fine against a private local Postgres but not against a shared
# instance already near its connection ceiling.
pg_test_pool =
  case System.get_env("PGPOOL") do
    value when is_binary(value) and value != "" ->
      case Integer.parse(String.trim(value)) do
        {size, ""} when size > 0 -> size
        _ -> raise "PGPOOL must be a positive integer, got: #{inspect(value)}"
      end

    _ ->
      System.schedulers_online() * 2
  end

config :phoenix_kit_posts, PhoenixKitPosts.Test.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: pg_test_db,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: pg_test_pool

# `PhoenixKit.RepoHelper` resolves this. Without it every context-layer DB call
# in this module raises into its own rescue and hands back a plausible nothing,
# so a test would be asserting the rescue rather than the behaviour.
config :phoenix_kit, repo: PhoenixKitPosts.Test.Repo
