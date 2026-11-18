# R1. Surface inventory

Every screen, panel, sheet, menu, popover, toast, widget and extension, with its states, how it comes and goes, its
keyboard path and its context menu. Code at 66c3d63. "Shot" points at R0 captures under `~/tmp/codex/boaz-craft/`.
State key: **E** empty, **L** loading, **Er** error, **O** offline, **P** permission, **F** first run, **—** not
designed (no code path found), **n/a** can't occur.

**Summary.** 23 iPhone surfaces, 27 Mac surfaces (8 of them DMG-only and code-read), 8 system surfaces. The patterns
that repeat across them, and feed R2 and R4:

- **Empty states exist almost everywhere, in two voices.** `ContentUnavailableView` titles mix "Archive is empty",
  "No history", "No downloads" (sentence case, iPhone) with "No Tabs", "No Downloads", "No History" (title case, Mac),
  and the Mac Archive window uses "Archive is empty" too. The Mac sidebar has no empty state at all.
- **Loading replaces content** on the Mac ("Opening page…" centred spinner, `WebPane.swift:132`) and is a thin glow on
  iPhone; nothing waits ~300 ms before showing.
- **Offline is not a state** on iPhone or the WebKit Mac build: it shows the generic load error. The DMG has a
  distinct offline message.
- **VoiceOver announcements** exist for toasts on both platforms (`AppModel.swift:1052`, `MacModel.swift:944`, with a
  longer Undo window under VoiceOver) and Mac onboarding; AI completions, downloads finishing and sheet results
  aren't announced.
- **Keyboard**: the Mac has full menu commands; the iPhone has three shortcuts in total.
- **Context menus**: Mac sidebar objects have them; iPhone tab cards and the tab fan don't.
- **System surfaces**: widgets, a share extension and two App Shortcuts on iPhone; nothing on the Mac; no Handoff or
  Spotlight on either.

## R1.1 iPhone

Layout facts that shape every row: one view tree for every posture (`RootView.swift:4`); the bar is a vertical rail
in the Duo's right-hand column when that column is ≥ 44 pt wide, otherwise a bottom bar (`ToolRail.swift:22`). Page
panels ("+" search and "…" page menu) share `BottomPanel` (`BottomPanel.swift`): a 0.18 black scrim over the page
only, glass card 8 pt from the edges, radius 28, slides up from the bottom (opacity under Reduce Motion),
drag-down or tap-scrim to dismiss. Only three hardware-keyboard shortcuts exist in the iPhone app (Cancel/Return in
the popup sheet, password sheet and AI sheets); none for New Tab, Address, Close, Reload or Find.

