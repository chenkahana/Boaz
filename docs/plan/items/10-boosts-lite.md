# PLAN-10: Boosts-lite: per-site customization

Wave: 2 Simplicity
Status: Ready
Depends on: nothing

## Goal

The smallest lovable slice of Arc Boosts: let a user change how a site looks, saved per site, on the Mac.

## Why

Boosts were Arc's per-site personality. Dia killed them, Arc is gone — a disciplined, minimal version is a
differentiator Boaz can own, as long as it stays simple.

## Scope (the "lite" is the point)

- Per-site custom CSS with a plain editor (monospace field, live preview on the current page), saved per host,
  applied on load, listed in one settings screen where each can be edited or deleted.
- Three bundled one-tap presets: dark-ify, hide-cookie-banners (best effort), bigger-text. Presets are just
  pre-filled CSS the user can then edit — no magic, no updates channel.
- Everything local. No gallery, no sharing, no account (must-have #12's spirit applies to features too).

## Non-goals

- JavaScript injection, a Boosts gallery/store, sync (revisit only if users ask), iPhone.

## Acceptance criteria

- [ ] CSS saved for a site applies on every load, edits apply live, delete removes cleanly.
- [ ] The three presets work on a representative site each (evidence screenshots).
- [ ] A broken stylesheet can't break the browser chrome — injection is page-scoped, errors contained.
- [ ] UI test for save/apply/delete.

## Verification

Screenshots before/after per preset; UI test links.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
