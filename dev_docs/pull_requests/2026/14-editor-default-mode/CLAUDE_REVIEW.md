# PR #14 — Open the post editor in the admin-configured default mode

**Author:** alexdont (`editor-default-mode`)
**Merge:** `ec26e98` (merges `ea9c846` into `c25bfc3`)
**Reviewer:** Claude (Opus 5)
**Date:** 2026-07-27

## Scope

Two lines:

- `web/edit.ex` — `mount/3` assigns `:editor_mode` from `PhoenixKit.Settings.get_editor_mode()`.
- `web/edit.html.heex` — passes `mode={@editor_mode}` to `<.leaf_editor>`.

The intent (from phoenix_kit core commit `f883bb73`, "Add site-wide Default Editor
Mode setting") is that core owns an `editor_default_mode` setting and exposes
`get_editor_mode/0` returning a validated atom, and that posts + comments "adopt it
in their next releases".

## Findings

### BUG - CRITICAL — `Settings.get_editor_mode/0` does not exist in any released phoenix_kit — FIXED

`get_editor_mode/0` was added to phoenix_kit core in commit `f883bb73` (2026-07-27),
which is **not in tag `v1.7.213`** — the latest release on Hex and the version this
package resolves to (`mix.lock`, pin `~> 1.7.189`). Verified two ways:

- `grep -r "editor_mode" deps/phoenix_kit/lib` → no matches anywhere in the tarball.
- `git merge-base --is-ancestor f883bb73 v1.7.213` in the core checkout → not an ancestor.

Consequences as merged:

1. **The gate fails.** `mix compile --force --warnings-as-errors` (step 1 of
   `mix precommit`) errors on
   `warning: PhoenixKit.Settings.get_editor_mode/0 is undefined or private`
   at `edit.ex:40`. The PR was merged without the gate passing.
2. **Every consumer's post editor crashes.** `mount/3` is the first thing that runs
   for `/admin/posts/new` and `/admin/posts/:id/edit`; an `UndefinedFunctionError`
   there takes the whole page down for anyone on the published core — i.e. everyone,
   until core cuts a release *and* this package's pin is raised to require it.

A dependency's unreleased `main` is not an API this package can call. The pin
(`~> 1.7.189`) explicitly admits core builds that predate the function, so even after
core ships it, a bare call would break consumers who resolve to an older 1.7.x.

**Fix:** probe before calling, exactly as the sibling `phoenix_kit_comments` module
does for the same setting (`comments_component.ex:1980`):

```elixir
@compile {:no_warn_undefined, {PhoenixKit.Settings, :get_editor_mode, 0}}

defp default_editor_mode do
  if Code.ensure_loaded?(Settings) and function_exported?(Settings, :get_editor_mode, 0) do
    __normalize_editor_mode__(Settings.get_editor_mode())
  else
    @default_editor_mode
  end
rescue
  _ -> @default_editor_mode
end
```

The module attribute covers the compile side (the call is legitimately absent until
core ships), the `function_exported?` probe covers the runtime side, and the `rescue`
covers a settings read raising when no repo is configured — same guard
`PhoenixKitPosts.enabled?/0` already uses. On today's core the editor opens in
`:hybrid` — Leaf's own default, so behaviour is unchanged — and the moment core
releases the setting, the admin's choice takes effect with no code change here. The
comment above the helper says to drop the probe once the pin requires a core that
exports it.

Dialyzer sees through the probe and reports `call_to_missing` regardless, so the fix
also adds a `.dialyzer_ignore.exs` with a single scoped entry (and wires
`ignore_warnings` + `list_unused_filters: true` into `mix.exs`, so the build *fails*
once the filter stops matching — the entry can't quietly outlive the core release that
makes it unnecessary). Same file, same entry, same reasoning as `phoenix_kit_comments`.

This mirrors the precedent already in this repo: `settings_section_header/1` is a
deliberate local copy of a core component "so this package renders identically without
requiring a core release that exports it".

### BUG - HIGH — an unexpected mode value crashes inside Leaf — FIXED

`mode` was passed straight through to `<.leaf_editor>`. Leaf's `normalize_mode/2`
(`deps/leaf/lib/leaf.ex:2624`) is guarded on `mode in [:visual, :hybrid, :markdown,
:html]` and has **no catch-all clause**, so anything else — a raw string from the
settings row, `nil`, a mode core adds later — raises `FunctionClauseError` inside the
component rather than degrading. `attr :mode`'s `values:` list does not help: HEEx only
validates literal attribute values at compile time, never a runtime `@assign`.

Core's `get_editor_mode/0` does validate today, but this package is what breaks if that
ever changes, and the probe path above can now surface a value core never sanitised.

**Fix:** all values go through `__normalize_editor_mode__/1`, which passes the four
atoms Leaf accepts, maps the setting's string values (`"visual"` → `:visual`, …), and
falls back to `:hybrid` for anything else. Locked by three tests in
`phoenix_kit_posts_test.exs` ("editor mode"): atom pass-through, string conversion, and
unknown/`nil` fallback. The function is `@doc false` public purely so the contract is
testable — same as the comments module.

### IMPROVEMENT - MEDIUM — the settings read belonged in `handle_params`, not `mount` — FIXED

`mount/3` runs twice for every editor page (HTTP render, then WebSocket connect), so a
settings read there is done twice. Every other setting this LiveView needs
(`posts_max_media`, `posts_default_status`, `posts_allow_scheduling`, …) is loaded in
`load_form_data/1`, which is reached from `handle_params/3` — once per navigation.

**Fix:** moved the `:editor_mode` assign into `load_form_data/1` next to the other
settings reads. Both `handle_params/3` clauses call it before the first render, so the
assign is always present when the template renders — the same guarantee the template's
existing `@max_content_length` / `@max_tags` assigns already rely on.

### BUG - MEDIUM — (outside this PR) stale `mix.lock` entry failed the gate — FIXED

`mix precommit` step 2 (`mix deps.unlock --check-unused`) aborted with
`Unused dependencies in mix.lock file: * :beamlab_ex_aws_sqs`. Introduced by
`6977328` ("lib upgrades"), not by PR #14: phoenix_kit 1.7.213 now depends on that
package under the `:ex_aws_sqs` key (`{:ex_aws_sqs, "~> 5.0", [hex:
:beamlab_ex_aws_sqs, ...]}`), so the old `"beamlab_ex_aws_sqs"` 4.0.0 entry was left
orphaned. Independent of this PR, but it blocks any release.

**Fix:** `mix deps.unlock --unused` — drops the one orphaned line; no resolved
version changes.

## What Was Done Well

- **Right seam.** `mode` is the correct Leaf attr for this, and passing it from the
  LiveView (rather than hard-coding in the template) is the right shape — the two-line
  diff is genuinely all the wiring the feature needs.
- **Seeded once, not per-render.** Leaf only honours `:mode` on its first render, and
  the PR reads the setting once at page load rather than re-reading it on every update
  — no per-keystroke settings lookup.
- **Consistent with the sibling module.** The same feature landed in
  `phoenix_kit_comments` in the same shape, so the two modules read the same core
  setting and stay in sync.

## Observations

- `mount/3` still calls `Settings.get_project_title()` (a settings read, twice per
  page). Pre-existing and repo-wide across these admin LiveViews — left alone rather
  than diverging one file from the house pattern.
- The setting is **core-owned** (`editor_default_mode`, admin UI under Settings →
  Content Editor), not a `posts_*` setting, so nothing was added to this module's
  settings page or to the settings table in `AGENTS.md` — deliberately, to avoid a
  second source of truth for the same knob.
- Once core releases `get_editor_mode/0`, the follow-up is: raise the `phoenix_kit`
  pin to that version, then replace `default_editor_mode/0`'s probe with a direct
  `Settings.get_editor_mode()` call (keeping `__normalize_editor_mode__/1`).
