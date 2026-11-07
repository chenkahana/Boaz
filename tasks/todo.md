# Folio: plan

**Goal:** an iPhone (Duo-first) and macOS browser that feels like Arc: smooth, playful, spaces-centric. It syncs over CloudKit and imports your Arc setup so the result looks and behaves the same. AI is parked.

**Decided (2026-11-07):** macOS app on WebKit · CloudKit sync · Arc import of spaces, pins, folders, themes, passwords and cookies · project lives in `~/Folio` (git).

## Evidence this plan rests on

- **Arc desktop data (this Mac):** `~/Library/Application Support/Arc/StorableSidebar.json` holds 2 spaces and 227 sidebar items (195 tabs, 24 folders, 8 containers). Item fields: `id, parentID, childrenIds, title, isUnread, createdAt, data.{tab{savedURL, savedTitle, timeLastActiveAt}, list, itemContainer{containerType}}`. Space fields: `id, title, containerIDs, profile, customInfo{iconType, windowTheme}`. Passwords and cookies sit in the Chromium profile under `User Data/Default/` (`Login Data`, `Cookies`), encrypted with the Keychain item "Arc Safe Storage".
- **Themes:** desktop `windowTheme` and mobile `*WindowTheme.json` share one schema (`semanticColorPalette.appearanceBased.{light,dark}`, `primaryColorPalette`, `background`). Imported spaces can therefore use exactly the colors they have in Arc.
- **Arc mobile feel** (from the IPA): tab stack with paging and pan-select gestures, edge-swipe web navigation, a bottom bar that collapses on scroll, spaces that page horizontally on themed backgrounds, shake to undo, auto-archive, haptics (impact, selection, notification, CHHaptics), confetti/sparkle/glow/"hologram" motion-parallax delights, toasts, and alternate icons.
- **Not visible statically:** spring constants and transition timings. These need measuring from screen recordings (see Phase 1).

## Architecture

- One Xcode project (XcodeGen) with targets `Folio-iOS` and `Folio-macOS`, plus a local Swift package **`FolioKit`** for models, store, sync, theme and import. The UI is per-platform; everything else is shared.
- **Store:** GRDB (SQLite), modelled on Arc's tree: `Space`, `SidebarItem(parentID, ordered children, kind)`, `ArchiveItem`, `Profile`. Raw `windowTheme` JSON is kept verbatim.
- **Sync:** `CKSyncEngine` against the private database in a custom zone. URLs and titles go in `encryptedValues`. Per-field last-writer-wins, explicit child-order merging, tombstones. GRDB was chosen over SwiftData+CloudKit because ordered trees and conflict control need explicit handling.
- **Profiles:** each Arc profile maps to a `WKWebsiteDataStore(forIdentifier:)`.

## Phase 0: Foundation ✅ (branch `phase-0/foundation`, uncommitted)
- [x] git init in `~/Folio`. Split into `Apps/iOS`, `Apps/macOS`, `Apps/Shared` (theme and assets) and `Packages/FolioKit`. AI answers are parked behind `FeatureFlags.aiAnswers = false`; search loads the web directly via `SearchInput`.
- [x] FolioKit: `Profile`, `Space`, `SidebarItem`, `ArchiveItem` and `WindowTheme` (Arc schema), with a GRDB store (migration `v1`), a live `sidebarUpdates()` observation, and DEBUG `SampleData` in Arc's shape.

## Phase 1: Mobile experience parity (non-AI). Core slice on branch `phase-1/mobile-core`
- [x] Spaces paging with themed gradient backgrounds (from `windowTheme`) and a space indicator. Favorites grid, pinned list, folders that expand and collapse.
- [x] Tab stack: Today cards with zoom transition into the tab, swipe-to-page on the bottom bar, close (✕, swipe card up, menu) with undo (toast + shake). Pin/unpin. *Still open:* pan-select, page snapshots on cards.
- [x] Web view: edge-swipe back/forward, bottom bar that collapses on scroll, glow progress line; live title/URL saved to the store. *Still open:* custom pull indicator.
- [x] Search field: overlay with suggestions from open and pinned tabs plus history (an address already open as a tab shows only as "switch to tab"). Search-engine choice lives in Settings. *Still open:* top-domains autocomplete.
- [x] Library: auto-archive of Today tabs with an interval setting (12h–30d/never, checked on foreground); Archive and History lists grouped by day, with search, restore, delete and clear. Closed tabs go to the Archive. History is local only (migration `v2-history`).
- [x] Incognito: in-memory tabs on a non-persistent website data store, no history, dark home and bar.
- [ ] Downloads, reader mode.
- [ ] Content blocking (`WKContentRuleList`) and cookie-banner auto-consent.
- [ ] Delight layer: tuned springs and haptics at every snap point, confetti/sparkle moments, alternate app icons.
- [ ] iPhone Duo: unfolded shows spaces sidebar + web (`ArrangementView`); half-open shows web on top and tab controls below; fold glow.
- [ ] Share extension, home and lock-screen widgets, App Intents (open/search), default-browser entitlement.
- [ ] **Feel calibration:** record Arc Search at 120 fps (tab switch, space page, open/close tab, bottom-bar collapse). Measure durations and curves frame by frame, then match the springs.

