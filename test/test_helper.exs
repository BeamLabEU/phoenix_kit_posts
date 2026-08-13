# Test helper for PhoenixKitPosts.
#
# Two levels:
#
#   * unit — schemas, changesets, slug generation. Always run, no database.
#   * integration — tagged `:integration` via `PhoenixKitPosts.DataCase`,
#     excluded automatically when PostgreSQL is unavailable.
#
# First-time setup:
#
#   createdb phoenix_kit_posts_test
#
# The posts tables live in CORE's versioned chain, not in this module — so the
# schema is built by `PhoenixKit.Migration.ensure_current/2`, the same call a
# host app makes. There is no module-owned DDL to run after it.

# `test/support` is on elixirc_paths for :test (mix.exs), so the repo and case
# are already compiled here — requiring the files as well would redefine both
# modules and warn on every run.

alias PhoenixKitPosts.Test.Repo, as: TestRepo

db_name = Application.get_env(:phoenix_kit_posts, TestRepo)[:database]

repo_available =
  try do
    {:ok, _} = TestRepo.start_link()

    # Publishing broadcasts. Without a PubSub server the broadcast lands in its
    # own rescue, so a test asserting a subscriber hears anything would fail
    # for a reason unrelated to what it is asking.
    {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: PhoenixKit.PubSub)

    # `start_link/0` connects lazily, so it succeeds against a database that
    # does not exist — the first real query is what fails, and by then every
    # test is running and timing out one settings read at a time. Ask a
    # question first.
    TestRepo.query!("SELECT 1")
    PhoenixKit.Migration.ensure_current(TestRepo, log: false)

    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)

    true
  rescue
    # Deliberately NOT folded into "no database": a core below the migration
    # floor is a version problem the runner has to see, not a reason to skip
    # half the suite and report success.
    e in PhoenixKit.Migrations.BelowFloorError ->
      reraise e, __STACKTRACE__

    e ->
      IO.puts("""

        Integration tests excluded — could not reach "#{db_name}".
        Run: createdb #{db_name}

        (#{Exception.message(e)})
      """)

      false
  end

if repo_available do
  ExUnit.start()
else
  ExUnit.start(exclude: [:integration])
end
