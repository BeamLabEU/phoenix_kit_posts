# PR #22 — permission sweep: review record

**Author:** Max Don (with Claude)
**Reviewers:** zai (round 1), grok (round 2); findings checked against the code by Claude before fixing
**Verdict:** every confirmed finding fixed in this PR, each with a test that fails when the fix is reverted.

The sweep's rules: a sub-key `<base>.<sub>` is checked with `Scope.can?/2` in `mount/3` and every write
event against the live scope; new sub-keys are backfilled once to current base-key holders, with the
flag set only after every grant succeeded. Round 1 reviewed the whole change, round 2 only the fixes.

## Findings

- MEDIUM — the board filter listed every user's private boards → own + public unless `posts.view_all`; adding to another's board needs `posts.manage_all`.
- MEDIUM (round 2) — the filter and Add menu had been swapped in that fix → fixed, tested on the rendered elements.
- NITPICK — a crafted map value crashed the settings save → non-scalars ignored.
