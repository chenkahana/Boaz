# Feature: Site customization (Boosts-style)

Priority basis: Arc power feature with a smaller audience (`docs/RESEARCH.md` section 2). Scheduled post-parity; not in the Phase 1-3 critical path.

## Goal

Let users restyle any site without code - colors, fonts, hide annoyances - and let power users drop to CSS.

## Spec

- Per-site overrides: background/text/accent colors, font family/size, element hiding via point-and-click picker.
- Advanced mode: raw CSS editor with live preview, per-site toggle.
- Overrides are per-profile, sync via sync.md, exportable/importable as JSON.
- Safety: overrides never run on payment/auth pages of major providers by default (maintained blocklist), with user override.

## Acceptance criteria

- [ ] No-code color/font changes apply per site and persist
- [ ] Element picker hides a chosen element reliably
- [ ] Raw CSS mode with live preview and disable toggle
- [ ] Overrides export/import and sync
- [ ] Blocklist prevents styling on listed payment/auth pages

## Out of scope

A community gallery for sharing styles (post-v1; needs moderation policy).
