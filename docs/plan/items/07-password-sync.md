# PLAN-07: Passwords sync across devices + iOS AutoFill

Wave: 1 Accuracy
Status: Ready
Depends on: nothing. **Chen decides** the storage design if it changes the privacy story (spike → Needs Chen
with recommendation → continue after his pick).

## Goal

A password saved on one device fills on the user's other devices, and on iPhone Boaz's passwords are available
system-wide through the AutoFill credential provider. Today passwords sit in the local Keychain only — a gap
every Chrome/Arc/Dia user switching over will feel on day one.

## Why

Accuracy includes "my data is where I am." Must-have #13 (the library is never lost) and the privacy must-haves
bound the design: no Boaz server, no third-party sync.

## Scope

1. **Spike first, one PR**: iCloud Keychain adoption vs CloudKit private-database sync of Boaz's own store.
   Data-classes, conflict behavior, what happens on sign-out, how the Chromium DMG's password store joins.
   Recommend one; Chen picks.
2. **Implement** the pick with a migration that keeps every existing local entry readable (must-have #13).
3. **iOS AutoFill Credential Provider extension** so Boaz passwords fill in other apps and Safari.
4. Extend docs/qa.md's sync checklist with password rows; docs/privacy.md states the design plainly.

## Non-goals

- History sync (must-have #11 forbids). Passkeys (vendor-waiting; see the plan README).

## Acceptance criteria

- [ ] Save on one device, fill on another, on Release builds against production CloudKit (evidence in log).
- [ ] Upgrade from the previous build loses nothing (migration test plus a clean-machine run).
- [ ] AutoFill extension lists and fills Boaz passwords on iPhone.
- [ ] qa.md and docs/privacy.md updated.

## Verification

Two-device evidence (screen recording or timestamped screenshots), migration test CI links.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
