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
| MS-9 | P3 | At the minimum window size the Today list is cut off below New Tab with no fade or scroll cue (overlay scrollbars are hidden at rest). | `shots/mac/min-light-*.png` (720 × 492; "Today Tab" not visible), `shots/mac-ci/browser-minimum-size-light.png` (a half row peeks under New Tab) | S4 | occasional | S | 2 | — |
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
| MW-8 | P6 | DMG split pane header shows the title in `.caption` with a 6% tint for the focused pane and 2% for the other. The WebKit build also outlines the focused pane in the space tint (`shots/mac-ci/split-view-light.png`); check the DMG shows the same outline, otherwise its focus cue is faint. | `WebPane.swift:72-85` | S4 | occasional | S | 2 | — |
| MW-9 | P7 | The WebKit build's find bar is AppKit's text finder with a **Replace** checkbox and "Done": replace has no meaning on a web page. (The DMG has its own find bar.) | `shots/mac-ci/find-bar-light.png` | S3 | daily | S | 6 | 10 |

Holds up well: the DMG's failure view separates offline (wifi.slash, "Check your internet connection"), unknown host
and crash ("Reload Page"), keeps the address, and re-tries a recovered offline navigation once by itself.

## R2.4 Mac library panel, Archive and History windows

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| ML-1 | P4 | The panel's tab labels are 9 pt with `minimumScaleFactor(0.8)`, so "Archived Tabs" can render at ~7 pt: below the 10–11 pt floor Mac apps use for labels, and unreadable for many. | `LibraryPanel.swift:76`; CI screenshot `shots/mac-ci/library-downloads-light-light.png` shows it truncated to "Archived…" | S3 | daily | S | 6 | — |
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

## R2.8 iPhone search panel (**+**)

Runtime: `shots/ios/main/04-search-panel`, `05-search-typing` (Light), `main-dark/04` (Dark), `private/32` (Incognito).

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| IS-1 | P2 | The field's Clear Text button is 28 × 28 pt, under the 44 pt minimum, right where the thumb lands to retype. | `shots/ios/main/05-search-typing.txt` (Button 'Clear Text' {28, 28}), `Chrome.swift:66` | S3 | every session | S | 8 | — |
| IS-2 | P6 | Opened from the empty browser, the panel's scrim leaves the "No tab open · New Tab" empty state readable behind it, so two "new tab" affordances show at once (the audit flags the dimmed "New Tab" for contrast). | `shots/ios/main/04-search-panel.png`, `04-search-panel.audit.txt` | S4 | rare | S | 1 | 7 |
| IS-3 | P8 | With a hardware keyboard, ↑/↓ don't move through suggestions and ⌘L/⌘T do nothing; Return is the only key. | `rg keyboardShortcut Apps/iOS` (3 hits, none here) | S4 | rare | S | 1 | — |
| IS-4 | P6 | No state for "suggestions failed" or offline: rows just don't appear, and the panel stays at full height (it grows on the first keystroke and keeps it by design). Judgment: fine for failures, but an offline hint would explain the empty panel. | `Chrome.swift:39-44` | S4 | occasional | S | 2 | — |

Holds up well: 44 pt rows with separate 44 × 44 Fill In buttons labelled "Fill In <suggestion>", inline completion
that doesn't come back after Delete, `.webSearch` keyboard with Go, no autocorrect or auto-capitalisation, the panel
grows once and holds its height so the field never jumps, nothing is sent in Incognito or for addresses.

## R2.9 iPhone page menu (**…**)

