# PLAN-06: Two products, one name — clear separation

Wave: 1 Accuracy
Status: Needs Chen — pick the naming/separation option
Depends on: nothing

## Goal

A user (or a reviewer, or a support email) can immediately tell what Boaz is on each platform and what each
build can and cannot do. One name, two engines — App Store builds are WebKit (must-have #10), the GitHub DMG is
Chromium (must-have #1) — must stop being a support trap.

## Why

Chrome, Arc and Dia are one product everywhere. Boaz's capabilities genuinely differ per build (extensions, for
one, behave differently per engine), and today nothing user-facing says so plainly.

## Scope

1. **Decision doc, first PR**: options with a recommendation — e.g. (a) one name, one capabilities page every
   surface links to; (b) a distinct name for the Chromium DMG; (c) converge by retiring a surface. This is
   Chen's call: set Status to Needs Chen and present it.
2. **Execute the pick**: README, docs, App Store description notes, in-app About rows and the DMG download
   page copy all state the same story. Keep [docs/extensions.md](../../extensions.md)'s per-engine matrix as the
   canonical capability table and link it.
3. Honesty check: nothing in any user-facing surface contradicts must-haves #1 and #10 (WebKit stays invisible
   inside the DMG; the App Store builds are WebKit and say so where a user would care).

## Non-goals

- Changing which engine ships where. Those are must-haves.

## Acceptance criteria

- [ ] Chen's picked option recorded in the item log with the date.
- [ ] Every user-facing surface tells the same story; the extensions matrix is linked from each.

## Verification

Screenshots of each changed surface in the finishing PR.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
