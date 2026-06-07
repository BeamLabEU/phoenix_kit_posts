# PR #7 Review — Fix post comments: forward Leaf editor events to the component

**Reviewer:** Claude
**Date:** 2026-06-07
**Status:** Merged (commit `85ab711`); review is post-hoc, with a follow-up change applied this session
**Verdict:** Approve the fix — it's correct. Replaced the hand-rolled forwarding with the dependency's purpose-built `PhoenixKitComments.Embed` helper.

---

## Summary

The PR fixes a real bug: the comment composer's Leaf rich-text editor reports its
content to the **host LiveView** via a `{:leaf_changed, …}` process message (a
`LiveComponent` has no `handle_info/2`, so the message can only land in the host).
`Details` embedded `CommentsComponent` but never forwarded that message into
`CommentsComponent.forward_leaf_event/2`, so the `send_update` that stashes the
content in the component's `new_comment` assign never ran — and "Post Comment"
silently submitted empty content (no crash, no warning).

The PR forwarded the message using the dependency's documented **soft-dependency**
runtime pattern: `Code.ensure_loaded(PhoenixKitComments.Web.CommentsComponent)` +
a manual `forward_leaf_event/2` call, plus a catch-all `handle_info/2`.

---

## What Works Well

1. **Correct root cause.** The diagnosis is exactly right — the content travels by
   process message, not form params, and the host is the only place that message can
   be received. Confirmed against `deps/phoenix_kit_comments/lib/phoenix_kit_comments/embed.ex`
   and `comments_component.ex` (`forward_leaf_event/2`, `update/2` with
   `leaf_content_changed`, and the `add_comment` handler reading `socket.assigns.new_comment`).

2. **Honest commit message.** Notes it wasn't browser-tested (no local post data) and
   that the same fix was applied to sibling repos (staff/projects/media).

3. **Small, targeted diff** for a behaviorally significant fix.

---

## Issue — wrong pattern for a hard dependency (fixed this session)

`phoenix_kit_comments` is a **hard dependency** of this project, not an optional one:

- `mix.exs` declared `{:phoenix_kit_comments, "~> 0.1"}` (not `optional: true`).
- `details.html.heex:221` references `PhoenixKitComments.Web.CommentsComponent` directly.
- `mount/3` calls `PhoenixKitComments.enabled?()` unguarded (`details.ex:42`).

The PR used the dep's **soft-dependency** runtime pattern (`Code.ensure_loaded` +
manual call), which exists for hosts where comments is *optional*. For a hard dep,
the dependency ships `PhoenixKitComments.Embed` precisely for this wiring — one line,
maintained centrally. The hand-rolled version carried three avoidable problems:

1. **`handle_info(_msg, socket)` catch-all silently swallowed every unmatched
   message.** That hides real bugs — a future PubSub subscription or a typo'd message
   would vanish with no log. `Embed` attaches a `:handle_info` lifecycle hook that
   **halts only `:leaf_changed`** and passes everything else through (`{:cont, …}`),
   so no blanket catch-all is needed.

2. **`Code.ensure_loaded/1` ran on every editor change.** `:leaf_changed` fires
   repeatedly while typing; module resolution per keystroke is pure waste for a hard
   dep. `Embed` resolves at compile time.

3. **Dead nested `case`.** Both branches returned `{:noreply, socket}`, and
   `forward_leaf_event/2` never mutates the socket (it does `send_update` then returns
   the same socket, or `:pass`), so the inner `case` did nothing.

There was also **copy-paste drift**: the same 19-line block was pasted into
staff/projects/media. `Embed` is the dep's answer to exactly that — a future change to
the Leaf message protocol then needs editing in one place, not four.

---

## Follow-up Changes Applied (this session)

| File | Change |
|------|--------|
| `lib/phoenix_kit_posts/web/details.ex` | Added `use PhoenixKitComments.Embed`; removed the hand-rolled `handle_info({:leaf_changed, _})` clause (with its `Code.ensure_loaded` + dead nested `case`) and the silent `handle_info(_msg, socket)` catch-all. |
| `mix.exs` | `{:phoenix_kit_comments, "~> 0.1"}` → `"~> 0.2"` — `Embed` only exists in the 0.2.x line (resolved version is 0.2.6). |

Net effect: same fix, **−18 lines**, no per-keystroke module lookup, and no
bug-hiding catch-all. The existing `handle_info({:comments_updated, …})` clause is
untouched. Verified with `mix compile --warnings-as-errors` — clean.

### Why the `mix.exs` bump matters

`Embed` was added in `phoenix_kit_comments` 0.2.x. `use PhoenixKitComments.Embed` is
compile-time, so a resolve to a 0.1.x version would fail to compile. Tightening the
requirement to `~> 0.2` makes the dependency on `Embed` explicit. (The original
`Code.ensure_loaded` approach was version-tolerant — its only genuine advantage, and
one that doesn't apply to a hard dep we control.)

---

## Risk Assessment

- **Correctness:** low — the fix is sound and now uses the dependency's maintained
  helper. The behavior (forward `:leaf_changed` → `forward_leaf_event/2`, halt) is
  identical to the manual version, minus the swallow-everything catch-all.
- **Performance:** improved — compile-time hook instead of `Code.ensure_loaded` per
  keystroke.
- **Security:** none.
- **Regression surface:** removing the blanket `handle_info(_msg, …)` catch-all means
  an unexpected message will once again surface (LiveView logs it / the process can
  crash-and-reconnect) instead of being silently dropped. That's the desired behavior —
  the only messages this LV receives are `{:comments_updated, …}` (handled) and
  `{:leaf_changed, …}` (now halted by the `Embed` hook before `handle_info`).

---

## Remaining Items (not addressed)

1. **Browser test the comment-post flow.** Neither the PR author nor this session could
   exercise it (no local post data). Type a comment in the composer and confirm "Post
   Comment" persists the content.
2. **Apply the same `Embed` swap to the sibling repos** (staff/projects/media) that
   received the copy-pasted hand-rolled block, and bump their `phoenix_kit_comments`
   requirement to `~> 0.2`.
3. **Render test** for `details.html.heex` with `comments_enabled: true` exercising the
   composer would lock this in and catch a future regression.

---

## Verdict

Correct, well-diagnosed fix. The only change worth making was *how* it's wired:
because comments is a hard dependency here, the dependency's own
`use PhoenixKitComments.Embed` is cleaner, faster, and centrally maintained — and it
drops the silent catch-all that would otherwise hide future message-handling bugs.
