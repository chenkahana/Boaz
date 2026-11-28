# R4. Systems design

Shared systems first, so per-screen fixes land as token changes. Each section ends with what changes in code and
where it would live; nothing here is implemented (research only). Once approved, these become `docs/design.md`
sections next to the sidebar rules. Where Edison and Jimmy need the same system, the names and rules here are meant
to be reused as-is (§1 "Sister handoffs").

## R4.1 Motion tokens and transition catalog

**Today (deterministic count, 66c3d63):** 45 distinct curves across `Apps/` (`rg` for `spring(`, `easeOut(`,
`smooth`, `snappy`, `bouncy`, `interpolatingSpring`): 23 `spring(response:dampingFraction:)` pairs, 2
`interpolatingSpring`s, 10 eases (one linear) and 10 `smooth`/`snappy`/`bouncy` variants. Four named constants exist, two of them called `motion` with different values
(`SidebarStyle.motion` smooth 0.2, `BottomPanelStyle.motion` snappy 0.3), plus `TabStack…motion` smooth 0.2 and
`Onboarding.spring` (0.5, 0.86). The most common literal, `.easeOut(duration: 0.2)` (9 uses), is mostly the hand-written
Reduce Motion fallback.

### Tokens (one set, two platform tunings)

| Token | Use for | iPhone | Mac | Reduce Motion |
|---|---|---|---|---|
| `quick` | Hover, press, selection, symbol swaps, small toggles | `.snappy(duration: 0.2)` | `.smooth(duration: 0.2)` (= today's `SidebarStyle.motion`, keeps `docs/design.md`) | unchanged (no movement involved) |
| `standard` | Panels and popovers in/out, list inserts and removals, toasts, split open/close | `.smooth(duration: 0.3)` | `.smooth(duration: 0.25)` | `.easeInOut(duration: 0.2)` cross-fade |
| `emphasized` | Presenting a hero: carousel open/close, page menu, command bar, space switch, peek | `.spring(duration: 0.45, bounce: 0.12)` | `.spring(duration: 0.4, bounce: 0.1)` | cross-fade 0.25 s |
| `gesture(velocity:)` | Anything a finger or trackpad releases: carousel paging, archive flick, panel drag-dismiss, space swipe, sidebar/split width snap | `.interpolatingSpring(duration: 0.42, bounce: 0.1, initialVelocity: v)` | same, velocity from the trackpad | `.easeOut(duration: 0.2)`, no overshoot |

Rules:
- No literal curves in views or models. A new need gets a token or reuses one.
- **Velocity always carries.** Every gesture end computes `v = remaining distance ÷ release velocity` and passes it to
  `gesture(velocity:)` (fixes IB-5, IM-3, MS-15; the carousel's `settle(velocity:)` is the model to copy).
- **Reduce Motion is read once, in the token**, not at each call site: a view modifier `.motion(.standard, value:)`
  and a model helper `withMotion(.standard) { … }` both resolve the fallback from
  `accessibilityReduceMotion` / `UIAccessibility.isReduceMotionEnabled` / `NSWorkspace…ShouldReduceMotion`. This
  removes the 9 hand-written fallbacks and covers the 14 model springs that ignore it today (AX-12).
- `bouncy` is reserved for one celebratory moment (picking an app icon); never for hover or chrome (MS-6).
- First appearance of restored content never animates (launch, relaunch, posture change): wrap restores in
  `withTransaction(\.disablesAnimations)`.

### Transition catalog

| Transition | Motion | Token | Reduce Motion | Used by |
|---|---|---|---|---|
| **present** | From its source: a panel rises from the bar it belongs to; a popover grows from its button; the command bar grows from the address pill for ⌘L (MC-3) | `emphasized` | fade | page menu, search panel, command bar, library panel, peek |
| **dismiss** | Back along the same path; interactive dismiss follows the finger and hands off velocity | `emphasized` / `gesture` | fade | same |
| **push** | Lateral, in the direction of travel (next space from the trailing edge) | `emphasized`, or `gesture` when swiped | fade | space switch, onboarding pages |
| **morph** | A card grows into the page it opens and shrinks back into its slot | `emphasized` | fade | iPhone carousel ↔ page (today a custom hero; `navigationTransition(.zoom)` / `matchedGeometryEffect` where the API fits) |
| **collapse** | A closed or archived item shrinks toward where it lived; neighbours close up | `standard` | fade | sidebar rows, carousel card archive, toasts |
| **appear** | None | — | — | restored windows, tabs, scroll positions |

**Code shape.** `Motion` enum in a shared file (`Apps/Shared/Theme/Motion.swift`) with the four tokens and
platform `#if`; `SidebarStyle.motion`, `BottomPanelStyle.motion`, the TabStack constant and `Onboarding.spring`
become aliases, then go. One PR replaces the literals by surface (W1), each with a before/after recording.

## R4.2 Haptic map

**Today:** 11 `sensoryFeedback` sites, all iPhone (and the share extension); 0 on the Mac
(`NSHapticFeedbackManager` unused). Existing iPhone haptics are already on meaningful moments: carousel paging
(`.selection` per card, `TabStack.swift:132`), back/forward swipe (`TabBrowser.swift:124`), pull-to-refresh armed
(`:125`), Undo toast (`RootView.swift:63`), onboarding step/finish, iCloud ready, app icon pick, share saved.

Rule: one haptic per meaningful moment (commit, threshold crossed, snap, success, failure), never on scroll ticks,
hover or plain taps that already show a press state. Every haptic is triggered from the same state change that drives
the visual, so the two can't drift.

### iPhone (`sensoryFeedback`)

| Event | Feedback | Today | Change |
|---|---|---|---|
| Carousel moves to another card | `.selection` | yes | keep |
| Archive flick passes the commit threshold (−110 pt) | `.impact(weight: .medium)` at the crossing, not on release | no (only the later toast) | add (IB-4); drop the toast's medium impact when the gesture already gave one |
| Archive / close via button or menu | none (toast shows) | toast medium impact | keep toast impact for non-gesture closes only |
| Undo performed | `.success` | no | add |
| Pull-to-refresh armed | `.impact(weight: .light)` | yes | keep |
| Back/forward edge swipe commits | `.selection` | yes | keep |
| Page menu or search panel drag-dismiss passes its threshold | `.impact(weight: .light)` | no | add (IM-3) |
| Tab fan long-press opens a secondary menu (IB-10) | system context-menu haptic | n/a | comes with `.contextMenu` |
| Posture change splits / joins panes (Duo) | none | none | keep none: the hinge itself is the feedback |
| Load failure shown | `.error`? | no | **no**: a passive error page isn't an action's result; only when a user action fails (Try Again fails again) |
| Share extension saved; iCloud ready; onboarding finished | `.success` | yes | keep |

### Mac (`NSHapticFeedbackManager.defaultPerformer`, trackpad only)

| Event | Pattern | Performance time |
|---|---|---|
| Sidebar width hits 200 or 420 pt, or a snap width | `.alignment` | `.now` |
| Split divider snaps to 50% (and 33/67 if added) | `.alignment` | `.now` |
| Dragged row crosses into a new slot or over a folder (spring-load fires) | `.generic` | `.drawCompleted` |
| Space swipe passes its commit point (MS-15) | `.levelChange` | `.now` |
| Favorite tile / pinned drop accepted | `.generic` | `.drawCompleted` |

Code shape: a `Haptics` enum beside `Motion` (`Apps/Shared/Theme/Haptics.swift`) with named events
(`.cardChanged`, `.archiveCommitted`, `.snap`, `.slotChanged`, `.undo`), mapped per platform, so a fix calls
`Haptics.play(.snap)` and the mapping stays in one table. Mac haptics fire only from trackpad-driven drags (the
performer is silent for a mouse anyway).

## R4.3 Layout tokens

**Today (deterministic):** two radius scales already exist, `MacRadius` (6/8/10/12/16, used in 9 files) and iOS
`Theme.Radius` (row 12, tile 18, card 20, sheet 30, used in 4 files), plus two stray constants (`Theme.cornerRadius`
18, `BottomPanelStyle.cornerRadius` 28). (The plan's E11 said iOS had none; it has one, mostly unused.) 33 literal
`cornerRadius:` values remain (10 ×7, 6 ×5, 12 ×5, 8 ×4, 22/20/16 ×3, 18 ×2, 24). Paddings and stack spacings are all
literals: padding 8 ×43, 12 ×33, 16 ×25, 10 ×23, 6 ×18, 4 ×16, 20 ×15, 14 ×8; spacing 8 ×46, 10 ×27, 2/12 ×25,
6 ×23, 4/14 ×18. In practice the app already uses a 2-4-6-8-10-12-14-16-20-24 ladder; 10 and 14 are the odd steps.

### Spacing scale (both platforms)

`xxs 2 · xs 4 · s 6 · m 8 · l 12 · xl 16 · xxl 20 · xxxl 24 · section 32`. 10 and 14 fold into 8/12 or 12/16 per call
site (judge by eye; the sidebar's documented 8/10 values in `docs/design.md` stay as named sidebar constants).

### Radius scale and the concentric rule

| Token | Mac | iPhone | Used for |
|---|---|---|---|
| `icon` | 6 | 8 | favicons, monograms |
| `row` | 8 | 12 | rows, hover/selection fills, fields |
| `tile` | 10 | 16 | favorites, menu tiles, nav tiles |
| `card` | 12 | 20 | content card (Mac), carousel cards, sections |
| `panel` | 16 | 28 | popovers, command bar, bottom panels |
| `sheet` | system | 30 / system | sheets: let the system draw them |

**Concentric rule:** an inset container's radius = outer radius − inset, rounded to the nearest token, never above
the outer. Checks to run: the Mac content card (12 at a 6 pt inset) against the macOS 26 window corner (MS-10:
measure on a 2× display; if the window radius is ≤ 16, the card should be 10 = `tile`); the iPhone page menu already
passes (panel 28, tiles 16 at a 12 inset). Always `style: .continuous`.

### Hit targets

iPhone: 44 × 44 pt minimum for every control, enforced in the components (`RailButton`, `RailIcon`, field clear
buttons, `TabStrip` rows) with `.frame(minWidth: 44, minHeight: 44).contentShape(...)`, not per call site; one bar
control size of **48 pt** (R3.1) for the rail and bottom bar. Mac: the whole row or tile is the click target
(`contentShape`), 24 pt minimum for icon buttons, a tooltip on every icon-only control (already true).

Code shape: `Spacing` and `Radius` enums in `Apps/Shared/Theme/` with platform values; `MacRadius` and
`Theme.Radius` become those; one W3 PR per surface replaces literals, each with a before/after screenshot.

## R4.4 Type ramp

**Today (deterministic):** 57 fixed `.system(size:)` fonts (Mac 43, iPhone 8, Shared 4, Browser 1, Extensions 1);
text styles are used widely (caption family ~95, callout 28, headline 24, body 14, title2 10, footnote 8,
subheadline 7, title3 3, title/largeTitle 1 each); 9 uses of `@ScaledMetric` / `dynamicTypeSize` /
`monospacedDigit` in total. The Mac sidebar's text-size setting (14/15/17) reaches rows, headers and the title only
(`SidebarStyle`), not glyphs (MS-7), the command bar (MC-5) or the library panel (ML-1).

### iPhone: text styles only

| Role | Style | Notes |
|---|---|---|
| Screen / sheet title | `.title2.bold()` via `navigationTitle` | Settings title grows (AX-11) |
| Empty / error title | `ContentUnavailableView` defaults | don't restyle |
| Row title | `.body` | page menu rows, Settings, Library |
| Row secondary (host, caption) | `.subheadline` / `.footnote`, `.secondary` | hosts truncate in the middle (`.truncationMode(.middle)`) so the domain's end stays |
| Tile caption (Back, Forward…) | `.caption` | at `isAccessibilitySize`, hide captions and rely on labels + large content viewer (AX-9) |
| Toast | `.callout.weight(.medium)` | today's value |
| Counts and zoom % | any style + `.monospacedDigit()` | "3 Tabs", text size %, download progress |

`@ScaledMetric` is allowed only for glyph and control sizes inside fixed-shape chrome (rail circles, tiles), capped,
and paired with `accessibilityShowsLargeContentViewer` (AX-6). No `.system(size:)` for text on iPhone.

### Mac: one ramp driven by the sidebar text size

The Mac has no Dynamic Type, so Boaz's own setting is the user's text size. Make it a ramp instead of a row size:
`base` = 14/15/17 (Small/Medium/Large) and every chrome size derives from it.

| Role | Size | Weight |
|---|---|---|
| Sidebar row | base | regular; selected medium |
| Sidebar section header | base − 3 | semibold |
| Space title | base + 1 | semibold |
| Sidebar glyphs (plus, lock, link, ellipsis) | base − 3 (via `.imageScale` or a derived font) | semibold |
| Command bar field | base + 4 | regular |
| Command bar rows | base − 1 | regular; caption base − 4 |
| Library panel tab labels | max(base − 4, 11) | medium; never `minimumScaleFactor` below 11 pt (ML-1) |
| Library and Settings rows | system `.body` (13) | — |

Code shape: `SidebarStyle` grows into a `ChromeType(base:)` value in the environment (it already carries
`sidebarTextSize`), read by the sidebar, command bar and library panel; the 43 Mac `.system(size:)` literals move to
it in W3.

## R4.5 Copy rules, glossary and String Catalog (English only, §7.3)

**Today (deterministic):** no `.xcstrings` file in any target; 2 `String(localized:)`; ~630 user-facing string
literals in `Text`/`Button`/`Label`/`Toggle`/`Picker`/`Section`/`Menu`/`ContentUnavailableView`/`help`/
`accessibilityLabel`/`showToast` calls; **30 hand-built plurals** (`count == 1 ? "" : "s"`, e.g. "Archived \(n)
tab\(s)", `MacModel.swift:242,663,768`, `MacAI.swift:170,186`, `ArcImportView.swift:89-91`); percentages built
by hand (`"\(Int(level * 100))%"` in `BrowserWindow.swift:78`, `DevToolsViews.swift:140`, `RootView.swift:279`,
"N percent" in `ThemeColorPicker.swift:256,294`).

### Capitalization

| Element | Rule | Example |
|---|---|---|
| Buttons, menu items, window and sheet titles, tab names, tooltips (Mac help tags) | Title case | "Reopen Closed Tab", "Previous Match" (fixes MW-6) |
| Settings labels and section headers | Title case on both platforms (matches iOS Settings sections and Boaz's Mac menus) | "Search Engine", "Block Ads and Trackers", "App Icon" (fixes ST-1) |
| Empty-state titles | Title case, "No …" pattern | "No Archived Tabs", "No History", "No Downloads" (fixes ML-3, E6) |
| Descriptions, footers, alert messages, toasts, placeholders | Sentence case, ending period only when it's a full sentence | "Closed and inactive tabs appear here." |
| Error titles | One title per kind: "Can't Open This Page" (generic), "You're Offline", "This Page Stopped Responding" | fixes MW-3 |

**Ellipsis:** "…" (U+2026) on items that open a further step (a sheet, a dialog, a picker); never on items that act
at once; never "..." (the code already complies, verified with `rg '\.\.\."' Apps` → 0).

**Errors:** say what happened, then the next action, in plain words; never append `error.localizedDescription` to a
toast (MS-14, WX-4). Log the detail instead.

### Glossary

| Term | Means | Not |
|---|---|---|
| **Archive** (noun, verb) | Where closed and inactive tabs go; "Archive Tab" | "Archived Tabs" as a separate name (panel tab), "Clear" for archiving Today |
| **Today** | Unpinned tabs of the current space (Mac) | "Today Tab" in UI copy |
| **Pinned** | Tabs kept in a space | "Saved" |
| **Favorites** | The tiles at the top of the sidebar | "Bookmarks" |
| **Space** | A Mac-only sidebar context (never on iPhone, must-have 8) | — |
| **Incognito** | Private browsing, both platforms | "Private" (DMG window title, MS-13; iPhone "Private search") |
| **Live Folder** | A folder filled from GitHub | — |
| **Library** | iPhone sheet (Archive + History); Mac panel | — |
| **Page Menu** | The **…** menu on iPhone (spoken name too, AX-7) | "Page Settings" |

### String Catalog adoption

- One `Localizable.xcstrings` per target (iOS app, Mac app, share extension, widgets) with "Use Compiler to Extract
  Swift Strings" on; English only, so its purpose is review: every string in one place, checked against the rules
  above.
- Plurals through the catalog and automatic grammar agreement: `"Archived ^[\(count) tab](inflect: true)"`;
  the 30 hand-built plurals go.
- Numbers through `FormatStyle`: `.percent` for zoom, battery and transparency; `ByteCountFormatStyle` for download
  sizes (`DownloadsView.swift` `sizeLabel`); `.relative(presentation: .named)` for "Yesterday"; `.list(type: .and)`
  for "2 spaces, 14 tabs and 3 favorites" (`ArcImportView.swift:89-91`).
- **Lint (cheap):** a CI step that fails on `count == 1 ? "" : "s"` and on `"\(Int(` + `* 100` + `)%"` patterns via
  `rg`; a full "literal outside the catalog" check isn't cheap with SwiftUI's `LocalizedStringKey` extraction, so the
  catalog's own "stale/missing" state in Xcode is the review tool instead.

## R4.6 State kit

**Today:** 15+ `ContentUnavailableView`s with mixed titles, three loading styles (DMG spinner over the page,
"Opening page…" centred spinner, iPhone/WebKit progress glow), four error views for a failed page (R2 MW-3, MW-5),
no offline state on iPhone or the WebKit Mac build, no sync-error state anywhere (ST-5).

One component family per platform, in `Apps/Shared/States/`:

| Component | Shows | Rules |
|---|---|---|
| `EmptyState(kind:)` | `ContentUnavailableView` with title "No …", one sentence of what appears here, optional action | Titles and copy from R4.5; same symbol per kind on both platforms (archivebox, clock, arrow.down.circle, photo.on.rectangle, square.on.square); search no-results always `ContentUnavailableView.search` |
| `LoadingState` | Nothing for the first 300 ms; then progress **in place**: the address pill / tab favicon on the Mac, the bar glow on iPhone; a snapshot (unlabelled) where a page will appear | Never a spinner over or instead of content (MW-1, MW-4, MW-2) |
| `PageFailure(kind:)` | One view, three kinds: **unreachable** ("Can't Open This Page", host kept, Try Again), **offline** ("You're Offline", wifi.slash, retries by itself when the network returns), **crashed** ("This Page Stopped Responding", Reload Page) | Shared by DMG, WebKit Mac and iPhone (closes MW-3, MW-5); offline detection with `NWPathMonitor` on the WebKit builds |
| `SyncStatus` | Last synced time (`.relative`), "Syncing…", or an error with a Retry / Open Settings action | Used in Settings › Sync on both platforms (ST-5) and as a quiet line in Tabs on Your Mac |
| `Toast` | One line (two at most), sentence case, Undo when undoable, announced to VoiceOver | Errors map to a short sentence (MS-14) |

Destructive actions (P6): bulk wipes (Clear Archive, Clear History, Delete Space) confirm and can't be undone;
single-item removals (archive a tab, delete a folder) act at once and offer Undo (toast, ⌘Z on the Mac, Shake to
Undo on iPhone). Never both, rarely neither.

## R4.7 Handoff between iPhone and Mac (approved, §7.2)

**Goal.** The page open on one device shows in the other's Dock (Mac) or App Switcher (iPhone); picking it opens the
same page in Boaz on that device, in the right place. Today nothing advertises (`rg NSUserActivity Apps` → 0).

**Pairing.** Handoff pairs apps signed by the same team that declare the same activity type. Both apps use bundle id
`com.chenkahana.boaz` and team `DPF8459C2J` (`project.yml`); the DMG is Developer ID–signed by the same team, so the
DMG, the Mac App Store build and the iPhone app can all take part. Each target declares `NSUserActivityTypes =
[com.chenkahana.boaz.page]` in its Info.plist.

**Advertising (sender).**

| | iPhone | Mac (DMG and App Store) |
|---|---|---|
| Who owns the activity | The focused pane's page (`TabBrowser`) | The key window's active tab (`BrowserState`), both engines |
| Activity | `NSUserActivity(activityType: "com.chenkahana.boaz.page")`, `webpageURL = page URL`, `title = page title`, `isEligibleForHandoff = true`, `isEligibleForSearch = false`, `isEligibleForPublicIndexing = false` | same |
| When | `becomeCurrent()` when a page finishes loading and when the tab or pane gains focus; `resignCurrent()` when the app backgrounds with no page, or on the empty browser | same, on window key / tab switch; `resignCurrent()` when the window closes |
| Never | **Incognito tabs and windows** (no activity at all, not even `invalidate`-later), `file:`, `data:`, `about:`, `chrome:` and `javascript:` URLs, error pages, pages behind HTTP auth prompts | same |
| Fallback | `webpageURL` means a device without Boaz opens the page in its default browser | same |

**Receiving (continuation).**

| | iPhone | Mac |
|---|---|---|
| Entry | `.onContinueUserActivity("com.chenkahana.boaz.page")` in `BoazApp` → `DeepLink`-style handler | `.onContinueUserActivity` on the main scene (WebKit build); `application(_:continue:restorationHandler:)` in the DMG's AppKit delegate |
| Where it lands | A **new tab on top of the fan** (must-have 7: the page comes first), switching out of Incognito if needed (the new tab is a normal tab) | A new tab in the **current space's Today**, in the frontmost main window; if none is open, the main window opens first (must-have 2: never a new window per space) |
| Duplicates | If the same URL is already the active tab, just focus it | Same: focus an existing tab with that URL in the current space instead of adding one |
| Validation | Same scheme allow-list as `boaz://open` (http/https only) | same |

**Must-haves to check in the real app (Chen's devices):** 10 (each side keeps its engine: the iPhone opens the page
in WebKit, the DMG in Chromium); 11 (Handoff carries only the current page of a normal tab; History and Incognito
never leave the device, and no library data is written by advertising); 13 (continuation only adds a tab, never
replaces or reorders the library); 2 and 7 (landing places above).

**Open question for Chen (one line):** a Handoff'd URL travels to the user's own devices through Apple's Handoff
channel, not the iCloud database; we read must-have 11 as allowing that for normal tabs (it's what "the iPhone can open
the Mac's tabs" already does). If that reading is wrong, W7 stops at design.

**Verification for the PR:** two devices on the test Apple Account; open a page on each side and pick it from the
Dock / App Switcher; repeat with Incognito (nothing must appear), with the DMG and the App Store build, and with Boaz
not installed on the receiver (default browser opens it).
