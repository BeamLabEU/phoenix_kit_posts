# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Project Overview

PhoenixKit Posts module — provides blog posts, tags, groups, likes/dislikes, media attachments, mentions, and scheduled publishing. Implements the `PhoenixKit.Module` behaviour for auto-discovery by a parent Phoenix application.

## Common Commands

```bash
mix deps.get          # Install dependencies
mix test              # Run all tests
mix test test/phoenix_kit_posts_test.exs  # Run specific test file
mix test --only tag   # Run tests matching a tag
mix format            # Format code
mix credo             # Static analysis / linting
mix dialyzer          # Type checking
mix docs              # Generate documentation
mix precommit         # Compile + format + credo + dialyzer
mix quality           # Format + credo + dialyzer
```

## Architecture

This is a **library** (not a standalone Phoenix app) that provides posts as a PhoenixKit plugin module.

### File Layout

```
lib/
  phoenix_kit_posts.ex                    # Main module — context + PhoenixKit.Module behaviour
  phoenix_kit_posts/
    schemas/
      post.ex                             # Post schema (title, content, status, type, counters)
      post_like.ex                        # Like tracking (one per user per post)
      post_dislike.ex                     # Dislike tracking (one per user per post)
      post_comment.ex                     # Comment schema (threaded via parent_uuid)
      comment_like.ex                     # Comment like tracking
      comment_dislike.ex                  # Comment dislike tracking
      post_tag.ex                         # Tag schema with auto-slugification
      post_tag_assignment.ex              # Many-to-many join for post ↔ tag
      post_group.ex                       # Group schema (Pinterest-style boards)
      post_group_assignment.ex            # Many-to-many join for post ↔ group
      post_media.ex                       # Media attachments with ordering
      post_mention.ex                     # User mentions in posts
      post_view.ex                        # View tracking schema
    handlers/
      scheduled_post_handler.ex           # Handler for scheduled publishing lifecycle
    web/
      posts.ex & posts.html.heex          # Admin post listing LiveView
      edit.ex & edit.html.heex            # Admin post create/edit LiveView
      details.ex & details.html.heex      # Admin post details LiveView
      groups.ex & groups.html.heex        # Admin group listing LiveView
      group_edit.ex & group_edit.html.heex # Admin group create/edit LiveView
      settings.ex & settings.html.heex    # Admin settings LiveView
    workers/
      publish_scheduled_posts_job.ex      # Oban worker for scheduled post publishing
```

### Key Modules

- **`PhoenixKitPosts`** (`lib/phoenix_kit_posts.ex`) — Main module implementing `PhoenixKit.Module` behaviour AND serving as the context module for all post operations (CRUD, likes/dislikes, tags, groups, media, mentions, scheduling).

- **`PhoenixKitPosts.Post`** (`lib/phoenix_kit_posts/schemas/post.ex`) — Ecto schema for posts. Fields: `title`, `subtitle`, `content`, `slug`, `type`, `status` (draft/public/unlisted/scheduled), `user_uuid`, `like_count`, `dislike_count`, `comment_count`, `view_count`, `scheduled_at`, `published_at`, `metadata`.

- **`PhoenixKitPosts.PostLike`** / **`PostDislike`** — Like/dislike tracking with unique constraint on `(post_uuid, user_uuid)`.

- **`PhoenixKitPosts.PostComment`** — Threaded comments with self-referencing `parent_uuid`, depth tracking, and like/dislike counters.

- **`PhoenixKitPosts.PostTag`** — Tag schema with auto-slugification. Assigned to posts via `PostTagAssignment`.

- **`PhoenixKitPosts.PostGroup`** — Pinterest-style board/collection schema. Assigned via `PostGroupAssignment`.

- **`PhoenixKitPosts.PostMedia`** — Media attachments with `position` for ordering.

- **`PhoenixKitPosts.PostMention`** — User mention tracking within posts.

- **`PhoenixKitPosts.ScheduledPostHandler`** — Lifecycle handler for scheduled post publishing.

- **`PhoenixKitPosts.Workers.PublishScheduledPostsJob`** — Oban worker that publishes posts when their `scheduled_at` time arrives.

### How It Works

1. Parent app adds this as a dependency in `mix.exs`
2. PhoenixKit scans `.beam` files at startup and auto-discovers modules (zero config)
3. `admin_tabs/0` callback registers the posts dashboard; PhoenixKit generates routes at compile time
4. `settings_tabs/0` registers the settings page under admin settings
5. Settings are persisted via `PhoenixKit.Settings` API (DB-backed in parent app)
6. Permissions are declared via `permission_metadata/0` and checked via `Scope.has_module_access?/2`

### Post Status

Four statuses as strings:
- `"draft"` — not visible publicly (default)
- `"public"` — visible to all
- `"unlisted"` — accessible via direct link but not listed
- `"scheduled"` — will be auto-published at `scheduled_at` time

### Like/Dislike Counters

- **Denormalized** on Post schema (`like_count`, `dislike_count`, `comment_count`, `view_count`)
- **Transaction-safe** increment/decrement operations
- **One-per-user** enforced by unique constraints