Runtime: `shots/ios/main/07-08`, `main/12` (error page), `tabs/26`, `private/30` (scrolled to the end), Dark
`main-dark/07`, `tabs-dark/26`; audits `07-page-menu.audit.txt`, `private/30-menu-end.audit.txt`.

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| IM-1 | P3 | The panel cuts its last visible row in half at the bottom edge (Print, Archive Tab) with no fade or edge effect, at rest and after scrolling; it reads as clipped rather than "more below". The README's 2026-11-13 note said the same. | `shots/ios/main/07-page-menu.png`, `tabs/26-menu-bottom.png` | S3 | daily | S | 6 | 7 |
| IM-2 | P7 | One undivided list of ~18 rows: page actions (Find, Reader, Listen, Translate, Print, Copy URL, Downloads), site settings (text size, Desktop, Pop-ups, Content Blocking), tab actions (Reopen Closed Tab, Archive Tab) and app items (Tidy Tab Titles, Library, Incognito, Settings) at the very end, three swipes down. No section titles. | `shots/ios/private/30-menu-end.png`, `PageSettingsMenu.swift:47` | S3 | daily | M | 3 | — |
| IM-3 | P1 | Drag-to-dismiss decides with the predicted end translation but doesn't carry velocity: past the threshold the panel leaves on its fixed transition; short of it, it snaps back on `BottomPanelStyle.motion`. The rubber band when dragging up is right. | `BottomPanel.swift:76-90` | S3 | daily | S | 6 | — |
| IM-4 | P4 | The Back/Forward/Reload/Share tile captions (`caption2`, one line, fixed 56 pt tiles) clip at larger text sizes; the site monogram letter ignores Dynamic Type. | `07-page-menu.audit.txt` ("Text clipped", "Dynamic Type font sizes are partially unsupported" ×4, "unsupported" for 'E'), `PageSettingsMenu.swift:212-214` | S3 | rare | S | 2 | — |
| IM-5 | P5 | The scrim (black 18%) dims the page but not the rail or bottom bar under the panel, by design so they stay tappable; the bright, live bar next to a dimmed page makes it unclear what's modal. Judgment; the README's 2026-11-13 note flagged it on the bottom bar. | `shots/ios/main/07-page-menu.png`, `BottomPanel.swift:9-11,33-39` | S4 | daily | S | 3 | 7 |
| IM-6 | P3 | Not reproduced in the simulator: the README's "smeared shadow" on disabled Back/Forward tiles (they render at 40% opacity with no shadow here). Check on a device. | `shots/ios/main/07-page-menu.png`, `PageSettingsMenu.swift:215-217` | — | — | — | — | — |

Holds up well: concentric corners (panel 28 pt, tiles 16 pt at a 12 pt inset), 46–50 pt rows, a grabber, disabled
items dim instead of disappearing, `.isModal` plus an escape action for VoiceOver, Reduce Motion fades instead of
sliding, text size shows tabular digits.

## R2.10 iPhone Duo postures

Runtime: folded only (simulator). Open, book, laptop and the hinge moving while a video plays (must-have 9) are
**needs device**. Code-read findings:

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| DU-1 | P2 | Half-open tab strip rows are 36 pt tall and each row's close button is 28 × 36 pt, under 44 pt, on a screen held in the air. | `TabStrip.swift:15,54,62` | S3 | daily | S | 6 | 9 |
| DU-2 | P11 | Posture changes are covered by a snapshot whose removal waits on timers: a 150 ms sleep, then a 300 ms fallback before the 0.2 s fade. The split itself waits 250 ms so a hand-speed unfold doesn't flash half-open (a deliberate debounce). Measure on device whether the cover lingers after the page is ready. | `RelayoutCover.swift:102-111`, `RootView.swift:86-92` | S3 | daily | M | 3 | 9 |
| DU-3 | P7 | Landscape status pill builds its battery string by hand (`"\(Int(level * 100))%"`) rather than `.percent` formatting. | `RootView.swift:279` | S4 | occasional | S | 2 | — |
| DU-4 | P3 | Folded: the rail column takes the page's edge colour so the page seems to run under the camera; with tinting off or before a page's colours arrive, the column is the plain background. Judgment: check the change-over isn't a visible flash on device. | `ToolRail.swift:58-63` | S4 | every session | S | 4 | 9 |

**Needs device (Chen), exact checks:** (1) unfold flat with a page open: the page must not reload and the cover must
lift as soon as the page has re-laid out; (2) half-open (book): tab strip + two panes, tap targets in the strip;
(3) laptop: keyboard over the panes, the fold stays put; (4) move the hinge through every posture while a YouTube
video plays (must-have 9); (5) unfolded portrait: the bar collapses while reading (`collapsesBar`) and the page ends
above it (must-have 7). Record each at 120 Hz with screen recording.

## R2.11 Widgets, extensions and system integration

