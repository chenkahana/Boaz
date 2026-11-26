# PLAN-12: Crash feedback loop without telemetry

Wave: 3 Operations
Status: Ready
Depends on: nothing

## Goal

Crashes reach the maintainer fast, with symbols, without adding any analytics or telemetry SDK. The privacy
stance stays absolute; the feedback loop stops depending on luck.

## Why

Mac crash review today is manual on one build Mac, and most users never report anything. Apple's own
opt-in crash sharing already delivers App Store builds' crashes to App Store Connect — the loop just isn't
wired into the release routine.

## Scope

- Release checklist (docs/release.md / docs/app-store.md): review App Store Connect / Xcode Organizer crashes
  for the current build as a named step, with a "no new crash cluster" release gate. (PLAN-13's access work
  makes this runnable; write the step now.)
- A `Tools/symbolicate` script: takes a user-sent `.ips`/crash report plus the matching dSYM and outputs a
  readable trace; documented in SUPPORT.md so users who email a report get a fast answer.
- In-app "Report a problem": Mac Help menu and iPhone Settings row that opens a prefilled GitHub issue or mail
  (build, OS, commit), per docs/qa.md's reporting format. No automatic attachment of logs — the user attaches
  what they choose.

## Non-goals

- Any in-app analytics, crash SDK, or background upload. Ever (must-have #12's spirit).

## Acceptance criteria

- [ ] Crash review is a named, gated step in the release docs.
- [ ] The symbolication script turns a sample `.ips` into a readable trace (evidence in log).
- [ ] "Report a problem" ships in both apps and produces a correctly formatted report.

## Verification

Script output pasted in the item log; screenshots of both menu entries; CI links.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
