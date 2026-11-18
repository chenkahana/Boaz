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

## R2.2 Mac command bar (⌘T, ⌘L)

Runtime: needs Chen session (a background app gets no keystrokes). All findings code-read.

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| MC-1 | P2 | Hovering a suggestion selects it (`onHover { selection = index }`), so a pointer that happens to rest where the list opens steals the selection from the top hit as rows appear and Return opens the hovered row. Spotlight, Safari and Arc move the selection only when the pointer actually moves. | `CommandBar.swift:96` | S2 | daily | S | 9 | — |
| MC-2 | P11 | Focus is reached by polling: up to 10 × 50 ms of toggling `focused` / `makeFirstResponder` until the field editor owns the keyboard; keys typed meanwhile are held and replayed (`beginTypeAhead`). It works as a safety net, but the field can be up to 0.5 s late, and the replay is what makes the first keystroke land. Measure on the DMG: ⌘T then type immediately, 20×, record at 120 Hz. | `CommandBar.swift:126-160` | S3 | every session | M | 4 | 1 |
| MC-3 | P1 | Opens with `.scale(0.96, anchor: .top) + opacity` from a fixed 110 pt top inset for both ⌘T and ⌘L. ⌘L edits the address shown in the sidebar's top pill but doesn't grow from it, so the eye has to jump. Judgment against Arc (which does the same) and Safari (edits in place). | `BrowserWindow.swift:63`, `CommandBar.swift:111` | S4 | every session | M | 2 | — |
| MC-4 | P5 | The DMG draws the bar on a 92% opaque background because glass can't sample Chromium's layer, while the WebKit build shows glass: the two builds' command bars look different. Fine as a fallback, but it's also what Reduce Transparency should show on both. | `CommandBar.swift:103-106` | S4 | every session | S | 4 | 1 |
| MC-5 | P4 | Fixed sizes (field 19 pt, icon 17 pt, rows 14 pt) that don't follow Settings › Sidebar text size, which is the only text-size control the Mac app offers. | `CommandBar.swift:55,68,342` | S4 | daily | S | 3 | — |
| MC-6 | P7 | Row captions are "Search", "Switch to Tab", or a bare host; a history row and a typed address both show a host with no distinction beyond the icon. Judgment: Safari labels history rows "History" — cheap clarity. | `CommandBar.swift:321-340` | S4 | daily | S | 3 | — |

Holds up well: ↑/↓/Esc/Return all handled; history lookup debounced 100 ms off the main thread; ⌘L selects the
address so typing replaces it; a bar closing while the next one opens hands the held keys to the new one.

## R2.3 Mac web pane and split view

