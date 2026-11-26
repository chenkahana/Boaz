# PLAN-03: Chromium security-update runbook, drilled

Wave: 0 Stability
Status: Ready
Depends on: nothing (PLAN-02's smoke subset makes drills cheaper, but is not required)

## Goal

Turn the 72-hour Chromium security-update target into an exercised, mostly automated operation — before a
zero-day forces the first attempt. This is the gap that killed Arc.

## Why

Chrome ships security fixes roughly weekly. Boaz ships a pinned custom Chromium fork whose update tooling has
never been exercised end to end. Every week of lag is a browser with known exploits in users' hands.

## Scope

- Write the runbook in docs/chromium/: detect upstream security release → bump the pinned revision (Vendor lock
  files) → rebuild → acceptance smoke set → publish DMG → appcast. Name the owner action at every manual step.
- Automate every step CI can own (a workflow that takes an upstream version and produces the signed release
  candidate). What can't be automated must be one documented command each.
- Add a patch-lag policy to SECURITY.md: what lag users can expect and how updates reach them.
- **Drill it once for real** on an actual upstream patch release, timing every step, and record the drill in the
  runbook. The drill is the acceptance criterion, not the document.

## Non-goals

- Rebasing Boaz's patches onto a new major Chromium line beyond what the drill requires; note the cost if it
  blows the 72-hour budget, and escalate to Chen with options.

## Acceptance criteria

- [ ] Runbook committed, with the drill's timings recorded step by step.
- [ ] SECURITY.md states the patch-lag policy.
- [ ] One real upstream patch went from release to published DMG inside 72 hours during the drill.

## Verification

The drill's published DMG and runbook timings; CI workflow run links.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