### Database Tables

- `phoenix_kit_posts` — Post records (UUIDv7 PK)
- `phoenix_kit_posts_likes` — Like records with unique `(post_uuid, user_uuid)` constraint
- `phoenix_kit_posts_dislikes` — Dislike records with unique `(post_uuid, user_uuid)` constraint
- `phoenix_kit_posts_comments` — Threaded comment records (self-referencing `parent_uuid`)
- `phoenix_kit_posts_comments_likes` — Comment like records
- `phoenix_kit_posts_comments_dislikes` — Comment dislike records
- `phoenix_kit_posts_tags` — Tag definitions
- `phoenix_kit_posts_tag_assignments` — Post ↔ tag many-to-many join
- `phoenix_kit_posts_groups` — Group/board definitions
- `phoenix_kit_posts_group_assignments` — Post ↔ group many-to-many join
- `phoenix_kit_posts_media` — Media attachments with ordering
- `phoenix_kit_posts_mentions` — User mention records
- `phoenix_kit_posts_views` — View tracking records

### Settings Keys

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

## Critical Conventions

- **Module key** must be consistent across all callbacks: `"posts"`
- **Tab IDs**: prefixed with `:admin_posts` (main tabs) and `:admin_settings_posts` (settings tab)
- **URL paths**: `/admin/posts` (dashboard), `/admin/settings/posts` (settings)
- **Navigation paths**: always use `PhoenixKit.Utils.Routes.path/1`, never relative paths
- **`enabled?/0`**: must rescue errors and return `false` as fallback (DB may not be available)
- **LiveViews use `PhoenixKitWeb` macros** — use `use PhoenixKitWeb, :live_view` (not `use Phoenix.LiveView` directly)
- **JavaScript hooks**: must be inline `<script>` tags; register on `window.PhoenixKitHooks`
- **LiveView assigns** available in admin pages: `@phoenix_kit_current_scope`, `@current_locale`, `@url_path`
- **UUIDv7 primary keys** — all tables use `uuid_generate_v7()`, never `gen_random_uuid()`
- **Admin routing** — plugin LiveView routes are auto-discovered by PhoenixKit and compiled into `live_session :phoenix_kit_admin`. Never hand-register them in a parent app's `router.ex`; use `live_view:` on a tab or a route module. See `phoenix_kit/guides/custom-admin-pages.md` for the authoritative reference

## Tailwind CSS Scanning

This module implements `css_sources/0` returning `["phoenix_kit_posts"]` so PhoenixKit's installer adds the correct `@source` directive to the parent's `app.css`. Without this, Tailwind purges CSS classes unique to this module's templates.

## Versioning & Releases

### Tagging & GitHub releases

Tags use **bare version numbers** (no `v` prefix):

```bash
git tag 0.1.0
git push origin 0.1.0
```

GitHub releases are created with `gh release create` using the tag as the release name. The title format is `<version> - <date>`, and the body comes from the corresponding `CHANGELOG.md` section:

```bash
gh release create 0.1.0 \
  --title "0.1.0 - 2026-03-24" \
  --notes "$(changelog body for this version)"
```

### Full release checklist

1. Update version in `mix.exs`, `lib/phoenix_kit_posts.ex` (`version/0`), and the version test
2. Add changelog entry in `CHANGELOG.md`
3. Run `mix precommit` — ensure zero warnings/errors before proceeding
4. Commit all changes: `"Bump version to x.y.z"`
5. Push to main and **verify the push succeeded** before tagging
6. Create and push git tag: `git tag x.y.z && git push origin x.y.z`
7. Create GitHub release: `gh release create x.y.z --title "x.y.z - YYYY-MM-DD" --notes "..."`

**IMPORTANT:** Never tag or create a release before all changes are committed and pushed. Tags are immutable pointers — tagging before pushing means the release points to the wrong commit.

## Pull Requests

### Commit Message Rules

Start with action verbs: `Add`, `Update`, `Fix`, `Remove`, `Merge`.

### PR Reviews

PR review files go in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/` directory. Use `{AGENT}_REVIEW.md` naming (e.g., `CLAUDE_REVIEW.md`, `GEMINI_REVIEW.md`). See `dev_docs/pull_requests/README.md`.

Review template should use severity levels: `BUG - CRITICAL`, `BUG - HIGH`, `BUG - MEDIUM`, `NITPICK`, `OBSERVATION`. Include a "What Was Done Well" section. Use `-- FIXED` notation for resolved issues.

## External Dependencies

- **PhoenixKit** (`~> 1.7`) — Module behaviour, Settings API, shared components, RepoHelper, Utils (Date, UUID, Routes), Users.Auth.User, Users.Roles
- **Phoenix LiveView** (`~> 1.0`) — Admin LiveViews
- **ex_doc** (`~> 0.34`, dev only) — Documentation generation
- **credo** (`~> 1.7`, dev/test) — Static analysis
- **dialyxir** (`~> 1.4`, dev/test) — Type checking
