# Feature: Split view

Priority basis: highlighted in reviews; the saved-split trick is a standout (`docs/RESEARCH.md`).

## Goal

Tile 2-4 tabs in one window, and treat the arrangement itself as a first-class, saveable tab.

## Spec

- `Cmd+Alt+Right` splits current tab with the next today tab; drag a sidebar tab onto the page edge to split there.
- Up to 4 tiles (2x2 grid); 8px gaps, each tile `radius.card`.
- A split group is a TabItem with `splitGroupId`: it appears as one sidebar entry, can be renamed, pinned, moved to a folder, and restored later.
- Resizing: drag dividers; layout persists with the group.
- Unsplit: drag a tile out to the sidebar or `Cmd+Alt+U`.

## Acceptance criteria

- [ ] 2, 3, and 4-tile arrangements render per design tokens
- [ ] Split group appears as one renamable sidebar tab; reopening restores layout
- [ ] Pin a split group; it survives restart
- [ ] Divider drags resize tiles and persist
- [ ] Unsplit returns tiles to today tabs without losing scroll/playback state

## Implementation notes

- Zen already has a split view - reskin to our tokens, then add the group-as-tab persistence layer in `core/` if Zen lacks it.
- Media continues playing across split/unsplit (no reload) - test with video.

## Out of scope

Splits spanning spaces (v1 keeps tiles within one space).
