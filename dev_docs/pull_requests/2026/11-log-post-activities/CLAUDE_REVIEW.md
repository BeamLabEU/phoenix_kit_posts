# PR #11 — Log post activities for the activity feed

- **Author:** Alexander Don (`alexdont`)
- **Merge commit:** `929aeeb`
- **Branch:** `feat/log-post-activities`
- **Reviewer:** Claude (Opus 4.8)
- **Scope:** `lib/phoenix_kit_posts.ex` (+71 / −11) — instruments `create_post`,
  `delete_post`, `publish_post`, and `like_post` to record entries in
  PhoenixKit core's activity feed via `PhoenixKit.Activity.log/1`.

## Summary

The PR is well-constructed and idiomatic. The `Activity.log/1` payload matches
core's own convention exactly (verified against `PhoenixKit.Activity.Entry`'s
schema and core callers in `phoenix_kit/lib/phoenix_kit/users/auth.ex`): `module`
and `mode` are real `Entry` fields, `:action` is the only required field and is
always supplied, and `actor_role` lives in `metadata` (which is where the feed's
`show.html.heex` reads it). The deep-link resolution is wired end-to-end —
`resource_type: "post"` maps to `PhoenixKitPosts` in core's
`ResourceLinks.handlers/0`, and this module's `resolve_comment_resources/1`
(`lib/phoenix_kit_posts.ex:1063`) returns `%{uuid => %{title, path}}`, so entries
link to `/admin/posts/#{uuid}`. The code comment referencing
`resolve_comment_resources/1` is accurate.

The logging is correctly defensive: `Code.ensure_loaded?` guards against core's
Activity module being absent, a `rescue` ensures a logging failure never breaks
the underlying post operation, and it runs **after** the DB op keyed off
`{:ok, _}` — so failed operations don't log, and a duplicate like (which errors on
the `(post_uuid, user_uuid)` unique constraint → transaction rollback) does not
double-log.

## Findings

### BUG - MEDIUM — Admin moderation attributed to the post author — FIXED

`post_actor/2` defaults the actor to the post's `user_uuid` (the author) when no
`:actor_uuid` opt is passed. The PR added the `opts`/`:actor_uuid` plumbing to
`delete_post/2` and `publish_post/2` precisely so a caller could record the real
actor — **but no call site passed it**, making the opt effectively dead code. The
only callers are the admin LiveViews:

- `web/posts.ex` — single publish/delete + `bulk_publish`/`bulk_delete`
- `web/details.ex` — single delete

So when an admin/moderator deletes or publishes **another user's** post, the
activity feed recorded the *author* as the actor (with `actor_role: "user"`),
corrupting the moderation audit trail.

**Fix:** each admin LiveView now threads the acting user through a nil-safe
`actor_opts/1` helper (`[actor_uuid: current_user.uuid]`, or `[]` → author
fallback when no current user). The scheduled auto-publish path
(`ScheduledPostHandler` → `publish_post/1`) intentionally keeps the author as
actor with `mode: "auto"`.

### IMPROVEMENT - MEDIUM — Duplicate `post.published` on idempotent re-publish — FIXED

`publish_post/2` unconditionally calls `update_post(status: "public")`, which
returns `{:ok, _}` even when the post was **already** public, so it logged a fresh
`post.published` every time. `ScheduledPostHandler` documents calling
`publish_post` idempotently (e.g. on an Oban retry), and the admin "Publish"
button / bulk-publish can be run on an already-public post — each re-fire spammed
the feed.

**Fix:** the log is now guarded on a genuine transition
(`with … false <- post.status == "public"`), so only draft/scheduled/unlisted →
public is recorded.

### OBSERVATION — Publishing via the edit form is not logged — NOT FIXED (by design)

Setting `status: "public"` through the edit LiveView calls `update_post/2`
directly, which is not instrumented; only the explicit `publish_post/1` action
logs. Deliberately left as-is: instrumenting the generic `update_post` path to
detect status transitions would risk ambiguous/duplicate events and broadens the
PR's intended surface. Recorded as a known coverage gap for the feed.

### NITPICK — `actor_role` is always `"user"` — NOT FIXED

Even after wiring the correct actor, admin-panel delete/publish record
`metadata.actor_role = "user"` (hardcoded in `log_post_activity/4`). The important
part — actor *identity* — is now correct; the role *badge* may under-state an
admin action. Left for the maintainer to decide, since module access does not map
cleanly to a specific role tier and inventing role detection here would overreach.

### OBSERVATION — `post.published` renders with a neutral badge — NOT FIXED (core-side)

Core's `Activity.action_badge_color/1` matches on substrings and has no
`"published"` branch, so `post.published` falls through to `badge-ghost`.
Cosmetic and belongs to core, not this module.

## What Was Done Well

- Payload matches core's `Activity.log/1` convention field-for-field.
- Resilient by construction: load-guard + rescue + post-commit, `{:ok, _}`-gated
  logging. A logging failure can never break a post operation.
- `delete_post` puts the title in `metadata` — thoughtful, since the row is gone
  by the time the feed tries to resolve it from the DB.
- `like_post` correctly omits the title (the post still exists, so the feed
  resolves it live) and does not double-log re-likes.
- Deep-link resolution correctly wired through the existing
  `resolve_comment_resources/1` handler registry.

## Testing

The library is not standalone DB-tested (`test/test_helper.exs` is bare
`ExUnit.start()`; the suite covers module/behaviour metadata only, no Repo). The
instrumented context functions require a parent-app Repo, so no DB-backed test was
added — consistent with the repo's stance. `mix precommit` is the gate.
