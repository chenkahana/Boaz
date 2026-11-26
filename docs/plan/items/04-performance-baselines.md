# PLAN-04: Performance baselines refreshed

Wave: 0 Stability
Status: Ready
Depends on: nothing

## Goal

Re-measure the docs/qa.md §4 table on current Release builds, replace the stale baselines, and make "worse than
the previous cycle is a bug" enforceable again.

## Why

The recorded baselines predate the Chromium engine entirely ("before #12", WebKit Debug builds). There is no
current number to regress against, so slowdowns ship unnoticed.

## Scope

- Run every §4 row (launch, new tab, typing with 50k visits, 150 tabs, archive, memory) on the current Chromium
  DMG Release build, plus the iPhone app where a row applies.
- Update the table with dated numbers, labeled by engine and build.
- File an issue for anything that reads badly on its face (e.g. 150-tab open time growing), per the qa.md rule.

## Non-goals

- Performance work itself. Fixes are their own PRs; this item measures and records.

## Acceptance criteria

- [ ] qa.md §4 carries current, dated baselines for the Chromium DMG and the iPhone app.
- [ ] Every regression found has an issue filed.

## Verification

The updated table and measurement notes (commands, device, build) in the progress log.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
