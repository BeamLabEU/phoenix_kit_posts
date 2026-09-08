# AGENTS.md

Guidance for AI agents working on `phoenix_kit_posts`.

## Overview

Social, feed-style posts for PhoenixKit: user-generated posts (`post` /
`snippet` / `repost`), tags with hashtag parsing, Pinterest-style groups
(boards), likes and dislikes, media attachments with ordering and a featured
image, @mentions, a view counter, and scheduled publishing. Comments on a post
come from `phoenix_kit_comments`; the post details page embeds its
`CommentsComponent` and this module answers the comments resource-handler
callbacks. `PhoenixKitPosts` is both the `PhoenixKit.Module` implementation
and the context module for every post operation. This is a library, not a
standalone Phoenix app.

- **Depends on:** `phoenix_kit` `~> 2.16` (Hex; a hard floor, because core's
  chain adds `phoenix_kit_posts.time_zone` at V185 and `Post` maps it, so
  every read and write of the table fails with `42703 undefined_column` on an
  older core, and because `Post.changeset/2` and `Web.ScheduleInput` call
  `Utils.TimeZone.valid?/1` and `Utils.Date.parse_datetime_local/2`),
  `phoenix_kit_comments` `~> 0.3` (hard; `Web.Details` does an unguarded
  `use PhoenixKitComments.Embed`), `phoenix_live_view` `~> 1.1`, `mdex`
  `~> 0.13` (Markdown rendering on the details page; declared directly
  because core carries no Markdown dep). The Leaf editor comes through core.
- **Consumed by:** no sibling module depends on the package. Core reaches it
  optionally (`Code.ensure_loaded?/1`): `PhoenixKit.ResourceLinks` registers
  `PhoenixKitPosts` as the `"post"` comment resource handler, the Sitemap
  module lists public posts, and `ProcessScheduledJobsWorker` calls
  `process_scheduled_posts/0` as its catch-up. `phoenix_kit_comments` calls
  `on_comment_created/3`, `on_comment_deleted/3` and
  `resolve_comment_resources/1` through that registry.
- **Admin surface:** tab `:admin_posts` "Posts" at `/admin/posts` (group
  `:admin_modules`, `match: :prefix`), subtabs `:admin_posts_all` "All Posts"
  (`/admin/posts`, `match: :exact`) and `:admin_posts_groups` "Groups"
  (`/admin/posts/groups`); hidden CRUD tabs `/admin/posts/new`,
  `/admin/posts/:id`, `/admin/posts/:id/edit`, `/admin/posts/groups/new`,
  `/admin/posts/groups/:id/edit`; settings tab `:admin_settings_posts` at
  `/admin/settings/posts`. Every tab carries `permission: "posts"`.
- **Module key** `"posts"`; settings prefix `posts_`.

## What this module does NOT do

- Long-form articles, `.phk` content, versioned or multilingual pages: that is
  core's Publishing module. Posts is the social counterpart, not a CMS.
- Comment storage, threading or moderation: `phoenix_kit_comments` owns it.
  The `PostComment`, `CommentLike` and `CommentDislike` schemas map the older
  `phoenix_kit_post_comments` / `phoenix_kit_comment_likes` /
  `phoenix_kit_comment_dislikes` tables and are not used by the context
  (`Post.has_many :comments` still points at `PostComment`). Do not build new
  comment features on them.
- Per-view rows: view tracking is the denormalized `view_count`, bumped once
  per connected visit to the details page. The `PostView` schema
  (`phoenix_kit_post_views`) is not written by anything.
- Database migrations: every table ships in core's chain (see Database &
  migrations).
- Its own editor or media picker: the editor is core's Leaf component and the
  picker is core's `MediaSelectorModal`. The module's one JS bundle
  (`js_sources/0`) carries a single hook, the editor's media inserter.
- Its own PubSub topics: nothing here broadcasts.
- A comments handler registration in host config: core's `ResourceLinks`
  registers `"post"` automatically when the module is loaded.

## Commands

```bash
mix deps.get
createdb phoenix_kit_posts_test          # once; DB-backed tests are tagged :integration and auto-skip without it
mix test
mix precommit                # compile --warnings-as-errors + format + credo --strict + dialyzer; run before every commit
```

