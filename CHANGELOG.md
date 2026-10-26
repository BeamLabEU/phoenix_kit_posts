# Changelog

## Unreleased

### Added

- **The module now tells core's orphan-file check which of its rows point at a stored file** (`file_references/0`, in `FileReferences`): `phoenix_kit_post_media`, `phoenix_kit_post_groups`, `phoenix_kit_posts`. The SQL moved here verbatim from core's `PhoenixKit.Modules.Storage`; a test compares it with core's own copy. Core reads the callback from the first release after 2.64.1; before that, core's own list stays in force. No migration, no change in what counts as an orphan.

## 0.6.0 - 2026-10-24

### Changed

- **The `phoenix_kit` floor is now `>= 2.38.0 and < 3.0.0`, and it is a hard
  one.** The acting user and the activity log now come from core's
  `PhoenixKitWeb.Actor` and `PhoenixKit.Activity.log/3`, both first shipped in
  2.38.0 and no longer feature-detected, so an older core fails to compile.
  The ceiling stays open through every later 2.x minor. Who is recorded as
  the actor of a publish or delete is unchanged. (#21)
- **Every posts admin page sets the admin header trail**: Posts, Posts /
  Groups, Posts / New post, Posts / *post* / Edit, Posts / Groups / New group or
  *group* / Edit, and Settings / Posts. Page titles are now translated (et,
  ru). (#21)
- Locked dependencies refreshed (`phoenix_kit` 2.64.1).

## 0.5.0 - 2026-09-16

### Changed

- **The 13 `phoenix_kit_post*`/`phoenix_kit_comment_*` tables' future shape
  now belongs to a module-owned migration chain**, `PhoenixKitPosts.Migrations`,
  marker `pkpo_schema:<N>` on `phoenix_kit_posts`, following the canonical
  dual-reader protocol documented by `phoenix_kit_hello_world` and used by
  `phoenix_kit_dashboards`/`phoenix_kit_warehouse` (`migrated_version/1` for
  migration context, `migrated_version_runtime/1` for `mix
  phoenix_kit.update`; `up/1` re-reads the version before changing anything).
  Varchar widths are sourced from each owning schema's `column_widths/0`
  (`Post`, `PostComment`, `PostGroup`, `PostMention`, `PostTag`, `PostView`)
  — the single shape authority — never restated as a second number.

  Ownership unfolds in three phases:

    * **Phase 0 (this release)** — V1 is an **adoption, not a create**: core's
      V135/V167/V168/V185 baseline still creates all 13 tables (and
      `phoenix_kit_posts.time_zone`) on every install, and V1 re-asserts that
      exact shape idempotently — every pkey, index, and the full 24-FK set
      (9 to `phoenix_kit_users`, 1 self-referential on
      `phoenix_kit_post_comments`, 1 to `phoenix_kit_post_groups`, 1 to
      `phoenix_kit_post_tags`, 2 to `phoenix_kit_files`, 8 to
      `phoenix_kit_posts`, 2 to `phoenix_kit_post_comments`) — and stamps the
      marker. Because no shape changes, core's `ExpectedSchema` stays
      accurate — **no core release is required and there is no
      release-ordering hazard**.
    * **Phase 1 (a future V2+)** — the first real shape change requires first
      adding the altered objects to core's manifest generator's
      `@excluded_exact` and regenerating `ExpectedSchema`, then raising this
      package's core floor to that release. Five unique constraints this
      module's schemas already assert via `unique_constraint/3` but core
      never backed with an index (`post_likes`/`post_dislikes`/
      `post_mentions` on `(post_uuid, user_uuid)`, `comment_likes`/
      `comment_dislikes` on `(comment_uuid, user_uuid)`) are a documented gap
      left for that first real version, not fixed here.
    * **Phase 2 (a future core baseline squash)** — once core stops creating
      these tables for fresh installs, V1's `CREATE TABLE` statements become
      the only thing that ever creates them from scratch, which is why
      `up/1` already ensures `uuid_generate_v7()` (and its `pgcrypto`
      extension) exist rather than assuming core's chain provided them.

  **`down/1` can never drop a table, for any target including 0.** It
  unstamps (or re-stamps) the marker on `phoenix_kit_posts` and nothing
  else: the rows are every user's posts, likes, tags, groups, media,
  mentions, views and legacy comments, and on most installs every table is
  core-created. Test-pinned — no statement in either direction may match
  `DROP`/`TRUNCATE`/`DELETE`. There is deliberately no automated uninstall
  path; README.md's new "Removing this module" section gives the operator
  manual SQL instead.

  Existing hosts: upgrade, then `mix phoenix_kit.update`; it generates a
  `posts_update_v00_to_v01.exs` migration that stamps `pkpo_schema:1` and
  nothing else changes. New hosts and hosts without this module: unchanged.

  This is the third of a planned series of similar module-owned-migration
  adoptions across `phoenix_kit_*` packages (after `phoenix_kit_dashboards`
  and `phoenix_kit_warehouse`) that today rely entirely on core's versioned
  chain for their own tables.

### Added

- **`test/integration/migrations_shape_identity_test.exs`** — the chain checked
  against a real database instead of a description of one. Core's whole chain
  builds into one schema, V1 builds from scratch into another holding only stub
  `phoenix_kit_users` / `phoenix_kit_files` tables, and every column, index and
  constraint of the 13 tables is diffed out of Postgres' own catalogue. The
  existing manifest comparison is core describing itself; this is the arbiter
  disagreeing with both if they drift. It is also the only exercise of V1's
  `CREATE TABLE` statements, which are no-ops on every install until core's
  Phase 2 baseline squash makes them the only thing that builds these tables.
- **`test/integration/column_width_test.exs`** — every writable
  `character varying(n)` column pinned to its schema's `column_widths/0`.

### Fixed

- **A subtitle, repost URL or generated slug wider than its column no longer
  500s the editor.** Three `character varying` columns were validated against
  numbers that disagreed with the database, so the changeset reported
  `valid?` and Postgres then raised `22001 string_data_right_truncation` on
  the insert — an unhandled `Postgrex.Error` rather than a form error.
  `Post.changeset/2` now drives every `validate_length/3` from
  `column_widths/0`, the same map the migration chain builds its DDL from:

    * `sub_title` was checked against **500** against a `varchar(255)` column,
      and the editor's own character counter and `maxlength` came from
      `posts_max_subtitle_length`, whose default is 500 — the page actively
      invited the input that broke it. `Web.Edit` now clamps both the title
      and subtitle limits to the real column widths, so a setting above the
      column is absorbed rather than advertised.
    * `repost_url` had no length bound at all, against a `varchar(255)`
      column. A repost URL with a long query string is ordinary.
    * A second post sharing a 255-character title produced a 257-character
      slug: `Slug.ensure_unique/2` appended `-2` to a slug already at the
      column's ceiling. Both `slugify/1` and `unique_slug/2` now pass
      `max_length:`, which trims the base to make room for the suffix — the
      hazard core's own `Slug` documents.
    * `PostGroup` and `PostTag` accepted an explicit slug wider than their
      columns (generated ones are safe — they derive from a `name` capped at
      100).

## 0.4.0 - 2026-09-06

### Fixed

- **A post scheduled by an editor in a named timezone was published in UTC.**
  The editor read and wrote its `datetime-local` field with `Integer.parse/1`
  on the editor's profile timezone. An IANA id (`Europe/Tallinn`) parses as
  `:error` and fell through to "no shift", so a post scheduled for 09:00 went
  out at 09:00 UTC — three hours late in Estonian summer. A legacy numeric
  offset fared better but was still a fixed `±N` hours, so a schedule typed
  across a daylight-saving boundary landed an hour off; and the site-wide
  `time_zone` setting was never consulted, so an editor with a blank profile
  silently got UTC rather than the site's zone.

  Both directions now go through core's `Utils.Date.parse_datetime_local/2` and
  `format_datetime_local/2` in the new `Web.ScheduleInput`, which resolve the
  wall clock through `TimeZone.from_wall/2` **on the date typed** — so DST is
  applied per instant, a legacy offset still works, and the zone follows core's
  rule: the editor's profile, else the site setting, else UTC. A blank profile
  value counts as unset. Input that does not parse is left for the changeset to
  reject instead of becoming a silent UTC instant (#18).

### Added

- **A post records the timezone its schedule was typed in.** `Post.time_zone`
  (an IANA id or a legacy offset, validated with `Utils.TimeZone.valid?/1` and
  bounded at the column's 64 characters) is set by the server next to a schedule
  the editor actually typed; any `time_zone` arriving in the form params is
  dropped first. Nil on rows written before core V185 (#18).

### Changed

- **The `phoenix_kit` floor is now `~> 2.16`, and it is a hard one.** Core's
  V185 adds `phoenix_kit_posts.time_zone`, which `Post` maps. Ecto names every
  field of a schema in every `SELECT`, so on an older core this is not a feature
  that degrades — every read and write of the table comes back
  `42703 undefined_column`, and this module's context rescues turn that into a
  plausible nothing: an empty Posts admin and a scheduled sweep that publishes
  nothing. 2.16 also clears `Utils.TimeZone.valid?/1` and `from_wall/2`
  (core 2.13.9), which the changeset and the schedule input call on every save.
  `test/core_pin_conformance_test.exs` moves with the pin and records why.
- Dependency updates: `phoenix_kit` 2.16.0.

## 0.3.0 - 2026-08-14

### Fixed

- **Publishing or editing a post rewrote a slug the author had chosen, moving a
  live URL.** `maybe_generate_slug/1` asked `get_change(:slug)`, which is `nil`
  both when the caller left the slug alone and when the record hasn't got one —
  so any save carrying no slug of its own re-derived it from the title, and the
  old slug was recorded nowhere. The admin edit form makes this ordinary rather
  than exotic: it repopulates `"slug" => post.slug`, and `cast/3` drops a value
  equal to the data, so it arrives looking identical to no slug at all.
  `fetch_change/2` separates the two. `PostTag` and `PostGroup` carried the same
  helper against `:name` and are fixed with it (#17).

- **Two callers could both publish the same scheduled post, and both log it.**
  The guard read `post.status` — the copy in the caller's hand — so two callers
  each holding a struct that still said `"scheduled"` both believed they had made
  the transition, writing two activity rows and two broadcasts. **Two callers is
  the normal case:** `process_scheduled_posts/0` runs from this module's cron
  worker *and* from core's `ProcessScheduledJobsWorker` catch-up, on separate
  schedules in separate queues — no cluster or unlucky timing required.

  The predicate now lives in the `WHERE` of a single `update_all`, so the
  database settles it. The loser is reloaded and returned `{:ok, current}` rather
  than an error, because `scheduled_post_handler.ex` turns `{:error, _}` into a
  permanently failed job and a no-op is not a failure.

- **The test harness could not reach a database on a role without `CREATEDB`,
  and reported success anyway.** `config/test.exs` hardcoded the database name
  and read no `PGDATABASE`, unlike every sibling module and core. Where the
  database was unreachable, `test_helper.exs` excluded all 18 `:integration`
  tests — which is where the slug and atomic-publish regressions live — and the
  run still exited 0. `PGDATABASE`/`PGPOOL` are now honoured, with the previous
  name as the fallback so CI is unaffected.

### Added

- **A database test harness.** `test_helper.exs` was `ExUnit.start()` and
  `config/test.exs` configured no repo, so nothing in the context layer could be
  exercised. That was not a neutral gap: every context function here rescues its
  own DB errors and returns a plausible nothing, so a repo-less suite did not
  fail — it passed while asserting the rescue. Posts tables come from core's
  versioned chain, so the schema is built by `PhoenixKit.Migration.ensure_current/2`,
  the same call a host makes.

### Changed

- **`publish_post/2` takes `:only_if`** — the statuses it may publish *from*. It
  defaults wide, because the admin Publish button legitimately publishes a draft;
  the scheduled sweep and the Oban handler pass `["scheduled"]` so a post the
  author has since moved back to draft is not published by a retry.
- Dependency updates: `phoenix_kit` 2.4.0. The `~> 2.0` pin is unchanged — this
  release keeps its local slug helper and calls `Slug.ensure_unique/2`, which has
  existed since core 2.0, rather than adopting core 2.4.0's new `put_slug/3`.

## 0.2.2 - 2026-08-11

### Changed

- Dependency updates: `phoenix_kit` 2.2.0 and the transitive set it pulls
  (`phoenix` 1.8.10, `hackney` 4.7.3). No source changes in this package.

## 0.2.1 - 2026-08-10

### Changed

- **⚠️ Requires `phoenix_kit ~> 2.0`.** The core pin moved to `~> 2.0`, so this
  release no longer resolves against core 1.7.

  Core 2.0.0 squashes the migration chain into a single `V135` baseline and makes
  V135 the chain's floor: `mix ecto.migrate` now *refuses* on a database below it
  rather than migrating. Check `mix phoenix_kit.status` **before** upgrading. A
  host below V135 must install `phoenix_kit 1.7.236` — the migration bridge, the
  last release carrying the full pre-squash chain — migrate until the reported
  version is at least V135, and only then move to 2.0.

  This package does not call migration internals, so the change is the pin
  itself.

### Documentation

- **Corrects a wrong comment introduced in 0.2.0.** That release rewrote PR #15's
  slug comments to claim core's `Slug.slugify/2` has no `:locale` option. True of
  core **1.7**; core **2.0.0** rewrote `PhoenixKit.Utils.Slug` to delegate to the
  `locale_slug` package, where `:locale` is fully supported —
  `Slug.slugify("Größe Fußball", locale: "de")` is `"groesse-fussball"` while
  `locale: "et"` gives `"grosse-fussball"`. PR #15's original comment was right.

  **No behaviour changes.** These three schemas slug a single-language name with
  no language in scope, so they pass no locale and never did; slugs are
  byte-identical. Only the comment was wrong. It now also notes that
  `:transliterate` is accepted-and-ignored under core 2.0 (romanization is
  always on), so it is redundant rather than load-bearing.

## 0.2.0 - 2026-08-10

### Changed

- **⚠️ Requires `phoenix_kit ~> 2.0`.** The core pin moved to `~> 2.0`, so this
  release no longer resolves against core 1.7.

  Core 2.0.0 squashes the migration chain into a single `V135` baseline and makes
  V135 the chain's floor: `mix ecto.migrate` now *refuses* on a database below it
  rather than migrating. Check `mix phoenix_kit.status` **before** upgrading. A
  host below V135 must install `phoenix_kit 1.7.236` — the migration bridge, the
  last release carrying the full pre-squash chain — migrate until the reported
  version is at least V135, and only then move to 2.0.

  This package does not call migration internals, so the change is the pin
  itself.

- `phoenix_kit_comments` raised to `~> 0.3` in step: its 0.3.0 is the first
  release requiring core 2.0, and is a **security release** (stored XSS in
  comment bodies). See its CHANGELOG.

### Fixed

- **Non-ASCII titles produced an empty slug (PR #15).** Five hand-rolled slug
  pipelines (`Post`, `PostGroup`, `PostTag`, and the auto-slug paths in
  `Web.Edit` / `Web.GroupEdit`) stripped every non-ASCII character, so a
  Cyrillic or Greek title slugged to `""` and German "Größe" lost its umlaut and
  its ß. All five now call core's `Slug.slugify/2` with `transliterate: true`,
  which romanizes instead. The empty slug was not merely cosmetic: the edit form
  read it back as "no slug yet" and regenerated on every subsequent save.

## 0.1.10 - 2026-07-27

### Added
- Open the post content editor in the site-wide default editor mode (PR #14).
  The editor now honours PhoenixKit core's `editor_default_mode` setting
  (admin-editable under Settings → Content Editor) instead of always opening in
  Leaf's built-in default; users can still switch modes inside the editor.

### Fixed
- Don't call `PhoenixKit.Settings.get_editor_mode/0` unconditionally. That function
  exists only in unreleased core builds, while this package's pin (`~> 1.7.189`)
  admits older ones — as merged, PR #14 emitted an `undefined or private` compile
  warning (failing `mix precommit`) and crashed the post editor's `mount/3` with an
  `UndefinedFunctionError` on every released phoenix_kit. The setting is now read
  through a `function_exported?` probe that falls back to `:hybrid`, matching how
  `phoenix_kit_comments` reads the same setting.
- Normalise the editor mode before handing it to Leaf. Leaf's internal
  `normalize_mode/2` has no catch-all clause, so an unexpected value (a raw string
  from the settings row, `nil`, a mode added later) raised a `FunctionClauseError`
  inside the component; unknown values now fall back to `:hybrid`.
- Read the editor-mode setting in `handle_params/3` (via `load_form_data/1`, where
  every other posts setting is loaded) rather than in `mount/3`, which runs twice
  per page load.
- Drop the orphaned `beamlab_ex_aws_sqs` entry from `mix.lock`. phoenix_kit 1.7.213
  depends on that package under the `:ex_aws_sqs` key, leaving the old entry unused
  and `mix deps.unlock --check-unused` (and therefore `mix precommit`) failing.

## 0.1.9 - 2026-07-10

### Added
- Modernize the admin **Posts Settings** page (PR #12): a single `admin_page_header`
  plus in-card `settings_section_header` groupings (Content Limits, Configuration,
  Features, Moderation) replacing the previous per-card `<h2>` layout, with responsive
  two-column grids and consistent toggle/label styling.
- Give the module its own Gettext backend (`PhoenixKitPosts.Gettext`) and wire the
  Settings LiveView to it, so posts strings resolve against this package's own
  `priv/gettext` catalogs. Ships full **Estonian** and **Russian** translations for
  every settings label, hint, option, and flash message (English falls back to the
  source msgids).

### Fixed
- Include `priv/` in the Hex package `files`. `PhoenixKitPosts.Gettext` is a
  compile-time backend, so the consuming app compiles its catalogs from the tarball;
  without `priv/` the newly added `priv/gettext/**/*.po` files were excluded and every
  non-English translation silently fell back to the English msgid in the published
  package.

## 0.1.8 - 2026-07-08

### Added
- Log post activities to PhoenixKit core's activity feed (PR #11). Creating,
  publishing, deleting, and liking a post now records a `post.*` entry via
  `PhoenixKit.Activity.log/1`, carrying `resource_type: "post"` + the post uuid so
  the feed deep-links each entry back to `/admin/posts/{uuid}` through the existing
  `resolve_comment_resources/1` handler. Logging is guarded (`Code.ensure_loaded?`)
  and rescued, so it never breaks the underlying post operation when core's
  Activity module is absent.

### Fixed
- Attribute admin-initiated publish/delete to the acting admin, not the post's
  author. The activity actor is now threaded from the admin LiveViews
  (`Posts` single + bulk actions, `Details` delete) via `:actor_uuid`; previously
  the `post_actor/2` fallback recorded the *author* for every moderation action,
  corrupting the feed's audit trail.
- Stop logging a duplicate `post.published` on idempotent re-publish. `publish_post`
  is re-invoked by the scheduled handler (e.g. on an Oban retry) and by the admin
  Publish / bulk-publish buttons on already-public posts; the event is now recorded
  only on a genuine transition to public.

## 0.1.7 - 2026-06-18

### Security
- Sanitize the rendered post-detail markdown HTML via `PhoenixKit.Utils.HtmlSanitizer` to strip stored-XSS vectors from user-authored post content. The previous Earmark path emitted raw HTML (`escape: false`) unsanitized.

### Changed
- Render post-detail markdown with [MDEx](https://hex.pm/packages/mdex) instead of the now-retired Earmark. phoenix_kit 1.7.161 dropped its transitive `earmark` dependency, so the module now declares `mdex` directly. Rendering is preserved (GFM, smart typography, `language-` code classes).
- Upgrade dependencies: phoenix_kit 1.7.161, phoenix_kit_comments 0.2.11.

### Fixed
- The Posts toolbar's "+ New Post" link now uses live navigation (`navigate`) instead of a full-page `href`, matching every other new/edit/view link in the module.
- Corrected the `PhoenixKitPosts.Web.Settings` moduledoc route — the settings page mounts at `{prefix}/admin/settings/posts` (registered under `settings_tabs`), not `{prefix}/admin/posts/settings`.

## 0.1.6 - 2026-06-17

### Changed
- Moved each admin page's title/subtitle into the top navbar (via the `@page_subtitle` assign forwarded by core's admin layout) and removed the in-page `admin_page_header` on the Posts, Post Groups, and Settings pages; their action buttons now sit in a slim toolbar. Matches the new PhoenixKit admin header pattern. The post detail/edit pages keep their own headers.

## 0.1.5 - 2026-06-08

### Changed
- Post editor now uses the shared `PhoenixKitWeb.Components.MediaGallery` for post images instead of a hand-rolled grid — the picker, drag-reorder, featured badge and lightbox all come from one canonical component (PR #9). The post-content Leaf editor also defaults to hybrid mode (was pinned to visual).
- Reframe Posts as the social/community posts module (user posts, threaded comments, boards, likes, mentions) rather than a blog/CMS — long-form publishing is handled by PhoenixKit's built-in Publishing module. Updated README, hex description, AGENTS.md and the admin-panel module description (PR #9).
- Upgrade dependencies: phoenix_kit 1.7.133, req 0.6.1.

### Fixed
- Removing an image from an existing post now actually detaches it — the `MediaGallery` `{:changed, …}` handler was calling `detach_media_by_uuid/1` (a PostMedia primary-key lookup) with a *file* uuid, so removals silently no-opped.
- Removing the featured (position 1) image no longer drops the post's featured image — media positions are renumbered to a contiguous `1..n` on every selection change, so `get_featured_image/1` (which matches `position == 1`) keeps resolving.
- Restore the `posts_max_media` cap in the post editor (wired through `MediaGallery`'s `max_count`).

## 0.1.4 - 2026-06-07

### Fixed
- Fix post comments silently posting empty content — the comment composer's Leaf rich-text editor reports its content to the host LiveView via a `{:leaf_changed, …}` process message, which `Details` never forwarded into `CommentsComponent.forward_leaf_event/2`, so "Post Comment" no-opped (PR #7). Now wired via the dependency's `use PhoenixKitComments.Embed` helper (a `:handle_info` lifecycle hook), which also drops the per-keystroke `Code.ensure_loaded` and the silent catch-all `handle_info/2` the initial fix introduced.
- Move LiveView DB queries from `mount/3` to `handle_params/3` across the post/group LiveViews — `mount/3` runs twice (HTTP + WebSocket), so querying there duplicated every read.

### Changed
- Require `phoenix_kit_comments ~> 0.2` (was `~> 0.1`) — `PhoenixKitComments.Embed` only exists in the 0.2.x line (resolved: 0.2.6).
- Upgrade dependencies: phoenix_kit 1.7.132, phoenix 1.8.7, ecto/ecto_sql 3.14, leaf 0.2.21, phoenix_live_view 1.1.31, earmark 1.4.49.
- Internal refactors: replace `Settings.get_setting(_, "true") == "true"` with `Settings.get_boolean_setting/2`; extract the post preload list to a `@post_preloads` module attribute.

## 0.1.3 - 2026-04-29

### Fixed
- Fix post edit page layout jumping/sidebar collapse when leaf editor mounts — switched the 2:1 row from flex to CSS grid (`grid-cols-3` + `col-span-2`) with `min-w-0` on both columns and `overflow-hidden` on the content column (PR #6)
- Fix runtime crash on post details page when comments are enabled — `live_component` was referencing the non-existent `PhoenixKit.Modules.Comments.Web.CommentsComponent`; now correctly uses `PhoenixKitComments.Web.CommentsComponent`
- Align stale deprecation docstrings in legacy comment/like/dislike schemas to the current `PhoenixKitComments.*` namespace

## 0.1.2 - 2026-04-11

### Fixed
- Fix wrong "In your Phoenix router" moduledoc example — routes are auto-generated by PhoenixKit, not hand-registered
- Add routing anti-pattern warning to AGENTS.md

## 0.1.1

- Migrate select elements to daisyUI 5 label wrapper pattern
- Remove deprecated select-bordered class for daisyUI 5 compatibility
- Add css_sources/0 for Tailwind CSS scanning

## 0.1.0

- Initial release
