defmodule PhoenixKitPosts.CorePinConformanceTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Guards the `:phoenix_kit` requirement against being re-narrowed to a single
  core MINOR, and against a local path override reaching a commit.

  The trap is the three-segment form: `~> 2.16.x` expands to
  `>= 2.16.x and < 2.17.0`, so no 2.17 or later core satisfies it. The breakage
  lands on CONSUMERS, never here — a host depending on both this module and a
  newer core minor gets an unsolvable dependency set and `mix deps.get` fails
  outright, with no degraded mode. Nothing else in this repo's own test run
  would notice, which is why the check is a test rather than a convention.

  What this does NOT forbid is raising the two-segment FLOOR. `~> 2.16` still
  admits every later 2.x, and the floor has to track the oldest core that has
  every function this module calls — and every COLUMN its schemas map:

    * `Post` maps `time_zone`, added to `phoenix_kit_posts` by core's V185
      (released in 2.16.0). A schema field with no column is not a feature
      that degrades: Ecto names every field in every SELECT, so on an older
      core `42703 undefined_column` comes back from every read and write of
      the table — listing posts, publishing, the scheduled sweep — and this
      module's context rescues turn that into a plausible nothing. A floor
      left at 2.0 buys a host a silently empty Posts admin.
    * `Post.changeset/2` calls `Utils.TimeZone.valid?/1`, and
      `Web.ScheduleInput` reaches `Utils.Date.parse_datetime_local/2` where it
      resolves a wall clock through `TimeZone.from_wall/2`. Both arrived in
      core 2.13.9 — below it the call raises, and the parse that does exist
      reads `Europe/Tallinn` as offset `0` and schedules the post on UTC with
      no error anywhere.

  The column sets the floor here, so it is 2.16 rather than the 2.14 the
  timezone behaviour alone would want. Raise this alongside `mix.exs` whenever
  a newly-adopted core API, BEHAVIOUR, or migration sets a higher one.

  Core 1.7 is deliberately excluded: core 2.0.0 squashed the migration chain to
  a V135 floor and this module is verified only against that baseline.
  """

  # Floor: core 2.16.0 (V185's `phoenix_kit_posts.time_zone`). Everything above
  # it, forever, must stay admitted — that is the two-segment invariant this
  # test exists for. Move both lists together with the pin in mix.exs.
  @must_admit ["2.16.0", "2.16.9", "2.17.0", "2.99.4"]
  @must_reject ["1.7.189", "1.7.236", "1.9.4", "2.0.0", "2.13.9", "2.15.1", "3.0.0"]

  test "the :phoenix_kit requirement admits every core 2.x and nothing else" do
    requirement = core_requirement()

    assert match?({:ok, _parsed}, Version.parse_requirement(requirement)),
           "`:phoenix_kit` requirement #{inspect(requirement)} is not a valid requirement"

    for version <- @must_admit do
      assert Version.match?(version, requirement),
             "`:phoenix_kit` requirement #{inspect(requirement)} rejects core #{version}. " <>
               "A pin that excludes a core minor breaks `mix deps.get` for every host " <>
               "running this module alongside that core. Keep it a two-segment pin at " <>
               "the module's floor, admitting every core above it."
    end

    for version <- @must_reject do
      refute Version.match?(version, requirement),
             "`:phoenix_kit` requirement #{inspect(requirement)} admits core #{version}, " <>
               "which is outside the range this module is verified against."
    end
  end

  # Resolution order matters. `Mix.Project.config()` is exact, but it reports the
  # dep as it resolved THIS run — and `pk_dep/3` rewrites it to a `path:` tuple
  # whenever PHOENIX_KIT_PATH is exported, which is the workspace's sanctioned way
  # to run this suite against unreleased core. Reading the committed literal from
  # mix.exs as a fallback keeps the check meaningful under that override instead
  # of failing the documented workflow — and it still fails when a path dep is
  # COMMITTED, because then there is no literal left to find.
  defp core_requirement do
    resolved_requirement() || committed_requirement() ||
      flunk("""
      No version requirement found for `:phoenix_kit`.

      Neither the resolved dep nor mix.exs carries one, which means a `path:`
      dep has been committed. That ships a broken package and breaks every
      other consumer's build — restore the published requirement.
      """)
  end

  defp resolved_requirement do
    Mix.Project.config()
    |> Keyword.get(:deps, [])
    |> Enum.find_value(fn
      {:phoenix_kit, requirement} when is_binary(requirement) -> requirement
      {:phoenix_kit, requirement, _opts} when is_binary(requirement) -> requirement
      _ -> nil
    end)
  end

  # First match wins, matching how every other tool in the workspace reads this
  # pin. Covers both the bare `{:phoenix_kit, "..."}` and the `pk_dep(:phoenix_kit,
  # "...")` forms, since the captured text is identical in each.
  defp committed_requirement do
    case Regex.run(~r/:phoenix_kit,\s*"([^"]+)"/, File.read!("mix.exs")) do
      [_full, requirement] -> requirement
      _ -> nil
    end
  end
end
