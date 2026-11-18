# R2. Pillar audit

Every surface from R1 walked through the twelve pillars (P1–P12, `PLAN.md` §2). Code at 66c3d63; runtime evidence
from R0 (`~/tmp/codex/boaz-craft/`, paths relative to it). A finding without runtime evidence says so ("code-read")
and is marked for confirmation in the real app before its PR.

**Scoring** (`PLAN.md` §5). Severity S1 broken or inaccessible = 4, S2 visibly unpolished in a main flow = 3, S3
noticed by a careful user = 2, S4 nit = 1. Reach every session = 4, daily = 3, occasional = 2, rare = 1. Effort S = 1,
M = 2, L = 3. **Score = severity × reach ÷ effort** (max 16). "MH" is the must-have a fix touches (number from
`docs/must-haves.md`), "—" for none.

IDs: MS Mac sidebar, MC command bar, MW web pane and split, ML library panel, ST settings, OB onboarding, IB iPhone
bar/fan/carousel, IS search panel, IM page menu, DU Duo, WX widgets and extensions, AX accessibility passes.

## R2.1 Mac sidebar

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| MS-1 | P9 | Dragging a tab, pinned tab or favorite out of Boaz drops the text `boaz-item:<uuid>`, not the page's URL: into Notes, Mail, Finder or another browser you get an internal id. | `Sidebar.swift:7-9` (payload), `:300`, `:584` (`.draggable(SidebarDrag.payload(…))`); code-read, confirm by dragging a row into TextEdit | S2 | occasional | S | 6 | — |
| MS-2 | P8, P12 | Sidebar rows, favorites and space dots can't take keyboard focus. They're tap gestures with a button trait (`sidebarPress`), so Tab / Full Keyboard Access skips them and there's no arrow-key navigation through the list. VoiceOver can press them (default action), so this is narrower than the 2026-11-09 P0-3. | `Sidebar.swift:879-889`; no `focusable`/`FocusState` in the file | S2 | daily | M | 4.5 | 5 |
| MS-3 | P12 | No VoiceOver custom actions on rows: Pin, Archive/Close, Move to Folder, Rename are reachable only through the context menu (VO-Shift-M), not the rotor's Actions. | `Sidebar.swift:889` (only `.default`) | S3 | occasional | S | 4 | — |
| MS-4 | P2 | No trackpad haptics anywhere on the Mac: not at the sidebar's width limits, not when a drag crosses into a folder or a reorder slot, not when a favorite drops. | `rg NSHapticFeedbackManager Apps/macOS` → 0 | S3 | daily | S | 6 | — |
| MS-5 | P1 | The sidebar's width stops dead at 200 and 420 pt (no rubber band, no snap); the split divider does the same at 20% / 80%. | `BrowserWindow.swift:332`, `:489` | S4 | occasional | S | 2 | — |
| MS-6 | P1 | Three curves outside the one-curve rule in `docs/design.md`: the peek opens with `.spring(0.32, 0.85)` and closes with `.spring(0.32, 0.9)`; favorite tiles hover with `.easeOut(0.12)`; the start page hover `.spring(0.3, 0.7)` (bouncy for a hover). | `BrowserWindow.swift:299,310`, `Sidebar.swift:180`, `BrowserWindow.swift:455` | S3 | every session | S | 8 | — |
| MS-7 | P4 | Glyphs in the sidebar have fixed point sizes (8–12 pt) that ignore Settings › Sidebar text size (14/15/17): at 17 pt the plus, lock, link and ellipsis glyphs look undersized next to the text. | `Sidebar.swift:163,195,203,383,467,621,804` | S3 | daily | S | 6 | — |
| MS-8 | P6 | A space with no tabs (and a fresh library) shows an empty sidebar: no New Tab row, no hint; only the bottom bar's icons. | `shots/mac/empty-light-*.png` | S3 | rare | S | 2 | 5 |
| MS-9 | P3 | At the minimum window size the Today list is cut off below New Tab with no fade or scroll cue (overlay scrollbars are hidden at rest). | `shots/mac/min-light-*.png` (720 × 492; "Today Tab" not visible) | S4 | occasional | S | 2 | — |
| MS-10 | P3 | The content card's corner (12 pt, `MacRadius.card`) at a 6 pt inset reads as rounder than the window corner beside it; concentric would be window radius − 6. Measure on a 2× display before changing. | `shots/mac/corners.png` (crop of `mac-light-main.png`), `MacRadius.swift` | S4 | every session | S | 4 | — |
| MS-11 | P9 | Hovering a dragged tab over a collapsed folder doesn't spring it open; the folder only expands on drop. | `Sidebar.swift:588-592` | S4 | occasional | S | 2 | 5 |
| MS-12 | P2 | The split divider is invisible until hovered (`opacity 0`), so a split has no visible handle. | `BrowserWindow.swift:478` | S3 | occasional | S | 4 | — |

Holds up well: one selection fill and hover fill from tokens, Increase Contrast doubles the selection (`Sidebar.swift:28`),
Reduce Motion turns the space push into a fade (`Sidebar.swift:64`) and freezes hover lifts (`:292`), every icon button
has a tooltip with its shortcut (`keys.hint`), resize and split handles show resize cursors (`BrowserWindow.swift:328,483`),
rows act on mouse-down like Arc and Chrome (`:881`), middle-click closes.
