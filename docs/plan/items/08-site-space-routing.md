# PLAN-08: Site-to-space routing (Air Traffic Control)

Wave: 2 Simplicity
Status: Ready
Depends on: nothing

## Goal

Rules that send sites to the right space automatically — Arc's Air Traffic Control, the single most-missed Arc
feature: work links always open in the Work space, personal in Personal, no matter where they were clicked.

## Why

Simplicity is the product. Automatic routing removes the daily "wrong space" chore that Arc users reorganize
their whole browser around.

## Scope

- Mac first. Rule model: host or host-prefix → target space, scoped per profile, evaluated on every navigation
  that opens or would open a tab (typed, clicked in-app, clicked from another app via default-browser/Quick
  Window hand-off).
- Rule management UI in space settings: add, reorder, delete; first match wins.
- Conflict handling: explicit user action (drag a tab to another space, "open here instead") always beats a rule.
- Sync rules through the same CloudKit path spaces use; the iPhone ignores rules (must-have #8: no spaces on
  iPhone) but must never break on synced rule data.
- Unit tests for matching/precedence; UI test for a rule firing on an external open.

## Non-goals

- iPhone routing UI. Temporary "open once in this space" prompts. Learning/suggesting rules from behavior.

## Acceptance criteria

- [ ] A link clicked in Mail opens in the ruled space, in the same window (must-have #2 holds).
- [ ] User override beats rules and is remembered for that tab.
- [ ] Rules sync between two Macs on the test account.
- [ ] Tests as scoped; iPhone regression-checked on synced data.

## Verification

UI test run links plus screen recordings of the external-open and override flows.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
