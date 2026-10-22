# Feature: Peek (link previews)

Priority basis: called out by reviewers as a top tab-reducer (`docs/RESEARCH.md` section 2).

## Goal

Read a link without committing to a tab. From pinned and favorite tabs, clicking a link that would open a new tab opens a floating preview instead; decide in one glance whether it deserves a tab.

## Spec

- Trigger: link clicked from a pinned/favorite tab whose target would open a new tab, or `Cmd`-click any link.
- Overlay: centered, 60% window width / 75% height, `radius.card`, drop shadow over a dimmed page scrim.
- Actions in overlay header: open as full tab (`Cmd+O` / button), close (`Esc` / click scrim), copy link.
- Peek never navigates the underlying tab; links inside Peek open inside Peek.
- One Peek at a time; opening another replaces it.

## Acceptance criteria

- [ ] Clicking an external link from a pinned tab opens Peek, not a tab
- [ ] `Esc` and scrim click both dismiss without creating a tab
- [ ] "Open as tab" promotes the preview into the current space's today section
- [ ] In-Peek navigation stays inside Peek
- [ ] Peek is fully usable keyboard-only

## Implementation notes

- On Zen/Firefox base: implement as a dedicated lightweight content browser element layered over the current one, sharing no navigation state.
- Respect sites that refuse framing (X-Frame-Options): detect and auto-fallback to a normal tab with a one-line notice.

## Out of scope

Peek from external apps (that's Little-Arc-style quick window; consider in Phase 4).
