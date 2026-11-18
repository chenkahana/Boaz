# R3. Reference teardown

What the apps to beat do at the five moments that matter (tab open/close, tab overview, address entry, page menu,
sidebar or tab-strip drag), written as mechanics. Apps to beat (§7.1): **Safari on iPhone**, **Arc on the Mac**;
Chrome, Dia and Orion are secondary.

Evidence levels: **observed** = captured in this pass (screenshots, hierarchy dumps, recordings under
`~/tmp/codex/boaz-craft/`); **known** = documented or widely observed behaviour, not captured here, to confirm by
frame-stepping before an implementation PR relies on it. Driving Arc, Chrome, Safari or other browsers on the Mac
would take over Chen's session and touch his browser profiles, so every Mac reference is "known" and the
frame-stepping is **needs Chen session** (QuickTime at 120 Hz, then step frames in QuickTime or `ffmpeg -vf
select`).

## R3.1 Safari on iPhone (observed, iOS 27.1 simulator, same Duo folded screen as Boaz)

Captured with the same harness driving MobileSafari: `shots/ios/safari/s00–s08`, `rec/safari.mov`. Safari on the
Duo's cover screen also puts its controls in the right-hand column, so the two apps compare directly.

| Moment | Safari mechanics | Boaz today | Gap → finding |
|---|---|---|---|
| Rail / toolbar | Every column control is **48 × 48 pt**: Back (top), Bookmarks, then New Tab and Tabs at the bottom; the page menu is a 48 pt glass button at the **bottom-left** of the page, Reload is a small glyph in the address pill. | 34 × 40 tab fan, 46 New Tab, 56 page menu, 60 Search | One size, one rhythm → IB-2, IB-9 |
| Address entry | Field sits at the bottom of the page area above the keyboard with a dismiss (✕) button beside it; top hit row with the site's icon and the completion highlighted inline ("exam**soft — Examsoft**"); suggestions grouped under a header ("Google Suggestions"); first-run explainer once. | Bottom panel field, inline completion, rows without section headers | Group headers ("Search", "Open Tabs", "History") and spoken kind → AX-4, R4 copy |
| Page menu | A **popover menu** (≈250 pt wide, 42 pt rows) anchored to its button, not a sheet; items grouped by dividers: Reader · Translate │ Share · Add to Bookmarks · Add Bookmark to… │ Find on Page · Page Zoom · Notify Me · Hide Distracting Items │ Extensions │ Tab Actions · Privacy & Security · Request Desktop Website. Rows that open a step end in "…". | Half-height bottom sheet, one undivided list, app items at the end | Group with dividers, move app items out → IM-1, IM-2 |
| Tab overview | Opens from the Tabs button into a **grid of cards** (one column on this narrow screen), each card with its own 22 pt **close ✕** and the favicon + title under it; Search tabs, Filter and More in the column; a **Private │ N Tabs** segmented capsule at the bottom switches tab groups; Done is a filled blue ✓. | Deck of one large card, swipe up to archive, no per-card close, no visible Incognito switch | Visible mode switch and per-card close → IB-1, IB-6 |
| Private | A tab group of its own, chosen in the overview; the whole chrome goes dark in Private. | Toggle in the page menu; chrome unchanged | → IB-1 |

