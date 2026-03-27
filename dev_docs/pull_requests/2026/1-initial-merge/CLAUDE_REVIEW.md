# Code Review: PR #1 — Initial Merge

**Reviewer:** Claude
**Date:** 2026-03-27
**PR:** https://github.com/BeamLabEU/phoenix_kit_posts/pull/1
**Scope:** 7211 additions — entire initial codebase (schemas, context, LiveViews, workers)

---

## BUG - CRITICAL

### 1. `get_post!/2` used where `get_post/2` is needed — will crash on nil

**File:** `lib/phoenix_kit_posts/web/details.ex`

```elixir
case PhoenixKitPosts.get_post!(post_uuid, preload: [...]) do
  nil -> ...   # <-- dead code, get_post! raises on nil
  post -> ...
end
```

`get_post!/2` raises `Ecto.NoResultsError` on missing records; it never returns `nil`. The `nil` branch is unreachable. If a user navigates to a nonexistent post UUID, the LiveView crashes. Same pattern in `lib/phoenix_kit_posts/web/posts.ex` (bulk operations and individual lookups).

**Fix:** Use `get_post/2` (without bang) in all these locations.

---

### 2. `eval()` of server-pushed JavaScript — XSS vector

**File:** `lib/phoenix_kit_posts/web/edit.html.heex`

```javascript
window.addEventListener("phx:exec-js", (e) => {
  if (e.detail && e.detail.js) {
    eval(e.detail.js);
  }
});
```

The server pushes arbitrary JS via `push_event("exec-js", %{js: js_code})` in `edit.ex`, and the client `eval()`s it. While the JS code is currently constructed from `file_uuid` values that go through `Jason.encode!`, the pattern of eval-ing server-sent strings is dangerous. If any upstream code or future change allows user-controlled data into the JS string, it becomes a stored XSS vector.

**Fix:** Use structured `push_event` data and have the client construct DOM manipulation from data rather than eval-ing code strings.

---

### 3. Like and dislike are not mutually exclusive

**File:** `lib/phoenix_kit_posts.ex` (`like_post/2`, `dislike_post/2`)

There is no mutual exclusion between likes and dislikes. A user can call both `like_post` and `dislike_post` on the same post, resulting in both `like_count` and `dislike_count` being incremented. Typical like/dislike systems are mutually exclusive — liking should remove an existing dislike and vice versa.

---

## BUG - HIGH

### 4. `list_posts/1` ignores `:page` and `:per_page` — no actual pagination

**File:** `lib/phoenix_kit_posts.ex` (`list_posts/1`)

The function accepts `:page` and `:per_page` in its documented opts, and these are passed from `load_posts/1` in `posts.ex`, but the implementation never applies `limit`/`offset` to the query. It always returns ALL posts. This means:
- The `count_posts` function in `posts.ex` loads all posts into memory to call `length()` — will degrade as data grows.
- `@total_count` always equals displayed count, so pagination UI never triggers.

---

### 5. Tag `usage_count` incremented unconditionally on `add_tags_to_post`

**File:** `lib/phoenix_kit_posts.ex` (`add_tags_to_post/2`)

```elixir
|> repo().insert(on_conflict: :nothing)  # silently ignores duplicates

# But ALWAYS increments usage_count:
from(t in PostTag, where: t.uuid == ^tag.uuid)
|> repo().update_all(inc: [usage_count: 1])
```

The insert uses `on_conflict: :nothing`, so duplicate assignments are silently skipped. But `usage_count` is incremented regardless, causing it to inflate every time a post is saved.

**Fix:** Check the insert return or use `insert_all` with returning to only increment for actually-new assignments.

---

### 6. `reorder_groups/2` and `reorder_media/2` ignore transaction result

**File:** `lib/phoenix_kit_posts.ex`

```elixir
def reorder_groups(user_uuid, group_uuid_positions) do
  repo().transaction(fn -> ... end)
  :ok  # <-- always returns :ok, ignoring transaction result
end
```

Same issue in `reorder_media/2`. If the transaction fails, the caller never knows.

---

### 7. View count double-incremented due to LiveView mount behavior

**File:** `lib/phoenix_kit_posts/web/details.ex` (`mount/3`)

```elixir
def mount(%{"id" => post_uuid}, _session, socket) do
  ...
  PhoenixKitPosts.increment_view_count(post)
  ...
end
```

LiveView `mount/3` is called twice: once for static render and once for WebSocket connection. Every visit increments view count by 2.

**Fix:** Guard with `if connected?(socket), do: PhoenixKitPosts.increment_view_count(post)`.

---

## BUG - MEDIUM

### 8. Post slug has no unique constraint

**File:** `lib/phoenix_kit_posts/schemas/post.ex` (`changeset/2`)

Slug is generated from title but has no `unique_constraint`. Two posts with the same title get the same slug, and `get_post_by_slug/2` returns whichever the DB picks first.

---

### 9. Group edit references `group.visibility` which doesn't exist on schema

**File:** `lib/phoenix_kit_posts/web/group_edit.ex`

```elixir
"visibility" => group.visibility || "public"
```

