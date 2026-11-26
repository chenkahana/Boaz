# PLAN-01: Green, trustworthy Mac UI tests

Wave: 0 Stability
Status: Ready
Depends on: nothing

## Goal

The Mac UI tests check is green on master and stays trustworthy: no silently quarantined flakes, no red master
treated as normal.

## Why

The check is red on master today (pre-existing; seen 2026-11-25 on a docs-only PR). A red check everyone ignores
hides real regressions — the exact failure mode the stability pillar exists to prevent.

## Scope

- Download the failing `xcresult` from the latest master CI run, identify every failing test, and fix the cause
  (product bug or test bug), starting with the known-flaky `ScreenTests.testToast`.
- If a flake's root cause can't be fixed, quarantine it only with a GitHub issue filed per test and a comment in
  the test naming the issue. Never skip a test silently.
- Add a short "UI test health" note to docs/qa.md §5: how to read the CI failure bundle.

## Non-goals

- New feature tests. Expanding coverage is welcome only where a fixed bug needs a regression test.

## Acceptance criteria

- [ ] Three consecutive green Mac UI test runs on master (links in the progress log).
- [ ] Every quarantined test has an open issue and an in-code pointer to it.
- [ ] docs/qa.md §5 documents reading CI failure bundles.

## Verification

GitHub Actions run links on master. CI is the source of truth; the runner Macs are the environment that matters.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
