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

- **The "takes a locale when the caller knows one" comment is wrong** and was
  repeated in all three schema files. `PhoenixKit.Utils.Slug.slugify/2` reads
  exactly two options, `:separator` and `:transliterate`; a `:locale` key is
  silently discarded, and core's romanization is a Cyrillic map plus an NFD
  combining-mark strip, which is not locale-sensitive by construction — "ö"
  becomes "o" for every language. This is the same false belief that
  `phoenix_kit_entities#26` acted on by actually passing the option. Rewrote the
  comment to state what core does, and to flag that `transliterate: true` is
  load-bearing rather than decorative.
- **`mix credo --strict` failed** on three counts of "alias is not
  alphabetically ordered among its group" — the new `alias PhoenixKit.Utils.Slug`
  was inserted above `Routes`/`Roles`/`Date` in `post.ex`, `edit.ex` and
  `group_edit.ex`. Reordered.

## Verification

| Check | Result |
|---|---|
| `mix precommit` | **passes** against core 2.0.0, after the alias fix |
| `mix test` | **28 tests, 0 failures** |