Steal this (Safari, iPhone):
1. **One control size (48 pt) for every rail and bar button**, and the page menu as a separate corner button. → IB-2, IB-9, W2.
2. **Page menu as a grouped popover with dividers**, page items first, tab and site items after, nothing app-level. → IM-1, IM-2, W6.
3. **Private as a visible tab group in the overview**, with dark chrome while in it. → IB-1, W6 (needs Chen's yes: visible behaviour change).
4. **Per-card close in the overview** next to the swipe gesture. → IB-6, W6.
5. **Suggestion section headers** ("Google Suggestions") so sighted and VoiceOver users both know a row's kind. → AX-4, W4.

## R3.2 Safari on the Mac (known; frame-stepping needs Chen session)

| Moment | Safari mechanics | Boaz gap → finding |
|---|---|---|
| Tab close (⌘W) | The tab collapses in place and its neighbours close the gap; Edit › **Undo Close Tab (⌘Z)** and History › Reopen Last Closed Tab both bring it back. | ⌘Z does nothing for tabs (E9, no `UndoManager`) → W5 |
| Tab overview (⇧⌘\\) | The page **zooms down into its card** in a grid and back up when picked: the signature "it came from there" move. | Mac has no overview; sidebar is the overview (fine for Arc's model) |
| Address entry (⌘L) | Edits **in place** in the toolbar field; suggestions drop beneath it; Top Hit first; Esc restores the URL. | Command bar opens centred, not from the pill → MC-3 |
| Page loading | Progress fills the address field's background; nothing draws over the page. | DMG spinner over the page → MW-1 |
| Find | Safari's own find banner (Done, ‹ ›, match count), no Replace. | WebKit build shows AppKit's finder with Replace → MW-9 |
| Window titles | Each window is titled after its current page in Window menu and Mission Control. | DMG windows all "Boaz" → MS-13 |

Steal this: **⌘Z reopens the last closed tab** (Safari's Undo Close Tab) on top of ⌘⇧T; **progress in the field, never
over the page**; **window titled after its page**.

## R3.3 Arc (Mac app to beat; known, frame-stepping needs Chen session)

| Moment | Arc mechanics | Boaz today | Gap → finding |
|---|---|---|---|
| Space switch (two-finger swipe on the sidebar) | Interactive paging: the current space's list follows the fingers 1:1 and the next space slides in beside it; release commits by distance **or** flick speed and settles with the finger's velocity. | The list moves at 0.4× up to ±90 pt, then snaps back; past 70 pt of travel (distance only, no velocity) the space changes with a separate push transition; no haptic. `Sidebar.swift:82-87` | New **MS-15** below; W1 |
| Command bar (⌘T / ⌘L) | Centred floating bar over a dimmed window, field focused on the first frame, results grouped (tabs, history, search). | Same layout; focus by polling with type-ahead replay (MC-2); hover steals selection (MC-1) | MC-1, MC-2 |
| Tab close / archive | Row collapses with a spring, neighbours close up; ⌘Z (and ⌘⇧T) brings it back. | Row removal animates with model springs; Undo via toast and ⌘⇧T only | E9 → W5; AX-12 for Reduce Motion |
| Sidebar drag (reorder, into folder) | Live row preview under the pointer, gap opens where it will land, folders spring open on hover. | Insertion line, no gap; folders open only on drop | MS-11 |
| Sidebar width | Edge drag with resize cursor; hide/show (⌘S) slides; hover the left edge to peek. | Same, hard stop at 200/420 pt | MS-5 |
| Split view | Drag a tab onto the page: drop zones highlight left/right; divider drag between panes. | Menu command or context menu; divider invisible until hovered | MW-7, MS-12 |
| Page loading | Indicator in the sidebar's URL pill / favicon; nothing over the page. | DMG spinner over the page | MW-1 |
| Peek / Little Arc | Links from pinned tabs open in a floating preview over the page with Expand and Close. | Peek overlay exists (`BrowserWindow.swift:496`) | parity |

New finding from the comparison:

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| MS-15 | P1 | The two-finger space swipe isn't interactive: the list slides at 0.4× up to 90 pt and snaps back, then a separate push transition plays if the drag passed 70 pt. A flick that's fast but short does nothing; nothing carries the fingers' speed; no haptic at the commit. | `Sidebar.swift:82-87` | S2 | daily | M | 4.5 | 2, 5 |

Steal this (Arc): **interactive space paging with velocity** (MS-15), **gap-opening reorder with spring-loaded
folders** (MS-11), **drag a tab onto the page for split view** (MW-7), **⌘Z restores the last closed tab** (W5).

