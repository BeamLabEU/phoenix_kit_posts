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
# The posts tables still live in CORE's versioned chain (core creates every
# one of them on every install), but their FUTURE shape belongs to this
# module's own chain, `PhoenixKitPosts.Migrations`. The schema is built by
# `PhoenixKit.Migration.ensure_current/2` first — the same call a host app
# makes — then this module's own V1 on top, stamping every test run's
# database `pkpo_schema:1`.

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

    PhoenixKitPosts.Migrations.up_statements()
    |> Enum.each(&Ecto.Adapters.SQL.query!(TestRepo, &1, []))

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

# The builds-alone test needs `PhoenixKit.TestSupport.ModuleChainCheck`, which
# ships in the first core release after 2.64.1; against an older core it is
# excluded.
chain_check_exclude =
  if Code.ensure_loaded?(PhoenixKit.TestSupport.ModuleChainCheck),
    do: [],
    else: [:requires_module_chain_check]

if repo_available do
  ExUnit.start(exclude: chain_check_exclude)
else
  ExUnit.start(exclude: [:integration | chain_check_exclude])
end