Runtime: not rendered (widget gallery and share sheets need interaction outside the app; code-read). `boaz://` links
reach the app through the system "Open in 'Boaz'?" prompt (`shots/ios/links/`).

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| WX-1 | P10 | No Handoff between Boaz on iPhone and Mac, no Spotlight items for pinned tabs or favorites, no Focus filter, no Mac App Intents or Services. Handoff is approved (§7.2) and is the biggest "two devices, one browser" gap. | `rg 'NSUserActivity|CSSearchable|SetFocusFilterIntent|NSServices' Apps` → 0 | S2 | daily | L | 3 | 10, 11, 13 |
| WX-2 | P10 | No Control Center / Lock Screen control (`ControlWidget`) for "New Tab" or "Search", which iOS 18+ users expect from a browser. | `BoazWidgetsBundle.swift` (search widget only) | S3 | occasional | M | 2 | — |
| WX-3 | P5 | The medium widget's favorites are letter tiles, because favicons live in the app's container and the widget can't read them. Safari's Favorites widget shows site icons. | `BoazSearchWidget.swift:103-120` (comment says why) | S3 | daily | M | 3 | 11 |
| WX-4 | P6, P7 | Share extension errors are raw: `error.localizedDescription` from the store, "Couldn't find <Space>'s tabs.", "Nothing to save yet."; no next action. The success checkmark has no haptic. | `ShareModel.swift:50,59,73`, `ShareRootView.swift:43-62` | S4 | rare | S | 1 | 11 |
| WX-5 | P7 | Share extension buttons say "Pin" and "Open on iPhone" inside an iPhone share sheet; "Open on iPhone" reads oddly on the iPhone itself (it means "add to my iPhone tabs"). | `ShareRootView.swift:30-36` | S4 | occasional | S | 2 | 8 |

Holds up well: the 2026-11-09 widget P0 is fixed (small and circular use `widgetURL`, the circular widget has a
container background and a label, `BoazSearchWidget.swift:53-61`); the medium widget has an empty state; the share
extension shows a space picker and a confirmation.

## R2.12 Accessibility: system audit

**iPhone.** `XCUIApplication.performAccessibilityAudit(for: .all)` on 18 screens (Light, Dark, Incognito), raw output
in `shots/ios/*/NN-*.audit.txt`. Totals: 51 contrast failed, 8 contrast nearly passed, 39 text clipped, 35 Dynamic
Type partially or fully unsupported, 26 hit area too small, 2 label not human-readable. Sorting them:

- **Hit areas (26):** all on Wikipedia's page content, none in Boaz chrome. The audit misses the 34 × 40 pt tab fan
  (IB-2) and the 28 pt Clear Text button (IS-1), found in the hierarchy dumps instead.
- **Contrast (51):** onboarding buttons on the gradient (OB-2), disabled page-menu items at 40% opacity (accepted:
  disabled controls are the exception in `docs/design.md`), menu rows over glass where the page behind is busy, and
  the dimmed empty state behind the search panel (IS-2). Simulator contrast sampling varies run to run (`docs/qa.md`
  §5 excludes it from CI for that reason); confirm by eye.
- **Dynamic Type / clipping (74):** page-menu tiles (IM-4), onboarding button (OB-3), and `ContentUnavailableView`
  error and empty states ("Can't Open This Page", "Archive is empty"); the last group is the system view and likely
  noise unless R2.14 shows real clipping.
- **Label not human-readable (2):** the carousel card of an untitled failed tab is labelled with its bare host
  ("nonexistent.invalid").