`PostGroup` schema has `is_public` (boolean), not `visibility` (string). This will raise `KeyError` when editing an existing group. Same issue in groups listing template (`visibility_badge_class(group.visibility)`).

---

### 10. `add_tag` event handler will never receive typed text

**File:** `lib/phoenix_kit_posts/web/edit.html.heex`

```html
<input phx-keydown="add_tag" phx-key="Enter" phx-value-tag="" />
```

`phx-value-tag=""` is hardcoded to empty string. When the user types a tag and presses Enter, the event always receives `%{"tag" => ""}`, which the handler rejects. The input value is never sent.

---

### 11. N+1 query issue in stats loading

**File:** `lib/phoenix_kit_posts/web/posts.ex` (`load_stats/1`)

Fires 5 separate queries, each loading ALL matching posts into memory just to count them. Combined with `handle_params` also calling `load_posts`, that's 6+ queries per navigation.

**Fix:** Use `Repo.aggregate/3` with `:count` or a single grouped query.

---

### 12. `content` not validated as required in `Post.changeset/2`

**File:** `lib/phoenix_kit_posts/schemas/post.ex`

```elixir
|> validate_required([:user_uuid, :title, :type, :status])
```

Documentation shows `content` as required, but it's not in `validate_required`. Posts can be created with nil content.

---

### 13. IP hash without salt is weak privacy protection

**File:** `lib/phoenix_kit_posts/schemas/post_view.ex`

```elixir
def hash_ip(ip_address) when is_binary(ip_address) do
  :crypto.hash(:sha256, ip_address) |> Base.encode16(case: :lower)
end
```

Unsalted SHA-256 of an IP is trivially reversible since the IPv4 address space is small (~4B). A rainbow table can be precomputed. Add a site-specific salt.

---

## NITPICK

### 14. Duplicated `slugify/1` across three schemas

`post.ex`, `post_group.ex`, `post_tag.ex` all have identical `slugify/1` and `maybe_generate_slug/1`. Extract to a shared utility.

---

### 15. Duplicated helper functions across LiveViews

`format_post_type/1`, `format_status/1`, `status_badge_class/1` duplicated in `details.ex` and `posts.ex`. Extract to a shared helpers module.

---

### 16. `PostTag.increment_usage/1` and `decrement_usage/1` are unused dead code

These modify in-memory structs but are never called. The context module uses `update_all(inc: ...)` directly.

---

### 17. Legacy comment schemas still referenced

`comment_dislike.ex`, `comment_like.ex`, `post_comment.ex` are marked "Legacy" with notes to use `PhoenixKit.Modules.Comments` instead, but are still in Post schema's `has_many` associations. Clarify migration strategy or remove associations.

---

### 18. Missing `@impl true` on Settings LiveView callbacks

`lib/phoenix_kit_posts/web/settings.ex` — `mount`, `handle_event` callbacks missing `@impl true` annotations, unlike all other LiveViews.

---

## OBSERVATION

### 19. Groups `load_groups` preloads `:posts` unnecessarily

`lib/phoenix_kit_posts/web/groups.ex` preloads all posts for every group just to show `length(group.posts || [])` in the template. `PostGroup` has a `post_count` field for this — use it and remove the `:posts` preload.

---

### 20. No server-side authorization check on `delete_post` in details LiveView

Template checks `can_edit_post?` to show/hide the delete button, but `handle_event("delete_post", ...)` does not verify authorization server-side. A crafted WebSocket message could delete any post.

---

### 21. `ScheduledPostHandler` and `PublishScheduledPostsJob` may double-publish

`ScheduledPostHandler` is registered via `ScheduledJobs.schedule_job` for individual posts, while the Oban cron worker queries ALL scheduled posts every minute. If both are configured, a post may be published twice.

---

### 22. Group search is non-functional

The groups LiveView adds a `:search` option to the keyword list, but `list_user_groups/2` never applies search filtering. The search bar UI does nothing.

---

## What Was Done Well

- **Thorough documentation** — Every module and public function has `@moduledoc`/`@doc` with examples, parameter descriptions, and validation rules.

- **Clean PhoenixKit.Module behaviour implementation** — Callbacks (`module_key/0`, `admin_tabs/0`, `settings_tabs/0`, `permission_metadata/0`) are well-structured and consistent.

- **Defensive counter operations** — Decrement functions guard against negative counts with `where p.like_count > 0`.

- **Consistent schema design** — UUIDv7 primary keys, `utc_datetime` timestamps, proper associations and foreign key constraints applied uniformly.

- **Transaction safety for compound operations** — `like_post`, `dislike_post`, `schedule_post`, `add_post_to_group` use `Repo.transaction` to keep record creation and counter updates atomic.

- **Two-pass media reorder strategy** — Uses a negative-position intermediate step to avoid unique constraint violations during reordering. Thoughtful approach.

- **Settings-driven configurability** — Nearly every feature aspect is configurable via the Settings API with sensible defaults and a comprehensive admin UI.

- **Timezone handling in scheduling** — The edit LiveView properly converts between user timezone and UTC when saving scheduled times.
