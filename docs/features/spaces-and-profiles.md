# Feature: Spaces and profiles

Priority basis: ranked #8 by users; called "a godsend" for account separation in reviews (`docs/RESEARCH.md`).

## Goal

Separate life contexts - work, personal, a project - in one window, each with its own tabs, pins, folders, theme, and logged-in accounts. Switching spaces is instant and physical.

## Spec

- Each space binds to an engine profile/container so cookies and logins never leak across spaces.
- Per-space: name, emoji or icon, gradient theme (`docs/DESIGN.md` presets or custom), independent sidebar contents.
- Switch: horizontal two-finger swipe (trackpad), `Ctrl+1..9` for direct jump, `Ctrl+Tab`-style cycler, or click space indicator (bottom of sidebar).
- Space switcher overview (`Cmd+Shift+Space`): bird's-eye grid of all spaces with live tab thumbnails.
- Tabs never migrate silently between spaces; moving a tab is an explicit drag in overview or a command-bar action.

## Acceptance criteria

- [ ] Create/rename/reorder/delete spaces; deleting offers to move tabs to another space
- [ ] Two Google accounts stay logged in simultaneously in two spaces
- [ ] Per-space gradient recolors window chrome per `docs/DESIGN.md` theming engine
- [ ] Swipe and `Ctrl+N` switching both work; overview shows live thumbnails
- [ ] New tab inherits current space; link routing (`link-routing.md`) can override

## Implementation notes

- Zen base: map spaces to Zen workspaces + Firefox containers (container per space by default; allow sharing one container across spaces for users who want shared logins).
- Space model in `core/spaces`; UI in `chrome/sidebar`.

## Out of scope

Cross-device space sync (sync.md), link routing rules (link-routing.md).