| Surface | Entry → exit (transition) | States designed | States missing | Keyboard | Context menu | Shot / code |
|---|---|---|---|---|---|---|
| Onboarding (2 pages: iCloud, You're all set) | First launch, full-screen cover → Start Browsing | F; iCloud checking ("Checking your iCloud account..."), signed out, folder-sync fallback | Offline during iCloud check (spinner text only); Dynamic Type clipping flagged by audit | — | n/a | `shots/ios/main/01,02`; `Onboarding/OnboardingView.swift` |
| Empty browser ("No tab open") | No tabs → New Tab | E | — | — | — | `03-empty`; `RootView.swift:356` |
| Page (web view) | Tab open; posture change covered by `RelayoutCover` (snapshot fade) | L (progress glow), Er ("Can't Open This Page", Try Again) | O (offline shows the same generic error), P (camera/mic prompts are WebKit's), blank card while a failed tab reloads | — | WebKit's link/image menus | `06-page`, `11-error-page`; `TabBrowser.swift:197` |
| Rail / bottom bar | Always; tab fan (`TabStack`), **+**, **…** | Tabs value "N open" | — | — | Long-press **…** opens the page menu, not a separate menu | `06-page.txt` (Tabs 34 × 40 pt) |
| Search panel (**+**) | **+** → BottomPanel slide up, keyboard up, field focused; tap scrim / drag down / Return | E (no query: field only), suggestions (engine, open tabs, history), inline completion | Engine error/offline (rows just don't appear), first-run explanation of suggestions | Return opens; no ⌘L | — | `04,05`; `Chrome.swift:7` |
| Page menu (**…**) | BottomPanel, max ½ height; scroll inside | Back/Forward disabled tiles, Website Settings (pop-ups, content blocking), text size, Desktop Website, AI items | Last row cut by the panel edge with no fade; menu has no section titles; Library and Incognito only reachable from the empty browser's Menu | — | n/a | `07,08,26`; `PageSettingsMenu.swift` |
| Tab carousel (deck) | Tap tab fan → deck grows out of the page (custom hero, not `matchedGeometry`), Done or tap card → grows back | E ("No Tabs"), "N Tabs" header, swipe-up archive with Undo toast | Snapshot missing for a failed tab: blank white card, also in Dark | — | — (no long-press menu on cards) | `tabs/21–23`, `tabs-dark/21`; `TabStack.swift:66` |
| Tabs on Your Mac sheet | Carousel rail → sheet | E ("No tabs open on your Mac in this space.") | Sync off / signed out state, loading | — | — | `TabStack.swift:546` |
| Tab strip (Duo half-open) | Posture → strip | — | **Needs device** | — | "Close …" button per row | `TabStrip.swift` |
| Toast (Tab archived · Undo) | Top, spring 0.35/0.85, medium impact haptic when it can undo | Announced to VoiceOver, 10 s Undo under VoiceOver (`AppModel.swift:1052`) | — | — | n/a | `tabs/23,24`; `Chrome.swift:229` |
| Shake to Undo alert | Shake → "Undo Archive Tab?" | — | — | — | n/a | `RootView.swift:348` |
| Library sheet (Archive · History) | Menu › Library → sheet with segmented control, search | E ("Archive is empty", "No history"), search no-results, clear with confirmation dialog | L (none needed), sync-pending | — | Row context menu (Open, Copy Link, Delete) + swipe actions | `13-library`; `LibrarySheet.swift:6` |
| Settings sheet | Menu › Settings or carousel gear → sheet, close X in the rail column | iCloud signed out, default browser set / not set | Sync error, sync in progress | — | — | `14–16`; `LibrarySheet.swift:167` |
| App icon picker | Settings › App icon | Selected check | — | — | — | `16-settings-3`; `Delight/AppIconPicker.swift` |
| Downloads | Page menu › Downloads → sheet | E ("No downloads"), Quick Look preview | L (in-progress download), Er (failed) | — | Swipe: Delete; Share | `Browser/DownloadsView.swift` |
| Reader | Page menu › Reader → sheet | Text size menu, reading time | L, "not available" (item is disabled instead) | — | — | `Browser/ReaderView.swift` |
| Find on Page | Page menu → system find bar | System | — | System | — | `PageSettingsMenu.swift` |
| AI sheets (Summarize, Ask This Page, Tidy Tab Titles) | Page/Home menu → sheet | L ("Getting ready…"), Er, Not Available, Language Not Supported, Not Enough Tabs, Titles Look Tidy | — | Done = Esc | — | `Browser/Intelligence/AIViews.swift` |
| Popup sheet (window.open) | Page → sheet | — | — | Esc cancels | — | `Browser/PagePopups.swift:164` |
| Password autofill / save | Page → top banner (move from top) | — | — | Return saves | — | `Browser/PasswordViews.swift` |
| Incognito | Menu › Incognito; "Private search" placeholder | — | Distinct look (only the placeholder and Leave Incognito change in code) | — | — | `HomeBar.swift:32,78` |
| Landscape status pill | Unfolded landscape | collapsed/expanded | **Needs device** | — | — | `RootView.swift:238` |
| Tips (TipKit) | "Swipe the toolbar to switch tabs" popover over the page | — | Appears over a page that's still loading | — | — | `main/09-second-page` |

## R1.2 Mac

Two builds share one SwiftUI window (`BrowserWindow`): the WebKit build hosts it in a SwiftUI `WindowGroup`; the DMG
hosts the same view in an AppKit `ChromiumAppWindow` (`ChromiumAppWindow.swift:149`) with its own AppKit menu bar
(`ChromiumApplicationMenu.swift`), settings window (`ChromiumSettingsWindow.swift`, toolbar tabs), load-failure view,
tab hover preview, peek and Quick Window. So DMG-only rows below are code-read only (needs Chen session to see).

| Surface | Entry → exit (transition) | States designed | States missing | Keyboard | Context menu | Shot / code |
|---|---|---|---|---|---|---|
| Main window: sidebar | Always; hide/show ⌘S, peek on left-edge hover (move from leading + opacity) | Pinned, Favorites, folders, Today, space title, space dots; drop target outline | **E**: an empty library shows an empty sidebar with only the bottom row (no hint); clipped rows at minimum size with no scroll cue | Rows are not focusable controls (see R2.1) | Tab, folder, space, favorite menus | `shots/mac/mac-light-main.png`, `empty-light-*`, `min-light-*`; `Sidebar.swift` |
| Main window: empty content (space start page) | No tab selected; space switch cross-fade 0.4 s | Space icon + title + search field with ⌘T hint; Incognito start page | — | ⌘T focuses | — | `BrowserWindow.swift:416` |
| Page (WebKit) | Tab selected (scale 0.9 + opacity) | L ("Opening page…" spinner centred, replaces content), Er ("Couldn't Open This Page") | O distinct from Er | ⌘R, ⌘[, ⌘] | WebKit page menus | `WebPane.swift:36,132` |
| Page (DMG) | Same | Er: "Couldn't load", offline ("Check your internet connection"), crashed ("This Page Stopped Responding" + Reload Page) | — | | Chromium page menus (`docs/qa.md` §2) | `ChromiumLoadFailureView.swift` |
| Command bar (⌘T empty, ⌘L current address) | Scale 0.96 from top + opacity; Esc closes | Suggestions with ↑/↓, search, open tabs | Focus lands after up to 10 × 50 ms retries (`CommandBar.swift:126-160`); no "no results" state | ⌘T, ⌘L, ↑/↓, Esc, Return | — | `CommandBar.swift` |
| Find bar | ⌘F; bottom of the page | Match count | No-match state styling | ⌘F, ⌘G?, Esc | — | `WebPane.swift` |
| Split view | View › Add Split View (⌃⇧=); divider drag | Two panes, divider | Snap points / haptic (none) | ⌃⇧= | — | `BrowserWindow.swift:470` |
| Peek (link from a pinned tab) | Overlay over the page | L (spinner) | — | Esc? | — | `BrowserWindow.swift:496`, `ChromiumPeekView.swift` |
| Tab hover preview (DMG) | Hover a sidebar row after a delay (`ChromiumTabPreview.swift:34`) | Snapshot | — | — | — | DMG only |
| Library panel (popover from the sidebar's archive-box button) | Popover, trailing arrow | Media, Downloads (in progress, interrupted), Spaces, Archived Tabs; search; E per pane ("No Media", "No Downloads", "No Spaces") | E for Archived Tabs uses a different string family | Library filter by keyboard (#134) | Downloads: Show in Finder etc. | `LibraryPanel.swift` |
| Archive window / History window | View › Archive ⌥⌘A, History › Show All History ⌘Y | E ("Archive is empty", "No History"/"No Results"), Clear with confirmation | — | ⌘W closes | Row menus | `LibraryViews.swift:8,139` |
| Settings | ⌘, — SwiftUI `Settings` (WebKit) / `NSTabViewController` toolbar window (DMG) | General, App Icon, Privacy, Sync, Passwords, Accounts, Sites, Shortcuts (8 panes) | Sync error state; Passwords locked state | ⌘W | — | `LibraryViews.swift:226` |
| Customize Space (space editor sheet) | Space menu → sheet | Theme, grain, light streak, transparency (#137) | Reduce Transparency preview | Esc/Return | — | `Shared/Spaces/SpaceEditor.swift` |
| Rename sheet | Tab/folder menu → sheet | — | — | Return/Esc | — | `BrowserWindow.swift:614` |
| AI sheet (Summarize, Ask This Page, Tidy Tabs) | View menu / right-click → sheet | L, Er ("Couldn't Read This Page"), Not Available | — | Done = Esc | — | `Intelligence/MacAI.swift`, `Browser/Intelligence/AIViews.swift` |
| Toast (Tab closed · Undo) | Bottom capsule, move from bottom + opacity | Undo with ⌘⇧T hint in tooltip; announced (`MacModel.swift:944`) | — | ⌘⇧T | — | `BrowserWindow.swift:596` |
| Onboarding (Welcome, Bring your browser, Make default, All set) | First launch → sheet; page transition | Arc import progress | — | Return/Esc | — | `Onboarding/OnboardingView.swift` |
| Import (Arc, other browsers) | File menu → sheet | L ("Reading your Arc sidebar…"), progress, result | Er detail | | | `Import/ArcImportView.swift` |
| QR code sheet | Share › QR | "Too Long for a QR Code" | | | | `QRCodeSheet.swift` |
| Extensions manager / confirm / Web Store | Extensions menu → sheets; toolbar actions popover | Working spinner | | | Toolbar action right-click | `Extensions/ExtensionViews.swift`, `Engine/ChromiumExtensionActions.swift` |
| Live folders (GitHub Pull Requests) | Sidebar + menu → New Live Folder | Delete confirmation, repository menus | Signed-out / rate-limited state (code-read: needs runtime) | | Folder menu | `LiveFolders/LiveFolderViews.swift` |
| Site permissions sheet (DMG) | Page asks → AppKit sheet 460 × 360 | | | | | `ChromiumSitePermissions.swift:57` |
| Password suggestions (DMG) | Field focus → suggestions | | | | | `ChromiumPasswordSuggestions.swift` |
| Quick Window | `open -a Boaz <url>`, ⌥⌘N | L | | ⌘W | | `ChromiumQuickWindow.swift` |
| Incognito window | ⇧⌘N | Start page text | Distinct window chrome (only start page text differs in code) | | | `BrowserWindow.swift:429` |
| Developer: Responsive Design Mode, User Agent, Vision Simulator, DevTools window | Develop menu | Emulation pending spinner | | ⌥⌘R, ⌥⌘C, ⌥⌘U | | `Views/DevToolsViews.swift`, `Engine/ChromiumResponsiveBar.swift` |
| Updates | Boaz › Check for Updates… | | Up-to-date / error feedback (code-read) | | | `Updates/Updates.swift` |
| Menu bar | Always | WebKit: File, Edit, View, History, Tabs, Extensions, Spaces, Develop, Window, Help. DMG: Boaz, File, Edit, Passwords, View, History, Tabs, Spaces, Page, Develop, … | Double separators, duplicate Close items, names differ between builds (R2.2/R2.3) | | | `shots/mac/menus-webkit-adhoc.txt`; `ChromiumApplicationMenu.swift` |

## R1.3 Widgets, extensions and system surfaces

| Surface | Platform | States / behavior | Gaps | Code |
|---|---|---|---|---|
| Search widget (small, medium, Lock Screen circular) | iPhone | Small and circular use `widgetURL` (search), medium has a search pill plus favorite tiles as `Link`s; circular has a clear container background and a label | No empty state for medium without favorites (code-read); no Control Center or Lock Screen *control* (`ControlWidget`) | `Extensions/Widgets/BoazSearchWidget.swift:41-130` |
| Share extension | iPhone | Space picker, Pin / Open on iPhone, error text in red, checkmark confirmation (scale + opacity), "Loading…" title | Error copy is raw (`errorMessage`), checkmark has no haptic | `Extensions/ShareExtension/ShareRootView.swift` |
| App Shortcuts: "Search in Boaz", "Open in Boaz" | iPhone | Routed through `DeepLink` | No Mac App Intents; no Focus filter; no Spotlight items | `iOS/Intents/AppIntents.swift` |
| `boaz://` links (`open`, `search`) | iPhone | `simctl openurl` shows the system "Open in 'Boaz'?" prompt first, as for any external caller; `javascript:` must do nothing (`docs/qa.md`) | — | `iOS/Intents/DeepLink.swift`; `shots/ios/links/` |
| Default browser | iPhone, Mac | iPhone: Settings row ("Make Boaz Your Default Browser" / "Boaz is your default browser"); Mac: General › Default browser row and onboarding step | — | `iOS/Views/DefaultBrowserSection.swift`, `LibraryViews.swift:337` |
| Handoff, Spotlight, Services, Dock menu | both | **None.** No `NSUserActivity`, `CSSearchableItem`, Services provider or `applicationDockMenu` in `Apps/` | W7 (Handoff approved, §7.2) | `rg` over `Apps/` returns nothing |
| Mac external opens | Mac | Every scene sets `.handlesExternalEvents(matching: [])`; links go to the Quick Window | — | `BoazMacApp.swift:22-65` |
| Notifications / Live Activities | both | None (downloads finish silently outside the app) | judgment | — |