`phoenix_kit*` deps resolve from Hex. To run against a local checkout, export
`<APP>_PATH` (the dep's app name upper-cased plus `_PATH`); `pk_dep/3` in
`mix.exs` swaps the Hex pin for a `path:` dep at resolve time. Unset means the
Hex pin, so `mix hex.publish` is unaffected. Run `mix deps.get` with the var
exported before the first `mix test` (a stale lock aborts on the optional
`igniter` dep), and never commit a hand-edited `path:` tuple.

```bash
PHOENIX_KIT_PATH=../phoenix_kit mix deps.get && PHOENIX_KIT_PATH=../phoenix_kit mix test
```

Only `:phoenix_kit` goes through `pk_dep/3`. `:phoenix_kit_comments` is a
plain Hex pin, so a local comments checkout means a temporary
`{:phoenix_kit_comments, path: "../phoenix_kit_comments", override: true}`
reverted together with `mix.lock` before committing.
`test/core_pin_conformance_test.exs` fails on a committed `path:` dep and on a
three-segment core pin (`~> 2.16.x` would exclude the next core minor for every
host); move its `@must_admit` / `@must_reject` lists together with the pin.

## Conventions

- Module key `"posts"` in every callback. Tab ids are prefixed `:admin_posts`
  (main tabs) and `:admin_settings_posts` (settings). URL segments use
  hyphens, never underscores (the behaviour test checks tab paths).
- Navigation and redirects go through `PhoenixKit.Utils.Routes.path/1`; never
  a relative or hand-built path. The one raw path is the `path` that
  `resolve_comment_resources/1` returns (`/admin/posts/<uuid>`): the comments
  contract wants it WITHOUT the prefix, because the renderer applies
  `Routes.path/1` once.
- Routing: every admin page is a `live_view:` tuple on a tab in
  `admin_tabs/0` / `settings_tabs/0`; core compiles them into
  `live_session :phoenix_kit_admin`. No `route_module/0`. Never hand-register
  these routes in a host router (a different live_session loses the admin
  layout and breaks cross-session navigation); see core's
  `guides/custom-admin-pages.md`.
- LiveViews `use PhoenixKitWeb, :live_view` (all six). Templates are
  `.html.heex` colocated files; none wraps in `LayoutWrapper` (admin LVs never
  do). Core provides `@phoenix_kit_current_scope`, `@phoenix_kit_current_user`,
  `@current_locale` and `@url_path`.
- Gettext: own backend `PhoenixKitPosts.Gettext` (`priv/gettext`, locales en,
  et, ru; `priv` is in the Hex package files so the catalogs ship, and the
  behaviour test asserts a `ru` lookup resolves). **All six LiveViews carry
  `use Gettext, backend: PhoenixKitPosts.Gettext` directly under their
  `use PhoenixKitWeb, :live_view`, and a new one must too.** The backend is
  resolved per call site at expansion time, so the ORDER is the whole rule: a
  `gettext/1` written above that line still binds to core's backend, its msgid
  lands in no catalogue of this package, and it renders raw English in every
  locale with no compile error and no runtime signal. A colocated
  `.html.heex` compiles into its module, so the template inherits whichever
  binding the module ends with. Extract and merge from the repo root
  (`mix gettext.extract && mix gettext.merge priv/gettext`); `en` is
  intentionally all-empty (fallback to the msgid). No catalog-data strings
  need `*_noop` anchors today.
- JS hooks: one bundle, `priv/static/assets/phoenix_kit_posts.js`, assigning
  `window.PhoenixKitPostsHooks` and declared by `js_sources/0` (`@impl` is
  fine — the 2.16 core floor declares the callback). It holds
  `PhoenixKitPostsMediaInserter`, the post editor's media inserter. Hook names
  stay namespaced because the fold into `window.PhoenixKitHooks` is
  last-write-wins across every module's bundle and core's own hooks. Never
  register a hook or a page helper from an inline `<script>` in a template:
  morphdom does not execute a script tag it inserts, so it works on a hard
  page load and is silently dead after any LiveView navigation.
- `enabled?/0` reads `posts_enabled` and rescues everything to `false` (the
  DB may not be up). The other rescue sites are deliberate and short:
  `count_posts/1` (to `0`), `resolve_comment_resources/1` (to `%{}`),
  `log_post_activity/4` (to `:ok`) and `Post.unique_slug/2` (to the
  unsuffixed slug). Everything else raises; do not add blanket rescues.
  `PhoenixKit.RepoHelper.repo/0` is the only repo access.
- Activity logging: `log_post_activity/4` writes `PhoenixKit.Activity.log/1`
  entries with `module: "posts"`, `mode: "auto"`, `resource_type: "post"`,
  `resource_uuid`, and metadata `%{"actor_role" => "user", "title" => title}`.
  Actions are `post.created`, `post.published`, `post.deleted` (updates are
  not logged). The actor is the creator for `created`; for `published` and
  `deleted` it is the `:actor_uuid` option when the caller passes one (the
  admin LiveViews pass the current user), else the post's author. Guarded
  with `Code.ensure_loaded?(PhoenixKit.Activity)` and rescued, so logging can
  never fail the post operation. Metadata carries the title and nothing else
  about the user.
- Soft delete: none. `delete_post/2` is a hard delete; the FK cascades remove
  media, likes, assignments and mentions.
- Statuses are strings: `draft` (default), `public`, `unlisted`, `scheduled`.
  Types: `post`, `snippet`, `repost` (a repost carries `repost_url`).
- Publishing is a single-statement compare-and-swap. `publish_post/2` updates
  `WHERE status IN only_if` (default `draft`/`scheduled`/`unlisted`) with
  `update_all`, so exactly one caller wins and logs, however many hold the
  same stale struct. A loser gets `{:ok, reloaded}` (never an error, because
  the scheduled handler turns errors into failed jobs). Never move that guard
  back onto the in-memory `post.status`. Publishing bypasses
  `Post.changeset/2` on purpose (sets `updated_at` by hand) so it cannot
  regenerate the slug.
- Two sweeps exist by design: this module's Oban worker
  `Workers.PublishScheduledPostsJob` (`queue: :posts`, `max_attempts: 3`) and
  core's `ProcessScheduledJobsWorker` catch-up, both calling
  `process_scheduled_posts/0`. The sweep and `ScheduledPostHandler` pass
  `only_if: ["scheduled"]`, so a post moved back to draft after scheduling is
  never published by a retry or a sweep. `process_scheduled_posts/0` counts
  only winners.
- Scheduling: `schedule_post/4` sets `status: "scheduled"` + `scheduled_at`,
  cancels pending `ScheduledJobs` rows for the post, and creates a new job for
  `ScheduledPostHandler` (`job_type "publish_post"`, `resource_type "post"`)
  in one transaction; `unschedule_post/1` cancels the jobs and reverts to
  draft. `Post.changeset/2` refuses a past `scheduled_at` only when the
  schedule or the status is what is changing, so editing other fields of a
  scheduled post keeps its schedule.
- `scheduled_at` is stored as a UTC instant and edited as a `datetime-local`
  wall clock in the EDITOR's zone (`Web.ScheduleInput`: the user's
  `user_timezone`, else the site `time_zone` setting, else UTC, via core's
  `get_user_timezone/1`); named zones follow daylight saving on the date
  typed, legacy fixed offsets still work. The zone the schedule was typed in
  is kept in `Post.time_zone` (validated by `Utils.TimeZone.valid?/1`, max 64
  chars; nil on rows older than the column).
