# Changelog

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
