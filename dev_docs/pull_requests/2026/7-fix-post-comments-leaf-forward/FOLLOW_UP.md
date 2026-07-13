# PR #7 Follow-up — Fix post comments: forward Leaf editor events

After-action for `CLAUDE_REVIEW.md`. Verdict **Approve** (the fix was correct); the review's one substantive change — *how* it was wired — plus its three "Remaining Items" are tracked below. Verified against current code.

## Fixed (post-review)
- ~~**Wrong pattern for a hard dep** — PR #7 used the soft-dep runtime pattern (`Code.ensure_loaded` + manual `forward_leaf_event/2` + a dead nested `case` + a blanket `handle_info(_msg)` catch-all that silently swallowed every unmatched message).~~ Re-wired to `use PhoenixKitComments.Embed` (`d37b5e9`): a `:handle_info` lifecycle hook that halts only `:leaf_changed`; dropped the per-keystroke `Code.ensure_loaded`, the dead `case`, and the bug-hiding catch-all. Bumped `phoenix_kit_comments` to `~> 0.2` (Embed lives in 0.2.x; resolved 0.2.6).
- ~~**Remaining Item #2** — apply the same `Embed` swap to the sibling repos (staff / projects / media) that received the copy-pasted hand-rolled block, and bump their `phoenix_kit_comments` requirement to `~> 0.2`.~~ **Done across the set (2026-06-08):**
  - **media (core)** — extracted to `PhoenixKitWeb.CommentsForwarding.forward_leaf_changed/2` by the maintainer (`phoenix_kit` `d9a483a2`); `media_detail` + `MediaBrowser.Embed` delegate to it.
  - **projects** — `project_show_live` now `use`s the Embed (`phoenix_kit_projects` `4e47f9f`, in PR #20); comments already pinned `~> 0.2`. Hard dep (renders `CommentsComponent` directly); the LV's blanket catch-all was *kept* because it legitimately serves its `{:projects, _, _}` PubSub subscription.
  - **staff** — converted from soft to hard dep: declared `phoenix_kit_comments ~> 0.2`, `use PhoenixKitComments.Embed`, dropped the hand-rolled forward + `comments_module/0` (`phoenix_kit_staff` `4f1a4fc`, **local-only — staff is not shipped**).

## Skipped (with rationale)
The review's other two Remaining Items are **net-new test coverage** on an already-merged + released (0.1.4) module, not regressions. Surfaced to Max 2026-06-08; **decision: skip.**
- **Remaining Item #1 — browser-test the comment-post flow.** Skipped.
- **Remaining Item #3 — render test for `details.html.heex`.** Skipped — posts has no LiveView test harness (no `Test.Endpoint`/`Router`/`LiveCase`), so this would mean building that infra. The exact `use PhoenixKitComments.Embed` wiring posts now uses is already pinned elsewhere: `phoenix_kit_comments` `test/embed_test.exs` (unit — hook routing) + `phoenix_kit_staff` `PersonShowLive` tests (integration — toggle-on render + the real `:leaf_changed` forward path). A third copy here is low marginal value for high cost.

The staff sibling-swap also got its `PersonShowLive` tests updated (de-staled soft-dep assertions + a comments-enabled render test) in the local staff work.

## Open
None.
