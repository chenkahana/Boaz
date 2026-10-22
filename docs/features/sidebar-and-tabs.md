# Feature: Sidebar, tabs, folders, rename

Priority basis: ranked #1 (folders), #2 (rename), #4 (sidebar) by users in `docs/RESEARCH.md` section 2.

## Goal

The sidebar is the only place tabs live. It merges tabs and bookmarks into one organized list in three sections, stays clean by default, and makes any page findable in under two seconds.

## Sections (top to bottom)

1. **Favorites** - icon-only grid (max 8, wrap to 2 rows), dock-like. Hover shows preview/unread where the site supports it (see `media-and-pip.md` note on previews).
2. **Pinned** - named tabs with full titles, organized into folders. Persists forever.
3. **Today** - everything unpinned, newest first, subject to lifecycle rules (`tab-lifecycle.md`).

A thin rule (`1px glass.bg`) separates pinned from today. Dragging a tab across the rule pins/unpins it.

## Folders

- Unlimited nesting (render indent 12px/level, cap visual indent at level 6).
- Folders can contain pinned tabs and other folders; today tabs must be pinned before filing (drag does this implicitly).
- Collapse state persists per folder.
- Closing a folder offers: close all contained tabs / keep.

## Rename

- Double-click (or `Cmd+E` with tab focused) edits the tab's display name inline.
- Custom name wins everywhere: sidebar, command bar, window title, split view.
- Original page title preserved: tooltip on hover, shown in archive list, searchable in command bar.

## Behavior rules

- Single-tab dedupe: opening an already-open URL triggers duplicate interception (`duplicate-interception.md`).
- Middle-click a sidebar item opens a copy (explicit escape hatch).
- `Cmd+W` on the last today tab leaves a blank window; never auto-opens a "start page" tab.
- Sidebar width 240-320px draggable; `Cmd+S` hides entirely; left-edge hover reveals as overlay.

## Acceptance criteria

- [ ] Three sections render per `docs/DESIGN.md` anatomy and tokens (radius.tab, fonts, accent wash on active)
- [ ] Create, nest (3+ levels), rename, collapse, drag-reorder folders
- [ ] Rename a tab; custom name appears in sidebar + command bar + window title; original title searchable
- [ ] Drag a today tab above the rule pins it; drag a pin below unpins
- [ ] `Cmd+S` toggles a completely chromeless window; hover-reveal overlay works
- [ ] New window is blank by default
- [ ] Shortcuts remappable (settings lists every shortcut)

## Implementation notes

- On the Zen base: replace Zen's tab-list rendering with our own; Zen's container/workspaces plumbing stays underneath.
- Sidebar state lives in `core/` TabItem/Folder model (`docs/ARCHITECTURE.md` data model), rendered by `chrome/sidebar`.

## Out of scope

Tab search ranking (command-bar.md), archive UI (tab-lifecycle.md), previews (media-and-pip.md).
