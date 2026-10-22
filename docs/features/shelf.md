# Feature: Shelf (a home for occasional things)

Surpass-Arc bet (#2 in `docs/PLAN.md`); fixes Arc's "nowhere to put occasional bookmarks/bookmarklets" gap (`docs/RESEARCH.md` section 4).

## Goal

A low-pressure place for links you need rarely but want kept - without pinning them into your daily sidebar.

## Spec

- One Shelf per space plus a global Shelf; toggled from sidebar bottom (`Cmd+B`).
- Add via drag, tab context menu, or command bar ("send to shelf"); stores title + custom name + favicon + note field.
- Bookmarklets welcome: stored and runnable from the Shelf and command bar.
- Fully searchable from the command bar (ranked below open tabs).
- No folders inside the Shelf by design; tags instead (one word each, filterable).

## Acceptance criteria

- [ ] Add/remove/reorder shelf items; per-space and global shelves both work
- [ ] Note and tags editable inline
- [ ] Bookmarklets execute from shelf and command bar
- [ ] Shelf items surface in command-bar search with a Shelf section label
- [ ] Shelf state syncs/exports with the rest of the model

## Implementation notes

- Shelf is `kind: shelf` in the TabItem model - reuse lifecycle/sync plumbing, exclude from archive rules.

## Out of scope

Reading-list features (read-later queues, offline capture) - evaluate after v1.
