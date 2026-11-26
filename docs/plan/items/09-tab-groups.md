# PLAN-09: Tab groups

Wave: 2 Simplicity
Status: Ready
Depends on: nothing

## Goal

Named, collapsible groups of tabs inside a space's sidebar — the last core Arc sidebar construct Boaz lacks.

## Why

Spaces, Favorites, Pinned, Today and folders already exist (must-have #5). Groups are how Arc users organize
working sets inside a space without committing to pins or folders.

## Scope

- Mac sidebar: create a group from selected tabs or an empty group; name, rename, color optional (default off —
  simplicity); collapse/expand; drag tabs in and out; ungroup keeps the tabs.
- Persistence across quit/relaunch, and sync through the same CloudKit mechanism folders use. Decide and record
  in the item log how groups appear on iPhone (default call: as ordinary folders, since folders already sync;
  deviate only with a reason).
- Keyboard and VoiceOver support from day one (docs/design.md accessibility rules apply).

## Non-goals

- Cross-space groups, auto-grouping, tab-group sharing. Folders stay as they are; groups don't replace them.

## Acceptance criteria

- [ ] Create/rename/collapse/drag/ungroup all work and survive relaunch.
- [ ] Groups sync to a second device and degrade gracefully on iPhone.
- [ ] UI tests for the create/collapse/relaunch flow; accessibility labels on every new control.

## Verification

UI test links; sync evidence between two devices on the test account.

## Progress log

- 2026-11-26: Item created (Instinct, from the Nov 25 gap analysis).
