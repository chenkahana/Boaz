# PLAN-11: TestFlight beta ring

Wave: 3 Operations
Status: Needs Chen — App Store Connect access (same blocker as PLAN-13)
Depends on: PLAN-13's access unblock

## Goal

A small external TestFlight ring (~25 people) as the standing feedback loop Boaz doesn't have: real devices,
real usage, real bug reports before App Store releases.

## Why

Boaz has no telemetry by design, so the only feedback loop is Chen plus whoever emails. Arc and Dia ran beta
communities; a quiet ring of 25 is the craft-product version.

## Scope, once access lands

- External TestFlight group with a public invite link Chen shares where he likes.
- Cadence rule: every App Store-bound build flies beta first, minimum 3 days, unless it's a crash hotfix.
- Feedback channel: a dedicated email alias or GitHub issue template for beta reports, linked from the beta
  notes; docs/qa.md's Reporting section is the bar reports are triaged against.
- Beta notes template pulled from CHANGELOG entries.

## Non-goals

- Recruiting itself (Chen shares the link), analytics of any kind.

## Acceptance criteria

- [ ] External group live with at least the first build distributed.
- [ ] Cadence and feedback path written into docs/app-store.md.

## Verification

App Store Connect screenshots/links in the item log.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