## Phase 2: Sync
- [ ] `CKSyncEngine` integration and state persistence. Record mapping for Space, SidebarItem, ArchiveItem and theme.
- [ ] Conflicts: concurrent reorder, move into folder, delete versus edit. Tombstone cleanup.
- [ ] Verify between two simulators on one iCloud test account, including an offline edit followed by a merge.

## Phase 3: macOS app
- [ ] Window with the sidebar: spaces swipe, pins grid, today tabs, folders, drag and drop, sidebar hidden/shown.
- [ ] Command bar (⌘T / ⌘L), split view, peek previews, a mini window for external links, auto-archive, theme editor.
- [ ] Keyboard shortcuts matching Arc's defaults, plus overrides read from `StorableKeyBindings.json`.

## Phase 4: Arc import (macOS)
- [ ] Spaces, themes, icons, pins, folders, favorites and ordering → store → synced to the phone automatically.
- [ ] Cookies: read "Arc Safe Storage" (macOS asks the user for approval), decrypt Chromium v10 values, write them to the matching profile's `httpCookieStore`. **Desktop only, never synced.**
- [ ] Passwords: decrypt `Login Data` and store as synchronizable Keychain internet passwords, plus web-form autofill. **Security review before shipping.**
- [ ] Develop and test against a throwaway Arc profile with test logins only. Real credentials are never read during development.

## Open risks
- Whether Folio-stored passwords can appear in Apple Passwords and system AutoFill is unverified. The fallback is Folio's own autofill.
- WebKit cannot run Chrome extensions. Safari web extensions are the substitute.
- Exact "feel" depends on the Phase 1 recordings.

## Review

**Phase 0 (2026-11-07)**
- Verified: `Folio-iOS` and `Folio-macOS` both build (Xcode 27.2). The macOS app launched and created `~/Library/Application Support/Folio/folio.sqlite` with migration `v1`, 2 spaces with theme JSON, 5 containers, 2 folders and 11 tabs. On the iPhone Duo simulator, typing `swift.org` opened `https://swift.org`.
- Not verified: how the macOS window renders (no accessibility or screen permission to inspect it), and the unfolded Duo layouts (the simulator has no hinge control).
**Phase 1, core slice (2026-11-07)**
- Verified on the iPhone Duo simulator (folded): the home screen renders both spaces on their own gradients; swiping changes space; tapping a card zooms into the tab; GitHub loaded; a bar swipe paged to the next tab; titles saved back to the cards; ✕ closed a tab with a toast and Undo restored it; search suggestions matched open tabs. Both apps build.
- Bug fixed during verification: `page(for:)` mutated observed state while rendering, causing an endless re-render loop that froze the app. The page cache is now `@ObservationIgnored`.
- Not verified: bar collapse on scroll, shake-to-undo, pin/unpin, and the unfolded/half-open Duo layouts (the simulator has no hinge control).
- AI prototype files were removed (recoverable from `675f224`).

- Carry into later phases: the macOS sandbox blocks reading `~/Library/Application Support/Arc`. Phase 4 needs a user-chosen folder grant or a non-sandboxed build. `position` is a Double; add rebalancing when sync lands.

**Phase 1, Library slice (2026-11-07)**
- Verified on the Duo simulator (folded):
  - A tab backdated by 3 days was auto-archived on launch.
  - The Library shows it under "Today", and tapping it re-opened the tab after the sheet closed.
  - Visits are written to `historyVisit` and suggested in search.
  - The Incognito page loaded example.com with no `historyVisit` or `sidebarItem` rows, and its private tabs were gone after relaunch.
  - The Settings sheet renders.
- Bugs fixed during verification:
  - Restore didn't open the tab (cover vs. dismissing sheet); it now opens from the sheet's `onDismiss`.
  - Day headers read "11 hours ago".
  - Restored tabs recorded no visit.
  - History duplicated open-tab suggestions.
  - The incognito gradient ended light (Indigo12 under dark scheme).
  - Space dots showed in incognito.
  - Home content ran under the cover screen's sensor column; content now respects the safe area while one full-bleed backdrop cross-fades between spaces.
- Not verified: changing the archive interval or search engine and seeing it take effect; the Library on the unfolded layout.