- Slugs: `Post.changeset/2` treats an ABSENT `slug` change as "unchanged",
  an explicit non-blank slug as authoritative, and an explicitly blank slug as
  "regenerate from the title" (the column is NOT NULL). Generation uses
  core's `Slug.slugify/2` (romanizing) and core's `Slug.ensure_unique/2`
  (suffix `-2`, `-3`, ... until free, excluding the post's own row). The
  uniqueness probe is advisory; the DB unique index on `slug` is the
  authority, and `get_post_by_slug/2` uses `repo().one()`, which raises on
  duplicates. `PostTag` and `PostGroup` slug the same way (tag slug unique;
  group slug unique per `user_uuid`).
- Post content is Markdown, rendered on the details page by MDEx with GFM
  extensions and `render: [unsafe: true]`, then passed through core's
  `HtmlSanitizer.sanitize/1`. Never render post HTML without the sanitizer.
- Editor mode: the setting value goes straight to Leaf's `:mode`, whose
  normalizer has no catch-all, so `Web.Edit.__normalize_editor_mode__/1` maps
  anything outside `[:visual, :hybrid, :markdown, :html]` to `:hybrid`.
  `PhoenixKit.Settings.get_editor_mode/0` is probed at runtime.
- Media: `PostMedia` rows are unique on `(post_uuid, position)`; the
  featured image IS the row at `position: 1` (`set_featured_image/2` deletes
  and reinserts it in a transaction), so a reorder that moves another file
  to position 1 changes the featured image. Content
  image/video insertion into the body is `push_event("insert-media", %{items:
  [%{url, type}]})` from `Web.Edit`. LiveView redispatches a pushed event on
  `window` as `phx:insert-media`, and the `PhoenixKitPostsMediaInserter` hook
  — bound to the hidden `#post-content-media-inserter` div in
  `web/edit.html.heex`, whose `data-editor-id` names the Leaf editor — writes
  each item into the editor's visual surface, or its markdown textarea as the
  fallback. File URLs come from core's `Storage.URLSigner`.
- Authorization in the LiveViews: editing and deleting a post require the
  current user to own it or to hold the admin/owner role
  (`PhoenixKit.Users.Roles`). Tab access is the `"posts"` permission.
- Comments seam: `Web.Details` renders
  `PhoenixKitComments.Web.CommentsComponent` with `resource_type="post"` and
  keeps `use PhoenixKitComments.Embed`, which forwards the composer's
  `{:leaf_changed, ...}` message into the component; without it "Post
  Comment" silently submits empty content. `on_comment_created/3` and
  `on_comment_deleted/3` maintain `comment_count`; the `{:comments_updated,
  _}` message refreshes the page.
- UUIDv7 primary keys everywhere (`uuid_generate_v7()`, never
  `gen_random_uuid()`); every table-backed schema has
  `use PhoenixKit.SchemaPrefix` right after `use Ecto.Schema`
  (`test/schema_prefix_conformance_test.exs` enforces it).
- `css_sources/0` returns `[:phoenix_kit_posts]` (an atom list, the OTP app
  name), so the host's Tailwind picks up this module's templates. Without it
  classes unique to these templates are purged.
- Dialyzer runs with `list_unused_filters: true`; `.dialyzer_ignore.exs` is
  intentionally empty. An entry covering a not-yet-released core API is
  removed the moment the floor moves to the release that adds it.

### Landmines

- A new string renders raw English in `et`/`ru` while every catalogue count
  says "complete": its `gettext/1` call sits ABOVE the
  `use Gettext, backend: PhoenixKitPosts.Gettext` line in its module (or the
  module has none), so it bound to core's backend and its msgid is in no
  catalogue here. Nothing warns. The check is a code-vs-catalogue diff, not an
  empty-msgstr count: `grep` the msgids out of `lib/` and look for them in
  `priv/gettext/default.pot`. This bit every LiveView but `Web.Settings`
  before 2026-09-08.
- A hook or page helper that works on a hard reload and does nothing after a
  live navigation is registered from an inline `<script>` — morphdom does not
  execute inserted script tags, and the LiveSocket's hook map was fixed at
  construction (the console reads `unknown hook found for "…"`). This is what
  killed editor media insertion before 2026-09-08. Everything client-side goes
  in `priv/static/assets/phoenix_kit_posts.js`.
- The media inserter is dead in a host that does not run core's
  `:phoenix_kit_js_sources` compiler: the bundle only reaches the browser
  through the host's `compilers:` list plus the vendored
  `/assets/vendor/phoenix_kit_modules.js` script tag. The compiler re-folds on
  every host `mix compile`, so a deploy that recompiles the host is enough;
  a host that never registered the compiler gets a compile-time warning from
  `PhoenixKitWeb.Integration` and nothing else. Since this is the module's
  first bundle, check that warning on a host before blaming the hook.
- The module reports itself disabled, every count reads 0, or a suite passes
  while exercising nothing: `enabled?/0` and `count_posts/1` rescue DB errors
  into `false` / `0`. Two causes: `config :phoenix_kit, repo:` missing (the
  harness test is the loud failure), or a core below 2.16 (`42703
  undefined_column` on `time_zone` from every query that names `Post`).
- A post published twice, logged twice, or a scheduled post that the author
  drafted going live anyway: someone reintroduced an in-memory status check
  or dropped `only_if: ["scheduled"]` from the sweep/handler path. The
  compare-and-swap in `transition_to_public/2` is the guard; the
  `Integration.PublishPostTest` asserts one activity row.
- `Ecto.MultipleResultsError` from `get_post_by_slug/2` means duplicate slugs
  got in; `unique_slug/2` rescues a missing repo into the unsuffixed slug, so
  a suite without a DB cannot see collisions. `Integration.SlugUniquenessTest`
  is the check.

## Architecture

```
lib/
  phoenix_kit_posts.ex                    # PhoenixKit.Module callbacks + the whole context
  phoenix_kit_posts/
    gettext.ex                            # PhoenixKitPosts.Gettext backend (priv/gettext)
    schemas/
      post.ex                             # Post: statuses, types, slug + time_zone rules
      post_like.ex, post_dislike.ex       # one row per (post_uuid, user_uuid)
      post_tag.ex, post_tag_assignment.ex # tags (auto-slug) + join
      post_group.ex, post_group_assignment.ex  # boards (slug unique per user) + join
      post_media.ex                       # (post_uuid, position) unique; position 1 = featured
      post_mention.ex                     # (post_uuid, user_uuid) unique; mention_type
      post_view.ex                        # unused; view_count on Post is the counter
      post_comment.ex, comment_like.ex, comment_dislike.ex  # legacy; comments live in phoenix_kit_comments
    handlers/scheduled_post_handler.ex    # PhoenixKit.ScheduledJobs.Handler: publish_post(only_if: ["scheduled"])
    workers/publish_scheduled_posts_job.ex # Oban cron worker, queue :posts, calls process_scheduled_posts/0
    web/
      posts.ex (+ .html.heex)             # list, filters, search, pagination, bulk publish/delete
      edit.ex (+ .html.heex)              # create/edit: Leaf editor, tags, mentions, groups, schedule, slug, media
      details.ex (+ .html.heex)           # single post, Markdown render, likes, embedded comments
      groups.ex, group_edit.ex (+ .html.heex)
      settings.ex (+ .html.heex)          # the posts_* settings page
      schedule_input.ex                   # datetime-local <-> UTC in the editor's zone
priv/gettext/                             # default.pot + en/et/ru
priv/static/assets/phoenix_kit_posts.js   # js_sources/0 bundle: PhoenixKitPostsMediaInserter
test/support/                             # Test.Repo, DataCase (fixtures + assert_activity_count/3)
```

Key context areas in `PhoenixKitPosts`: CRUD (`create_post/2` requires an
existing user, `update_post/2`, `delete_post/2`, `get_post/2`, `get_post!/2`,
`get_post_by_slug/2`, `list_posts/1` with `:user_uuid` / `:status` / `:type` /
`:search` / `:page` + `:per_page` / `:preload`, `count_posts/1`,
`list_public_posts/1`); publishing (`publish_post/2`, `schedule_post/4`,
`unschedule_post/1`, `draft_post/1`, `process_scheduled_posts/0`); counter
caches (`increment_*`/`decrement_*` for like, dislike, comment; `view`);
likes/dislikes (`like_post/2` ... `list_post_dislikes/2`); comments handler
callbacks; tags (`find_or_create_tag/1`, `parse_hashtags/1`,
`add_tags_to_post/2`, `remove_tag_from_post/2`, `list_popular_tags/1`); groups
(`create_group/2` ... `reorder_groups/2`, `add_posts_to_group/3`); mentions;
media (`attach_media/3`, `detach_media/2`, `reorder_media/2`,
`set_featured_image/2`, `get_featured_image/1`, `remove_featured_image/1`).

### Tables (all in core's chain)

| Table | Schema | Notes |
|-------|--------|-------|
| `phoenix_kit_posts` | `Post` | slug unique; `user_uuid` NOT NULL FK; `time_zone` |
| `phoenix_kit_post_likes` | `PostLike` | unique `(post_uuid, user_uuid)` |
| `phoenix_kit_post_dislikes` | `PostDislike` | unique `(post_uuid, user_uuid)` |
| `phoenix_kit_post_tags` | `PostTag` | slug unique (`phoenix_kit_post_tags_slug_index`) |
| `phoenix_kit_post_tag_assignments` | `PostTagAssignment` | unique `(post_uuid, tag_uuid)` |
| `phoenix_kit_post_groups` | `PostGroup` | unique `(user_uuid, slug)` |
| `phoenix_kit_post_group_assignments` | `PostGroupAssignment` | unique `(post_uuid, group_uuid)` |
| `phoenix_kit_post_media` | `PostMedia` | unique `(post_uuid, position)` |
| `phoenix_kit_post_mentions` | `PostMention` | unique `(post_uuid, user_uuid)` |
| `phoenix_kit_post_views` | `PostView` | unused |
| `phoenix_kit_post_comments` | `PostComment` | legacy |
| `phoenix_kit_comment_likes` | `CommentLike` | legacy |
| `phoenix_kit_comment_dislikes` | `CommentDislike` | legacy |

Denormalized counters on `Post`: `like_count`, `dislike_count`,
`comment_count`, `view_count`, maintained by the context, never by the
LiveViews directly.

### Permissions

One permission key, `"posts"` (`permission_metadata/0`; icon
`hero-document-text`). No sub-permissions. Ownership vs admin/owner role is
checked in the LiveViews, not by core.

### Settings keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `posts_enabled` | boolean | true | Module on/off |
| `posts_per_page` | integer | 20 | Posts per page in admin listing |
| `posts_default_status` | string | "draft" | Default status for new posts |
| `posts_likes_enabled` | boolean | true | Enable/disable like system |
| `posts_allow_scheduling` | boolean | true | Allow scheduled publishing |
| `posts_allow_groups` | boolean | true | Allow post groups/boards |
| `posts_allow_reposts` | boolean | true | Allow reposting |
| `posts_seo_auto_slug` | boolean | true | Auto-generate URL slugs |
| `posts_show_view_count` | boolean | true | Show view counts publicly |
| `posts_require_approval` | boolean | false | Require admin approval |
| `posts_max_media` | integer | 10 | Max media attachments per post |
| `posts_max_title_length` | integer | 255 | Max title character length |
| `posts_max_subtitle_length` | integer | 500 | Max subtitle character length |
| `posts_max_content_length` | integer | 50000 | Max content character length |
| `posts_max_mentions` | integer | 10 | Max mentions per post |
| `posts_max_tags` | integer | 20 | Max tags per post |

Settings are read and written through `PhoenixKit.Settings` (`*_with_module`
writers tag them with module `"posts"`).

PubSub topics: none.

## Database & migrations

None. Tables `phoenix_kit_posts`, `phoenix_kit_post_likes`,
`phoenix_kit_post_dislikes`, `phoenix_kit_post_tags`,
`phoenix_kit_post_tag_assignments`, `phoenix_kit_post_groups`,
`phoenix_kit_post_group_assignments`, `phoenix_kit_post_media`,
`phoenix_kit_post_mentions`, `phoenix_kit_post_views`,
`phoenix_kit_post_comments`, `phoenix_kit_comment_likes` and
`phoenix_kit_comment_dislikes` ship in core's chain (V135 baseline;
`phoenix_kit_posts.time_zone` from V185); `migration_module/0` is unset. A
schema change is a core migration first (raise this module's core floor to
the release that ships it, with the conformance test's lists), then schema
edits here. UUIDv7 PKs and `use PhoenixKit.SchemaPrefix` on every table-backed
schema.

## Testing

- Test DB `phoenix_kit_posts_test` (`MIX_TEST_PARTITION` appended);
  `PGDATABASE` overrides the name, `PGUSER` / `PGPASSWORD` / `PGHOST` the
  connection (defaults `postgres` / `postgres` / `localhost`), `PGPOOL` the
  pool size (default `schedulers_online() * 2`). `config/test.exs` also sets
  `config :phoenix_kit, repo: PhoenixKitPosts.Test.Repo`; without it
  `RepoHelper.repo/0` resolves nothing and the context is untestable.
- Two tiers. Unit tests (behaviour, core-pin and schema-prefix conformance,
  slug generation, `ScheduleInput` conversions, editor-mode normalization)
  run with no database. `:integration` tests use `PhoenixKitPosts.DataCase`
  and are excluded automatically when the DB is unreachable;
  `test_helper.exs` probes with `SELECT 1` first, because `start_link/0`
  succeeds lazily against a missing database.
- Schema: `PhoenixKit.Migration.ensure_current(TestRepo, log: false)` builds
  everything (no module chain). A `PhoenixKit.Migrations.BelowFloorError` is
  re-raised, not folded into "no database", so a core below the floor fails
  the run instead of skipping half of it. `Phoenix.PubSub` is started as
  `PhoenixKit.PubSub` because activity logging broadcasts.
- Support: `PhoenixKitPosts.Test.Repo`; `DataCase` with `user_fixture/1`
  (inserts a `PhoenixKit.Users.Auth.User` directly, skipping the
  rate-limited registration path), `post_fixture/2` (inserts directly so
  tests can set statuses and past `scheduled_at` values the changeset
  refuses), and `assert_activity_count/3` (counts rows in
  `phoenix_kit_activities`; a refute-shaped assertion would pass on a wholly
  broken activity pipeline).
- `test/integration/harness_test.exs` proves the repo, the tables and the
  activity table are wired before anything relies on them. Slug
  generation tests assert only what holds on every core version (ASCII
  cases), by design.
- Four source-level guards in `test/phoenix_kit_posts_test.exs` cover the two
  defect classes that produce no compile error and no runtime signal: every
  file calling `gettext/1` has the rebinding in its module (templates checked
  against their companion `.ex`); every `gettext("…")` literal in `lib/` is a
  msgid in `default.pot` (the code-vs-catalogue diff — an empty-msgstr count
  cannot see a msgid that went to the wrong backend); `js_sources/0` points at
  a bundle that really is in `priv/` under a `PhoenixKitPosts*` global; and
  every `phx-hook="PhoenixKitPosts…"` in a template names a hook the bundle
  defines. All four fail when broken — verified by breaking them.
- Known noise: none recorded.

## Feature notes

None. Feature behaviour is documented in `@moduledoc`s and the comments beside
the code (`Post.changeset/2` for slug and schedule rules,
`PhoenixKitPosts.transition_to_public/2` for the publish compare-and-swap,
`Web.ScheduleInput` for the timezone round trip).

## Versioning & releases

SemVer. The version is single-sourced in `mix.exs` (`@version`); `version/0`
reads it at compile time and the behaviour test asserts against
`Mix.Project.config()[:version]`, so nothing else needs bumping.

Release procedure (the steps the maintainer runs):

1. Bump `@version` in `mix.exs`; add a `CHANGELOG.md` entry headed `## x.y.z - YYYY-MM-DD`.
2. `mix precommit` clean.
3. Commit (`"Bump version to x.y.z"`) and push; verify the push landed.
4. `mix hex.publish`.
5. Tag, matching the form of the newest existing tag (`git tag --sort=-creatordate | head -1` shows it), and push the tag.
6. GitHub release via `gh release create` if the repo does those (`gh release list` shows whether it does).

Tags are immutable pointers: never tag before the commit is pushed and the
publish has succeeded.

## Pull requests & commits

- Commit messages start with an action verb (`Add`, `Update`, `Fix`, `Remove`, `Merge`). No AI attribution and no `Co-Authored-By` trailers.
- Version bumps and CHANGELOG entries land with the release commit on upstream, not in feature PRs.
- Review files live in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/{AGENT}_REVIEW.md`, one file per reviewing agent, never edited by another agent; `FOLLOW_UP.md` records how each finding was resolved. Severities: `BUG - CRITICAL/HIGH/MEDIUM`, `IMPROVEMENT - HIGH/MEDIUM`, `NITPICK`.

## TODOs

- Translate the `et`/`ru` msgstrs for the six msgids the 2026-09-08 extract
  added (the `Web.Posts` row actions and `Web.Edit`'s generic save error).
  They are empty on purpose — English beats an invented translation — so
  those strings still render English. Trigger: a translator pass.
- Most user-facing copy in `Web.Posts`, `Web.Edit`, `Web.Details`,
  `Web.Groups` and `Web.GroupEdit` is still bare literals, not `gettext/1`
  calls; the backends are now bound correctly, but only 6 strings outside
  `Web.Settings` are extractable. Trigger: an i18n pass on the admin pages.
- Drop or repurpose the legacy comment schemas (`PostComment`, `CommentLike`,
  `CommentDislike`) and `PostView`. Trigger: a core migration that retires
  the tables; until then leave the schemas so `Post` still compiles.
