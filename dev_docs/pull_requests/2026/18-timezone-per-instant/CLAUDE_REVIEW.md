# PR #18 Review — Read the schedule in the editor's zone, and keep that zone

**Author:** Max Don (mdon), branch `mdon/pr/timezone-per-instant`
**Merged:** 2026-09-06 (`f41bc7a`)
**Reviewed:** 2026-09-06
**Verdict:** APPROVED — merged, with one release-blocking fix applied on main

---

## What the PR does

Four commits replacing the post editor's homegrown timezone maths with core's
per-instant helpers, and recording the zone a schedule was typed in.

**1. The conversion itself, and the bug it fixes.** `web/edit.ex` used to do
`Integer.parse/1` on the editor's profile timezone in both directions. That is
wrong twice over. An IANA id parses as `:error` and fell through to "leave it
alone" — i.e. **`Europe/Tallinn` was read as UTC**, so a post an Estonian admin
scheduled for 09:00 went out at 09:00 UTC, three hours late in summer. And even
where the profile held a legacy numeric offset, a fixed `±N` hours ignores
daylight saving, so a January schedule typed in June (or the reverse) landed an
hour off. The site-wide `time_zone` setting was never consulted at all — an
editor with a blank profile silently got UTC rather than the site's zone.

The new `Web.ScheduleInput` routes both directions through
`PhoenixKit.Utils.Date.parse_datetime_local/2` and `format_datetime_local/2`,
which resolve a wall clock through `TimeZone.from_wall/2` **on the date typed**,
so DST is applied per instant and a legacy offset still works. The zone itself
comes from core's `get_user_timezone/1` rule: profile, else site setting, else
UTC. This is the right shape — one module, both directions, no local arithmetic
left in the repo (`rg Integer.parse lib/` now returns nothing).

**2. A blank profile counts as unset.** Core's `get_user_timezone/1` only
pattern-matches `nil`, so a profile holding `""` would be handed on as a "zone".
`editor_tz/1` treats blank as unset before delegating. Also correct for the
`%{uuid: …}` partial map an assign may carry — core's `user.user_timezone`
would raise `KeyError` on it, `editor_tz/1` does not.

**3. Unparseable input no longer becomes a silent UTC.** `from_input/2` returns
`:error` and the raw string is left in the params for the changeset to reject,
instead of the old code's quiet pass-through.

**4. The zone is stored, and the server decides it.** `Post` gains
`time_zone`, cast, length-bounded at 64 and validated with
`Utils.TimeZone.valid?/1`; `convert_scheduled_at_to_utc/2` **deletes any
`time_zone` the form carried** and sets it only next to a schedule this editor
actually typed. Dropping the client's value is the right instinct — the form has
no such input, so anything arriving under that key is crafted.

Tests are the good kind: the January/July Tallinn pair pins the exact regression
(both dates would have been 10:00 UTC under the old code), and the round-trip
loop crosses seasons × zone kinds.

---

## Findings

### BUG - CRITICAL — the schema mapped a column no released core had *(fixed on main)*

`field(:time_zone, :string)` was merged against a core that does not create the
column. Core's chain topped out at **V183** (`phoenix_kit` 2.15.1, the latest
release at merge time; the local core checkout's `main` was also V183). The PR's
own title says "needs core V184" — the dependency was known, and shipped anyway.

This is not a feature that degrades. Ecto names **every** field of a schema in
**every** `SELECT`, so with the column absent the failure is not confined to
scheduling — it is every read and write of `phoenix_kit_posts`:

```
** (Postgrex.Error) ERROR 42703 (undefined_column) column p0.time_zone does not exist
    query: SELECT p0."uuid", …, p0."time_zone", … FROM "phoenix_kit_posts" AS p0
           WHERE (p0."status" = 'scheduled') AND (p0."scheduled_at" <= $1)
```

Against a database migrated by core 2.15.1 the suite gave **14 failures** —
`create_post/2`, `publish_post/2`, `process_scheduled_posts/0`, the listing
queries. And because this module's context functions rescue their own DB errors
and hand back a plausible nothing, a host would not have seen a crash: the Posts
admin would simply have gone empty and the scheduled sweep would have published
nothing, quietly. The repo's own suite said nothing because no database was
reachable in the merge environment, so all 20 integration tests were excluded
and the run still exited 0.

**Fixed by the floor, not by removing the field.** Core **2.16.0** was published
hours after the merge and carries the column — as **V185**, not V184:

```
ALTER TABLE …phoenix_kit_posts ADD COLUMN IF NOT EXISTS "time_zone" character varying(64)
```

`varchar(64)` matches the changeset's `validate_length(:time_zone, max: 64)`, so
the bound is the column's, not an invented one. Applied on main:

- `mix.exs`: `pk_dep(:phoenix_kit, "~> 2.0")` → `"~> 2.16"`, with the reason in
  a comment — a schema field with no column is a whole-table outage, not a
  missing feature, so this floor is hard.
- `mix.lock`: core 2.15.1 → 2.16.0.
- `test/core_pin_conformance_test.exs`: floor moved with the pin
  (`@must_admit` from 2.16.0, `@must_reject` gains 2.0.0 / 2.13.9 / 2.15.1) and
  the moduledoc records *why* the floor is 2.16 — matching how
  `phoenix_kit_publishing` and `phoenix_kit_bookings` document theirs. The
  two-segment shape the test exists to protect is unchanged: every core above
  the floor is still admitted.
- The two comments citing "core V184" (`schemas/post.ex`, the integration test)
  now say V185.

With core 2.16.0 the full suite runs green: **61 tests, 0 failures**, integration
tier included.

### BUG - HIGH — the pin also admitted cores without the functions being called *(fixed by the same floor)*

Independently of the column, `Post.changeset/2` calls
`Utils.TimeZone.valid?/1` and `ScheduleInput` reaches `TimeZone.from_wall/2`
through `parse_datetime_local/2`. Both arrived in core **2.13.9**. Under the old
`~> 2.0` a host could resolve core 2.0–2.13.8 and get `UndefinedFunctionError`
on the first post save — and, on the parse side, the *present-but-older*
function that reads `Europe/Tallinn` as offset `0`, which is the silent version
of the very bug this PR set out to fix. The 2.16 floor covers both; the
conformance test now records the 2.13.9 boundary as well, so the reason survives
the next time someone asks why the floor is where it is.

### OBSERVATION — `post.time_zone` is write-only today

Nothing in this repo reads the column back. `to_input/2` renders a stored
instant in the **current** editor's zone, not in the zone the schedule was typed
in, and the publishing worker only compares instants. So the field is provenance
for a future reader (and for cross-module use), not something that changes
behaviour here — which is consistent with commit `6d0b012`'s framing that the
zone is the server's to set. Worth knowing before someone "fixes" the editor to
render in the stored zone: doing that would make a Warsaw admin see a Tallinn
admin's post at the Tallinn wall clock, which is a product decision, not a bug.

Practical consequence of the current design: whoever saves last owns the zone.
Editor B in New York opening a Tallinn-scheduled post sees the correct instant
in NY time and, on save, rewrites `time_zone` to `America/New_York`. The instant
is preserved; only the provenance changes.

### OBSERVATION — the unschedule path re-sends the schedule it just cleared

In `edit.ex`, flipping a scheduled post to draft calls `unschedule_post/1`
(which writes `scheduled_at: nil`) and then `update_post(post, post_params)`
with the form's params — which still carry the parsed `scheduled_at`, and now
`time_zone` alongside it. The row keeps a stale schedule under a draft status.
Harmless (the sweep filters on `status == "scheduled"`) and **pre-existing** —
the PR only adds one more field to what tags along — so it is recorded rather
than fixed, to keep this change set to the timezone question.

### NITPICK — the zone is resolved once per call

`editor_tz/1` falls through to `Settings.get_setting("time_zone", …)`, which is
an uncached DB read in core. A save resolves it twice (`from_input/2` and the
`Map.put`), a mount once. Two queries on a form submit is not worth a cache
parameter; noted only so the next person doesn't discover it as a surprise.

---

## What Was Done Well

- **The failure mode was named, not just fixed.** The `ScheduleInput` moduledoc
  states the old behaviour and its consequence ("a post scheduled for 09:00 by a
  Tallinn editor went out at 09:00 UTC"), so the test that pins it can never be
  mistaken for a redundant assertion.
- **Both directions moved together.** Fixing only the write would have left the
  editor rendering a saved schedule an hour off across a DST boundary; the round
  trip is tested as a round trip.
- **The client does not get to state the zone.** `Map.delete(post_params,
  "time_zone")` before any parsing, and `TimeZone.valid?/1` behind it in the
  changeset, is defence at both layers for a field with no form input.
- **The test tiering is honest.** The settings-backed fallback went to the
  integration tier rather than being mocked into the unit tier, and the pure
  conversions stayed `async: true` with no database.

---

## Verification

```
mix format
PGDATABASE=beamlab_test mix test        # 61 tests, 0 failures (20 integration)
mix precommit                            # format + compile --warnings-as-errors + credo --strict + dialyzer
```

Against core 2.15.1 the same suite gives 14 failures, all
`42703 undefined_column` — the check that made the CRITICAL finding concrete
rather than theoretical.
