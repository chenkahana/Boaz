# R1. Surface inventory

Every screen, panel, sheet, menu, popover, toast, widget and extension, with its states, how it comes and goes, its
keyboard path and its context menu. Code at 66c3d63. "Shot" points at R0 captures under `~/tmp/codex/boaz-craft/`.
State key: **E** empty, **L** loading, **Er** error, **O** offline, **P** permission, **F** first run, **—** not
designed (no code path found), **n/a** can't occur.

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
| Toast (Tab archived · Undo) | Top, spring 0.35/0.85, medium impact haptic when it can undo | — | VoiceOver announcement not found | — | n/a | `tabs/23,24`; `Chrome.swift:229` |
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