**Mac.** The CI suite runs the same audit (all but contrast) on every Mac screen, isolated, on GitHub's runner. On
`master` 66c3d63: 62 tests, 49 passed, **1 failed** (`testToast`: the toast vanished before its screenshot), the
rest skipped; **no audit failures**. 69 screenshots of every Mac screen exported to `shots/mac-ci/` (from run
artifact `UITestResults`, `ci-uitest.xcresult`). This is the WebKit build; the DMG needs `BOAZ_UITEST_APP` (needs Chen
session).

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| AX-1 | P12 | `testToast` fails on master: the toast's 2.5 s lifetime (5 s with Undo) races the screenshot, so the Mac toast screen is the one screen without an audit. | `ci-uitest.xcresult` summary; `MacModel.swift:946-948` | S3 | every session | S | 8 | 14 |
| AX-2 | P12 | The system audit can't see hit areas inside custom rail and bar controls (it flagged none of IB-2, IS-1, DU-1); hit-target checks need the hierarchy-frame assertion the Mac suite already has ("no overlapping buttons"), ported to an iPhone UI test target. | `shots/ios/main/06-page.txt` vs `06-page.audit.txt` | S3 | every session | M | 4 | — |
| AX-3 | P12 | A failed tab's carousel card is labelled with its bare host, which the audit calls "not human-readable"; label it "<host>, couldn't load". | `tabs/21-carousel.audit.txt` | S4 | occasional | S | 2 | — |

## R2.13 Accessibility: VoiceOver walk of the five main flows

The simulator harness can't run VoiceOver, so this walk reads what VoiceOver would get: the element tree from each R0
screen (`shots/ios/*/NN-*.txt`), the Mac CI audit, and every `accessibility*` modifier in `Apps/`. A spoken walk on a
device (iPhone) and with VoiceOver on the Mac DMG is **needs Chen** (15 min: the five flows below, VO on, note anything
announced wrong or skipped).

| Flow | iPhone | Mac |
|---|---|---|
| 1. Open a page from search | "Search" / "New Tab" buttons labelled; field "Search or enter address"; suggestion rows read their text, Fill In buttons read "Fill In <text>"; panel is modal with an escape action | Command bar field identified; rows are buttons with a selected trait |
| 2. Switch tabs | Tab fan: "Tabs, 3 open, Shows your tabs side by side"; on the page: "Next Tab"/"Previous Tab" actions; carousel: escape, next/previous, per-card "Archive" action | Sidebar rows: buttons with the title, selected trait, folder "Expanded/Collapsed" value; but no keyboard focus (MS-2) |
| 3. A page-menu action (Find on Page) | Rows labelled; tiles "Back"/"Forward" labelled and dimmed; no headers in an 18-row list (IM-2) | Menu bar commands (full) |
| 4. Archive a tab, then Undo | Card action "Archive"; toast announced; Undo button in the toast, 10 s under VoiceOver | Row context menu only (no custom action, MS-3); toast announced, Undo in it |
| 5. Settings | Standard `Form` rows | Standard; audit clean on every pane |

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| AX-4 | P12 | Search suggestion rows announce only their text ("example pdf, button"); nothing says whether a row searches, opens a history page or switches to a tab, which sighted users get from the icon. Add the kind as a value or hint. | `shots/ios/main/05-search-typing.txt` | S3 | daily | S | 6 | — |
| AX-5 | P12 | No rotors anywhere (0 `accessibilityRotor`): History and Archive lists, the carousel and the Mac sidebar can only be walked item by item. A "Tabs" rotor on the page and a "Pinned/Today" rotor in the sidebar would match Safari. | `rg accessibilityRotor Apps` → 0 | S3 | occasional | M | 2 | — |
| AX-6 | P12 | iPhone has no `accessibilityShowsLargeContentViewer` on the rail and bar buttons, whose glyphs are capped (`min(glyph, 28)`) and don't grow past AX sizes: long-press-to-magnify is the system's answer for fixed-size bar controls. | `ToolRail.swift:169,186` | S3 | occasional | S | 4 | 7 |
| AX-7 | P12 | Voice Control: the tab fan's visible content is a stack of thumbnails while its name is "Tabs"; the rail's ellipsis button is "Page Settings" though it shows "…" and is called the page menu in docs. Users have to guess the spoken names. Use `accessibilityInputLabels` with "Tabs", "Menu", "More". | `shots/ios/main/06-page.txt`; `TabBrowser.swift:465,506` label "Page Settings" | S4 | rare | S | 1 | — |

## R2.14 Accessibility: Dynamic Type AX3 and AX5 (iPhone)

