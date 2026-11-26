# PLAN-13: App Store submission pipeline

Wave: 3 Operations
Status: Needs Chen — App Store Connect access (Xcode Cloud check or Apple ID via the secret store + one OTP)
Depends on: Chen unblocks access. Standing since 2026-11-22.

## Goal

Get the pending iOS update submitted, then make every future submission routine instead of a per-release
negotiation.

## Why

The iOS app is the shipped product; updates have been waiting on access since Nov 22 while the DMG auto-ships.
This is the recurring version of a problem that should exist once.

## Scope

1. **Unblock**: either Chen confirms/creates the Xcode Cloud workflow (archive Boaz-iOS and Boaz-macOS on
   master, TestFlight post-action — docs/app-store.md describes it) or saves his Apple ID in the secret store
   so Instinct runs submissions in the browser (one OTP at sign-in).
2. **Submit the current update**: What's New text drafted from the CHANGELOG (Instinct writes it; Chen approves
   the words once, then standing drafts from CHANGELOG).
3. **Make it routine**: docs/app-store.md updated so a submission is a checklist, including the version-bump
   decision (MARKETING_VERSION vs the DMG's 0.4.x line — record which scheme the App Store uses and why).

## Non-goals

- App Store marketing assets, screenshots refresh, pricing. Separate asks if Chen wants them.

## Acceptance criteria

- [ ] Current iOS update submitted for review (state screenshot in log).
- [ ] docs/app-store.md's checklist reflects the path that actually worked.

## Verification

App Store Connect state links/screenshots in the item log.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
