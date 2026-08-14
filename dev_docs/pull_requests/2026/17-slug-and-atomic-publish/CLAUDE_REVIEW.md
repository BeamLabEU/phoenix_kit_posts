# PR #17 Review — Stop rewriting chosen slugs, and let one caller win the publish

**Author:** Max Don (mdon)
**Reviewed:** 2026-08-14 (ecosystem sweep)
**Verdict:** APPROVED — merged, with one harness fix that makes the PR's own tests reachable

---

## Three changes, all sound

**1. The slug fix.** `maybe_generate_slug/1` asked `get_change(:slug)`, which is `nil` both
when the caller left the slug alone and when there isn't one — so any save carrying no
slug re-derived it from the title and moved a live URL. The admin form makes this
ordinary rather than exotic: `web/edit.ex:74` repopulates `"slug" => post.slug`, and
`cast/3` drops a value equal to the data, so it arrives looking identical to no slug at
all. `fetch_change/2` separates the two. Applied to `PostTag` and `PostGroup` too, which
carried the same helper against `:name`.

**2. The atomic publish.** The guard read `post.status` — the in-memory copy — so two
callers each holding a struct that still said `"scheduled"` both believed they had made
the transition and both wrote an activity row and broadcast it. **Two callers is the
normal case, not a race to hand-wave:** `process_scheduled_posts/0` runs from this
module's cron worker *and* from core's `ProcessScheduledJobsWorker` catch-up, on separate
schedules in separate queues. Moving the predicate into the `WHERE` of one `update_all`
lets the database settle it.

The details are right:
- the loser gets `{:ok, current}`, not an error — `scheduled_post_handler.ex` turns
  `{:error, _}` into a permanently failed job, and a no-op is not a failure;
- the loser is **reloaded** rather than echoing the caller's struct, which still carries
  the pre-publish status;
- `only_if` defaults wide (the admin Publish button legitimately publishes a draft) and
  the scheduled paths narrow it to `["scheduled"]`, so a post an author moved back to
  draft is not published by a sweep or an Oban retry;
- the sweep counts winners rather than `{:ok, _}`, which would have counted losers too;
- going around `Post.changeset/2` is *also* what stops publishing from regenerating the
  slug, and `updated_at` is set by hand since `update_all` runs no changesets;
- it is built on `Post` rather than raw SQL so `use PhoenixKit.SchemaPrefix` keeps
  targeting the installed schema on a prefixed install.

**3. The test harness.** This repo had `ExUnit.start()` and no repo configured. The PR's
framing of why that mattered is exactly right and worth preserving: every context function
here rescues its own DB errors and returns a plausible nothing, so a repo-less suite
doesn't fail — **it passes while asserting the rescue.**

---

## Findings

### BUG - HIGH — the new harness could not run here, and said nothing about it *(fixed on main)*

`config/test.exs` hardcoded `database: "phoenix_kit_posts_test…"` and read no
`PGDATABASE`. Every sibling harness in this workspace (`phoenix_kit_entities`,
`phoenix_kit_document_creator`, `phoenix_kit_ai`) and core itself read `PGDATABASE`
/`PGPOOL` precisely so a suite can point at a database the test role is not allowed to
CREATE — the shared-instance case core's `AGENTS.md` calls out by name.

The consequence is the failure mode that section warns about, and it landed:

```
mix test  →  36 tests, 0 failures (18 excluded)
             Integration tests excluded — could not reach "phoenix_kit_posts_test".
```

**Exit 0.** The 18 excluded tests are `test/integration/` — which is where the slug
uniqueness and atomic-publish regressions live. So the suite reported success having
exercised neither of this PR's two headline fixes. A harness added to close exactly that
gap reintroduced it one level up.

**Fix:** `config/test.exs` now reads `PGDATABASE`/`PGPOOL`, matching the siblings, with
the fallback unchanged so CI and publishing are unaffected.

```
PGDATABASE=phoenix_kit_test PGPOOL=8 mix test  →  54 tests, 0 failures
```

### Both fixes verified non-vacuously

Reverting each fix makes its own tests fail, so the coverage is real:

| reverted | result |
|---|---|
| the `where: p.status in ^from_statuses` compare-and-swap | `publish_post_test.exs` → **10 tests, 3 failures** |
| `fetch_change(:slug)` back to `get_change(:slug)` | slug tests → **15 tests, 3 failures** |

---

## Notes

- **No core pin change needed.** This PR keeps a local `maybe_generate_slug/1` and calls
  `Slug.ensure_unique/2`, which has existed since core 2.0 — it does *not* adopt core
  2.4.0's new `put_slug/3`. The `~> 2.0` pin stays correct, and
  `core_pin_conformance_test.exs` keeps passing unchanged. (Contrast
  `phoenix_kit_document_creator`, which did adopt `put_slug/3` in this same sweep and
  therefore had to move its floor to `~> 2.4`.)
- Adopting `put_slug/3` here would collapse three near-identical local helpers into core's
  one and is the obvious follow-up, but it is a separate change and would drag the pin
  with it.
- `mix precommit` exits 0 as merged — no gate fixes were required.