Runtime: `simctl ui content_size accessibility-large` (AX3) and `accessibility-extra-extra-extra-large` (AX5), same
screens each time: page, page menu, search panel typing "exa", carousel, Settings. Screens in
`shots/ios/dt-accessibility-large/` and `shots/ios/dt-accessibility-extra-extra-extra-large/`, side by side in
`shots/ios/dt3.png`, `dt5.png`.

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| AX-8 | P4, P3 | At AX5 the carousel header's "1 Tab" runs into the "Done" button: the two overlap ("1 TaDone"). | `dt-accessibility-extra-extra-extra-large/43-carousel.png` | S1 | occasional | S | 8 | — |
| AX-9 | P4 | At AX5 the page menu shows about one and a half rows in its half-height panel; tile captions truncate to "Ba…", "Fo…", "Re…", "Sh…" and the title to "Exampl…". At AX3 "Forward" already truncates ("Forw…"). The panel should grow to full height and the tiles drop their captions (or stack) at accessibility sizes. | `dt-…-large/41-page-menu.png`, `dt-…-extra-extra-extra-large/41-page-menu.png` | S1 | occasional | M | 4 | 7 |
| AX-10 | P4 | At AX5 the search panel's "Switch to Tab" caption breaks mid-word ("Swit / ch to / Tab") beside a title cut to "Ex…"; at AX3 the tab row already squeezes its title to "Exampl…". The caption should move under the title at accessibility sizes (`ViewThatFits` / `dynamicTypeSize.isAccessibilitySize`). | `dt-…-extra-extra-extra-large/42-search.png`, `dt-…-large/42-search.png` | S2 | occasional | S | 6 | — |
| AX-11 | P4 | Settings' sheet title "Settings" stays small at every size while its content grows (inline title in a custom header). | `dt-…/44-settings.png` | S4 | occasional | S | 2 | — |

Holds up well at AX5: page text (WebKit honours the text size), Settings rows wrap instead of truncating, rail glyphs
stay inside their circles by design (capped, `ToolRail.swift:169,186`; see AX-6 for the large content viewer).

## R2.15 Accessibility: Increase Contrast, Reduce Motion, Reduce Transparency

