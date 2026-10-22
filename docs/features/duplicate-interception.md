# Feature: Duplicate interception

Surpass-Arc bet #1 (`docs/PLAN.md`). Arc users kept opening the same Gmail five times; reviewers flagged it and Arc never fixed it.

## Goal

The browser never holds two tabs on the same URL unless you explicitly ask it to.

## Spec

- Any navigation to a URL that is already open anywhere (any space, any folder, archive excluded) focuses the existing tab instead, switches space if needed, and flashes a "Already open" pill naming its space and folder.
- Normalization: strip tracking params (utm_*, fbclid, gclid), trailing slash, default ports; fragment kept by default (headings differ), with per-site override.
- Explicit override: middle-click sidebar item, `Alt+Enter` in command bar, or "Open anyway" on the pill creates a real second tab.
- Per-site opt-out from the pill or settings (e.g. apps where two documents share a URL pattern).

## Acceptance criteria

- [ ] Cmd-clicking a link to an open URL focuses the existing tab + flashes pill with space/folder
- [ ] Tracking-param variants of an open URL dedupe
- [ ] "Open anyway" and middle-click both create genuine duplicates
- [ ] Per-site opt-out persists
- [ ] Cross-space focus switch lands on the right tab (regression-test with 3+ spaces)

## Implementation notes

- Runs in `core/dupes` as a navigation observer; normalization table in one file with tests.
- Pill UI: `radius.pill`, `motion.fast` in/out, top-center of page, auto-dismiss 2.5s.

## Out of scope

Merging near-duplicate pages (different URLs, same content) - research problem, not v1.
