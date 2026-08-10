# PR #15 — Use core's slug rule instead of a local ASCII-only one

**Reviewed:** 2026-08-10 · **Author:** mdon · **Verdict:** merged, with two
small fixes on `main`. Released in **0.2.0**.

Reviewed as part of the phoenix_kit 2.0 sweep.

## Accepted

Replaces five hand-rolled slug pipelines (`Post`, `PostGroup`, `PostTag`, and
the auto-slug paths in `Web.Edit` / `Web.GroupEdit`) with core's
`Slug.slugify/2`. **Correctly passes `transliterate: true`** — which is the
whole ballgame, since core's option defaults to `false` and without it the
`[^a-z0-9]+` pass reproduces exactly the bug being replaced. Two other modules
in this same sweep got that wrong in different ways
(`phoenix_kit_document_creator#32` fixed it, `phoenix_kit_entities#26`
half-fixed it), so getting it right first time here is worth noting.

The `Web.Edit` comment identifies the real consequence precisely: an empty
generated slug is not merely ugly, the form reads it back as "no slug yet" and
regenerates on every subsequent save.

**`test/slug_generation_test.exs` is the best thing in the PR.** Its moduledoc
explains why it asserts *only* what holds at every core version, rather than the
obvious `assert slug("Видеопродакшн") == "videoprodakshn"` — that assertion is
version-dependent on which `phoenix_kit` resolves, and
`phoenix_kit_dashboards#5` shipped exactly that mistake and had to be repaired
after merge. Declining to write the satisfying-but-fragile assertion, and
documenting why, is the right call.

(Now that this module requires core `~> 2.0`, the `:transliterate` option is
guaranteed present, so those non-ASCII cases would in fact pass. The test stays
conservative, which costs nothing.)

## Fixed on `main`

- **A comment correction that was itself wrong, corrected again in 0.2.1.** In
  0.2.0 I rewrote the PR's "takes a locale when the caller knows one" comment to
  say `slugify/2` has no `:locale` option. That is true of core **1.7** — and the
  check behind it was run against core 1.7 in a sibling repo before its
  dependencies had been updated. Core **2.0.0** rewrote `PhoenixKit.Utils.Slug`
  to delegate to the `locale_slug` package, where `:locale` is fully supported:
  `Slug.slugify("Größe Fußball", locale: "de")` is `"groesse-fussball"`, and
  `locale: "et"` gives `"grosse-fussball"`. **The PR's original comment was
  right.** 0.2.1 restores an accurate version of it.

  No behaviour changed in either direction here — these three schemas slug a
  single-language name with no language in scope, so they pass no locale and
  never did. Only the comment was wrong. (`phoenix_kit_entities` did act on the
  same mistaken belief and had real behaviour reverted; see entities 0.3.1.)

  Also recorded there: `:transliterate` is **ignored** by core 2.0 — romanization
  is always on, and the option is accepted only so existing call sites keep
  compiling. So it is redundant here rather than load-bearing.
- **`mix credo --strict` failed** on three counts of "alias is not
  alphabetically ordered among its group" — the new `alias PhoenixKit.Utils.Slug`
  was inserted above `Routes`/`Roles`/`Date` in `post.ex`, `edit.ex` and
  `group_edit.ex`. Reordered.

## Verification

| Check | Result |
|---|---|
| `mix precommit` | **passes** against core 2.0.0, after the alias fix |
| `mix test` | **28 tests, 0 failures** |