Runtime (iPhone): all three on at once (`simctl ui increase_contrast enabled`, `EnhancedBackgroundContrastEnabled`,
`ReduceMotionEnabled` in the simulator's `com.apple.Accessibility` domain), same five screens:
`shots/ios/a11y-contrast-transparency-motion/` and `rec/a11y-contrast-transparency-motion.mov`. Mac: code-read.

Sweep (deterministic): `accessibilityReduceTransparency` 0 uses; `colorSchemeContrast` in 2 files (Mac sidebar, Duo
tab strip); `accessibilityReduceMotion` in 13 files; 127 animation call sites, of which those in 15 files never
consult Reduce Motion (largest: `BrowserState.swift` 14, `WebPane.swift` 3, `LiveFolderViews.swift` 3, `MacAI.swift`
3, `PullToRefresh.swift` 3).

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| AX-12 | P1, P12 | The Mac model drives 14 springs that never check Reduce Motion: new tab, archive, pin/unpin, split open/close, peek in/out, Incognito insert. Views fade their own insertions under Reduce Motion, but rows still slide and settle with these springs. | `BrowserState.swift:520,979,981,1182,1367,1371,1379,1524,1620,1630,1640,1696,1711,1743` | S2 | daily | S | 9 | — |
| AX-13 | P5 | A translucent space theme (Customize Space, up to 60% see-through) keeps its gradient at partial opacity over the window's blur. With Reduce Transparency the system blur turns opaque grey, so the theme washes out to a greyer tint instead of turning solid. Use full opacity when `accessibilityReduceTransparency` is on. | `WindowTheme+SwiftUI.swift:108-112`, `BrowserWindow.swift:247-271` | S3 | occasional | S | 4 | 5 |
| AX-14 | P5 | Increase Contrast changes only the Mac sidebar's selection fill and the Duo tab strip. The page-menu tiles (`.background.opacity(0.55)`), carousel captions, search-panel row highlight and the Mac command bar keep their normal-contrast fills. In the iPhone capture the page-menu tiles and search highlight look the same as without it. | `shots/ios/a11y-contrast-transparency-motion/m.png` vs `main/07`, `05`; `PageSettingsMenu.swift:167,215` | S3 | occasional | M | 2 | — |
| AX-15 | P5 | Reduce Transparency works on iPhone glass for free: the page menu, search panel and rail turn solid (system `glassEffect`), so E4's "zero handling" mostly matters for the custom fills above (AX-13, the 0.55 tiles) and the DMG command bar's 92% background. | same capture | — | — | — | — | — |

Reduce Motion holds up where it's checked: carousel springs become a 0.2 s ease-out, panels fade instead of
sliding, onboarding fades, the Mac space push fades and hover lifts freeze. Recording a Reduce Motion pass on the
Mac needs Chen session.

## R2.16 Re-verification of the 2026-11-09 review (`inputs/ux-review-2026-11-09.md`)

Status against 66c3d63. **Fixed** = the problem is gone (evidence given); **open** = still true (pointer to the
R2 finding that carries it); **obsolete** = the surface no longer exists (Folio-era Space Home, per-space iPhone UI).
Tally: 19 fixed, 11 open or partly open, 10 obsolete.

| Old | Status | Evidence now |
|---|---|---|
| P0-1 widgets open the app, circular has no background | Fixed | `BoazSearchWidget.swift:53-61` (`widgetURL`, container background, label) |
| P0-2 Clear History/Archive in one tap, confetti | Fixed | Confirmation dialogs (`LibrarySheet.swift:80`, `LibraryViews.swift:124,190`); `rg confetti Apps` → 0 |
| P0-3 Mac sidebar unusable with VoiceOver or keyboard | Partly open | VoiceOver: rows are buttons with labels and selection (`Sidebar.swift:885-889`). Keyboard focus still missing → MS-2; custom actions → MS-3 |
| P0-4 no visible Back on standard iPhones, no Forward | Fixed differently | Back/Forward tiles with history menus in the page menu (`PageSettingsMenu.swift:95-118`) plus edge swipe; bottom bar itself needs device |
| P0-5 failed load leaves a blank page | Fixed | "Can't Open This Page" + Try Again (`TabBrowser.swift:196-206`, `shots/ios/main/11`); offline copy still generic → MW-5 |
| P1-1 home content under the bar, dots over cards | Obsolete | Space Home removed (must-have 8) |
| P1-2 Today card close button 24 pt | Obsolete | Space Home removed |
| P1-3 touch targets under 44 pt | Open (new places) | IB-2 tab fan 34 × 40, IS-1 Clear Text 28, DU-1 strip 28 × 36 |
| P1-4 missing iOS VoiceOver labels | Fixed, one new gap | Menu labelled (`HomeBar.swift:68`); new: OB-1 iCloud icon |
| P1-5 gestures without alternatives, nothing teaches them | Fixed | Next/Previous Tab and Archive actions (`TabStack.swift:155-156,474`, `TabBrowser.swift:116-117`); TipKit toolbar tip |
| P1-6 search overlay without escape or modal trait | Fixed | `BottomPanel.swift:49-51` (`.isModal`, escape action) |
| P1-7 toasts not announced, 5 s Undo | Fixed | `AppModel.swift:1052`, `MacModel.swift:944` (announced, 10 s under VoiceOver) |
| P1-8 tab paging slides from the wrong side | Obsolete | Paging moved to the carousel deck with velocity (`TabStack.swift:252`); the old `move(edge:)` is gone |
| P1-9 haptics fire too often | Fixed | 11 `sensoryFeedback` sites, each on a commit or threshold; none on scroll |
| P1-10 book/laptop "Tabs" button closes the page | Obsolete (needs device) | Posture layout rewritten (`RootView.swift` `PostureLayout`, `TabStrip`) |
| P1-11 no Find on iOS; Mac Find replaces the Edit text group | Fixed | iOS page menu Find on Page; Mac Edit › Find in Page… as its own item (`menus-webkit-adhoc.txt`) |
| P1-12 Clear Today's Undo restores one tab | Fixed | `MacModel.swift:640` ("Undo restores both" tabs and folders) |
| P1-13 Mac lacks zoom, Print, History | Fixed | View › Zoom In/Out/Actual Size, File › Print…, History › Show All History (`menus-webkit-adhoc.txt`) |
| P1-14 Mac Settings window not Mac-like | Fixed | Toolbar panes (`ChromiumSettingsWindow.swift`, `LibraryViews.swift:255`); pane chrome differs by build → ST-6 |
| P1-15 Mac sidebar type too small | Fixed | 15 pt rows with a 14/15/17 setting (`docs/design.md`); glyphs don't scale → MS-7 |
| P1-16 Dynamic Type breaks main surfaces | Open (new surfaces) | AX-8, AX-9, AX-10 at AX3/AX5 |
| P1-17 Library "empty" on no results; History can't delete | Fixed | `ContentUnavailableView.search` (`LibrarySheet.swift:57`); swipe Delete (`:26`) |
| P1-18 shake to undo silent, ignores the setting | Fixed | Alert "Undo Archive Tab?" and `applicationSupportsShakeToEdit` check (`RootView.swift:345-348`) |
| P1-19 widget favorites all globes, no empty state | Partly open | Letter tiles and an empty state (`BoazSearchWidget.swift:64-69,103`); real icons → WX-3 |
| P2-1 glass on material, mixed materials | Obsolete | Space Home cards removed; remaining glass-over-tint is Liquid Glass panels |
| P2-2 radii not tokenized | Open | `MacRadius` exists; literals remain → ML-4, MS-10 |
| P2-3 dark space cards blend into the backdrop | Obsolete | Space Home removed |
| P2-4 sheet buttons without iOS 26 roles | Fixed | `Button(role: .close)` in sheet toolbars (`LibrarySheet.swift:224`, `TabStack.swift:571`, `DownloadsView.swift:52`) |
| P2-5 copy inconsistent | Open | ML-3, ST-1, MW-3, MW-6 |
| P2-6 shortcut hints hard-coded | Fixed | `keys.hint(...)` everywhere (`Sidebar.swift:104`, `BrowserWindow.swift:601`) |
| P2-7 error toasts show raw system strings | Open | `MacModel.swift:244,633,651,787,873,924` ("Couldn't save: \(error.localizedDescription)") |
| P2-8 Mac Back/Forward dimmed but enabled | Fixed | `.disabled(items.isEmpty)` (`Sidebar.swift:175`) |
| P2-9 manual NSCursor push/pop | Fixed | `.pointerStyle(.frameResize/.columnResize)` (`BrowserWindow.swift:328,483`) |
| P2-10 Mac window titles never set | Partly open | WebKit: `.navigationTitle(windowTitle)` (`BrowserWindow.swift:98`). DMG: the AppKit window is titled "Boaz" or "Boaz — Private" (`ChromiumAppWindow.swift:63`), so the Window menu can't tell windows apart, and "Private" contradicts "Incognito" everywhere else (P7) |
| P2-11 folder icon states reversed between platforms | Obsolete | iPhone has no folders UI (must-have 8) |
| P2-12 Reduce Motion / Increase Contrast gaps | Partly open | The five listed transitions now check Reduce Motion; model springs don't → AX-12; Increase Contrast only in two files → AX-14 |
| P2-13 fold glow over the page at 80% | Obsolete (needs device) | Replaced by `FoldFill` behind the panes (`RootView.swift:49`) |
| P2-14 Pro Max landscape gets the unfolded layout | Fixed | Layout keys on the hinge's reserved region, not size class (`RootView.swift:16-20,50-52`) |
| P2-15 context menus unequal across platforms | Open | iPhone cards and fan have none → IB-6 |
| P2-16 small polish items | Mixed | Folded into the R2 sections above where still true |

New finding from this pass:

| ID | P | Finding | Evidence | Sev | Reach | Eff | Score | MH |
|---|---|---|---|---|---|---|---|---|
| MS-13 | P7, P10 | DMG windows are titled "Boaz" (or "Boaz — Private") whatever space or page they show, so Window menu, Mission Control and the VoiceOver window chooser can't tell them apart; "Private" is the only place that name is used for Incognito. | `ChromiumAppWindow.swift:63` | S3 | daily | S | 6 | 2 |
| MS-14 | P6, P7 | Mac error toasts append the raw system error ("Couldn't save: The operation couldn't be completed. (…)") in six places. | `MacModel.swift:244,633,651,787,873,924` | S3 | rare | S | 2 | 13 |