Runtime: needs Chen session for the DMG; WebKit build captured static only. Findings code-read unless noted.

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| MW-1 | P6 | On the DMG every navigation puts a spinning `ProgressView` over the top centre of the page, immediately, with no ~300 ms grace. Safari and Arc show progress in the chrome (address field fill, a thin bar) and never draw over the page. | `WebPane.swift:129` (Chromium tab pane only; the WebKit pane has no page overlay, only the Stop/Reload glyph swap in the sidebar, `Sidebar.swift:117`); confirm with a recording | S2 | every session | S | 12 | 1 |
| MW-2 | P7 | Restoring a tab shows its snapshot with a "Saved preview" caption in the corner until the live page appears. The caption names an implementation detail; Arc and Safari show the snapshot unlabeled. | `WebPane.swift:110-118` | S3 | daily | S | 6 | 13 |
| MW-3 | P7 | Five titles for a page that didn't load: "Can't Open This Page" (DMG tab pane, WebKit pane, iPhone), "Couldn't Open This Page" (DMG video fallback), "Couldn't Load This Page" (DMG load failure), "You're Offline", "This Page Stopped Responding". The last two are good distinct states; the first three should be one. | `WebPane.swift:36,100,387`, `ChromiumLoadFailureView.swift:17-18`, `TabBrowser.swift:198` | S3 | occasional | S | 4 | — |
| MW-4 | P6 | "Opening page…" (a centred spinner with text) replaces the pane while a tab's engine page is created, so switching to an unloaded tab flashes a spinner instead of the tab's snapshot. | `WebPane.swift:38,132` | S3 | daily | S | 6 | 1 |
| MW-5 | P6 | Load failure copy differs per build: the DMG distinguishes offline, unknown host and crash with matching symbols; the WebKit Mac build and the iPhone show one generic error for all of them (iPhone: "This website couldn't be found…" even when offline). | `ChromiumLoadFailureView.swift:17-30` vs `TabBrowser.swift:413`, `WebPane.swift:387`; `shots/ios/main/11-error-page.png` | S3 | occasional | M | 2 | 10 |
| MW-6 | P7 | Find bar tooltips and labels use sentence case ("Previous match", "Close find bar", placeholder "Find in page") while every other Mac tooltip is title case ("Toggle Sidebar", "Back to Pinned Page"). | `ChromiumFindBar.swift:17,28-36`, `Sidebar.swift:104,540` | S4 | daily | S | 3 | — |
| MW-7 | P1, P2 | Split view: no snap to 50% (or to the halves people use), no double-click on the divider to even the panes, no haptic; the pane header's Separate and Close buttons appear only on hover; separating uses a one-off `.spring(0.4, 0.85)`. | `BrowserWindow.swift:470-494`, `WebPane.swift:76-80` | S3 | occasional | S | 4 | — |
| MW-8 | P6 | Split pane header shows the title in `.caption` with a 6% tint for the focused pane and 2% for the other: the focus cue is faint (judgment; check against Arc's focused-pane outline). | `WebPane.swift:72-85` | S4 | occasional | S | 2 | — |

Holds up well: the DMG's failure view separates offline (wifi.slash, "Check your internet connection"), unknown host
and crash ("Reload Page"), keeps the address, and re-tries a recovered offline navigation once by itself.

## R2.4 Mac library panel, Archive and History windows

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| ML-1 | P4 | The panel's tab labels are 9 pt with `minimumScaleFactor(0.8)`, so "Archived Tabs" can render at ~7 pt: below the 10–11 pt floor Mac apps use for labels, and unreadable for many. | `LibraryPanel.swift:76` | S3 | daily | S | 6 | — |
| ML-2 | P3 | Fixed 630 pt tall popover: at the 492 pt minimum window height it can't fit beside the sidebar (AppKit shifts or clips it). | `LibraryPanel.swift:56`; confirm at 720 × 492 | S3 | occasional | S | 4 | — |
| ML-3 | P7 | Same list, four names and three empty-state voices: "Archived Tabs" (panel tab), "Archive" (View menu, Window menu, window title), "Archive is empty · Closed and auto-archived tabs appear here." (Mac) vs "Archive is empty · Closed and inactive tabs land here." (iPhone), next to "No History", "No Downloads", "No Media" (title case, "No X" pattern). Search prompts: "Search Archive…" (panel) vs "Search archive" (window) vs "Search history". | `LibraryPanel.swift:16,174,363,469`, `LibraryViews.swift:68,120,182,186`, `LibrarySheet.swift:59` | S3 | daily | S | 6 | — |
| ML-4 | P3 | Literal radii (10, 8) in the panel duplicate `MacRadius.tile`/`.row` instead of using them; `AppIconSettings` uses 22 and onboarding 20, outside the token set. | `LibraryPanel.swift:96,147`, `AppIconSettings.swift:102`, `OnboardingView.swift:246,510` | S4 | daily | S | 3 | — |
| ML-5 | P8 | The panel's tab column has no keyboard path between tabs (no ⌘1–⌘4, no arrow keys); Esc closes it (`onExitCommand`). | `LibraryPanel.swift:60,68-90` | S4 | occasional | S | 2 | — |
| ML-6 | P6 | Clearing the Archive or History confirms with "This can't be undone." and no Undo; that's the right pattern for a bulk wipe. Archiving one tab offers Undo (toast). Consistent with P6. | `LibraryViews.swift:124-130,190-195` | — | — | — | — | 13 |

Holds up well: the tab column tiles take the whole 44 × 44 tile as the click target and expose selection to
VoiceOver; downloads show live progress and an interrupted state (DMG); Esc closes; the panel takes the space's theme.

## R2.5 Settings (Mac and iPhone)

Runtime: iPhone `shots/ios/main/14-16-settings*.png` (Light), `main-dark/14` (Dark). Mac code-read (the Settings
window needs a key window).

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| ST-1 | P7 | Labels mix title case and sentence case in the same list: "Archive Inactive Tabs After", "Search Engine Suggestions", "Tint chrome with site colors", "Block ads and trackers", "Search engine"; section headers "Default Browser", "Apple Intelligence", "iCloud Sync" next to "App icon". Across platforms: "Sync Folder" (iPhone) vs "Sync folder" (Mac), "Default Browser" vs "Default browser". | `LibrarySheet.swift` (iPhone settings), `LibraryViews.swift:294-540`; `shots/ios/main/14,15,16` | S3 | occasional | S | 4 | — |
| ST-2 | P7 | "Archive Inactive Tabs After" shows "After 7 days" as its value: "After" twice. | `shots/ios/main/14-settings.png` | S4 | occasional | S | 2 | — |
| ST-3 | P7 | iCloud row: "Sign in to iCloud in Settings to sync." directly above a "Sign In to iCloud" button; the message repeats the button. | `shots/ios/main/15-settings-2.png` | S4 | occasional | S | 2 | 11 |
| ST-4 | P3 | iPhone Settings on the Duo cover screen: the sheet's close button sits outside the sheet, in the rail column, as a floating glass circle; the sheet's own title "Settings" is a small inline title rather than a navigation title. Judgment; needs device check on a standard iPhone. | `shots/ios/main/14-settings.png` | S3 | occasional | M | 2 | 9 |
| ST-5 | P6 | Sync section has no error or "last synced" state on either platform: Sync Now and a sign-in prompt, but no feedback when a sync fails or when it last succeeded. | `LibraryViews.swift:459-497`, `LibrarySheet.swift` iCloud section | S3 | occasional | M | 2 | 11 |
| ST-6 | P2 | Mac Settings is eight toolbar panes (General, App Icon, Privacy, Sync, Passwords, Accounts, Sites, Shortcuts); fine for the DMG's AppKit window, but the WebKit build uses SwiftUI `TabView` tabs, so the two Settings windows differ in chrome and resize behaviour. | `ChromiumSettingsWindow.swift`, `LibraryViews.swift:255-262` | S4 | occasional | M | 1 | 10 |

Holds up well: every iPhone toggle has an explanation footer in plain words ("Runs on your iPhone with Apple
Intelligence; nothing is sent to a server."), the default-browser row switches to a confirmation once set, Reset
keyboard shortcuts confirms.

## R2.6 Onboarding (Mac and iPhone)

Runtime: iPhone `shots/ios/main/01-02`, `main-dark/01`, audits `01-onboarding-1.audit.txt`, `02-onboarding-2.audit.txt`.
Mac code-read (needs Chen session; `make uitest` with `-BoazResetOnboarding YES` covers it).

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| OB-1 | P12 | The iCloud status icon has no label, so VoiceOver reads the SF Symbol's name: "Not Uploaded To Icloud" for `icloud.slash`. | `shots/ios/main/01-onboarding-1.txt` (Image label), `ICloudSignIn.swift:85` | S2 | rare | S | 3 | 11 |
| OB-2 | P5 | System audit flags contrast on every onboarding control: "Sign In to iCloud", "Continue Without Syncing", "Start Browsing" (white on the light end of the brand gradient) and the secondary text in the iCloud card. | `main/01-onboarding-1.audit.txt`, `02-onboarding-2.audit.txt` | S2 | rare | S | 3 | — |
| OB-3 | P4 | "Sign In to iCloud" is flagged as clipping at larger Dynamic Type sizes. | `01-onboarding-1.audit.txt` ("Text clipped") | S3 | rare | S | 2 | — |
| OB-4 | P9 | Pages change only with the buttons; a swipe between them does nothing, though the page dots invite one (iPhone). | `iOS/Onboarding/OnboardingView.swift` (no gesture), `Onboarding.swift:71-86` | S4 | rare | S | 1 | — |
| OB-5 | P6 | With no iCloud account the first page leads with "Not signed in to iCloud · In Settings, tap Apple Account…", a dead end that sends people out of the app before they've browsed once; the primary button is still "Sign In to iCloud". Judgment: lead with Start Browsing, offer sync as the secondary path. | `shots/ios/main/01-onboarding-1.png` | S3 | rare | S | 2 | 11 |

Holds up well: Reduce Motion turns page slides into a fade (`Onboarding.swift:30-35`), the step dots read "Step 1 of 2",
the iCloud icon animates only while checking and switches with a symbol replace, Mac import progress and "Import
Again" are labelled with the source.

## R2.7 iPhone bar, tab fan and carousel

Runtime: Duo folded (side rail) `shots/ios/main`, `tabs`, `tabs-dark`, `private`; recordings `rec/main*.mov`,
`rec/tabs*.mov`, `rec/private.mov`. The standard-iPhone bottom bar (must-have 7) needs a device: every bar finding
below is from the rail, which shares `HomeBar`/`TabStack`/`RailButton`.

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| IB-1 | P5 | Incognito doesn't look different. The empty page still says "No tab open", the search field still says "Search or enter address", pages, rail and carousel look the same; only the search button's glyph (glasses) and a toast "Incognito on" change. Safari tints the whole chrome dark. | `shots/ios/private/31-34`; `HomeBar.swift:31-32` (the "Private search" placeholder exists only in the bottom-bar variant) | S2 | occasional | M | 3 | 8 |
| IB-2 | P2 | The tab fan's hit area is 34 × 40 pt, under the 44 pt minimum, on the control people use most. | `shots/ios/main/06-page.txt` (Button 'Tabs' {34.0, 40.3}) | S2 | every session | S | 12 | 7 |
| IB-3 | P6, P5 | A tab whose load failed has no snapshot, so its carousel card is a blank white rectangle, in Dark too (a white slab on the dark deck). | `shots/ios/tabs/21-carousel.png`, `tabs-dark/21-carousel.png` | S2 | occasional | S | 6 | — |
| IB-4 | P2 | Swipe-up to archive has no haptic at the commit threshold (−110 pt); the only feedback is the medium impact when the Undo toast appears afterwards. Paging does tick per card (`.selection`). | `TabStack.swift:132,267`, `RootView.swift:63` | S3 | daily | S | 6 | — |
| IB-5 | P1 | The archive flick doesn't carry the finger's speed: on release past the threshold the card leaves on a fixed `.snappy(0.28)`; below it, it returns on a one-off `.spring(0.3, 0.75)`. Paging does hand velocity to its spring (`settle(velocity:)`). | `TabStack.swift:252-274` | S3 | daily | S | 6 | — |
| IB-6 | P9 | No context menu on carousel cards or on the tab fan (Safari: Close, Copy, Share, Move to Tab Group). The only actions are tap and swipe-up. | `TabStack.swift` (no `.contextMenu`) | S3 | daily | M | 3 | — |
| IB-7 | P6 | The "Swipe the toolbar to switch tabs" tip pops over the middle of a page that's still loading, right after the second tab opens. | `shots/ios/main/09-second-page.png` | S3 | rare | S | 2 | — |
| IB-8 | P1 | Reopening a failed tab from the carousel shows a blank page with only a hairline progress glow for 2+ s before the error returns. | `shots/ios/tabs/24-opened.png`, `25-toolbar-swipe.png` | S3 | occasional | S | 4 | — |
| IB-9 | P3 | Rail controls use four sizes on one column: Search 60 pt, Menu 56 pt, New Tab 46 pt, Tabs 34 × 40 pt. | `shots/ios/main/03-empty.txt`, `06-page.txt` | S4 | every session | S | 4 | 9 |
| IB-10 | P2 | The page menu (**…**) and the tab fan answer a long-press with the same action as a tap; no secondary action (Safari: long-press tabs for Close/New Private Tab). | `shots/ios/main/12-menu-longpress.png` | S4 | daily | S | 3 | — |

Holds up well: the carousel grows out of the page and back into it (a custom hero, `TabStack.swift:62-64`, so E2's
"no matched geometry" is about the API, not the effect); paging carries velocity and ticks a selection haptic per
card; archive has Undo in a toast and Shake to Undo; "1 Tab"/"3 Tabs" plurals are right; Reduce Motion swaps every
carousel spring for a 0.2 s ease-out.
