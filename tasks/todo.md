# Folio: plan

**Goal:** an iPhone (Duo-first) and macOS browser that feels like Arc: smooth, playful, spaces-centric. It syncs over CloudKit and imports your Arc setup so the result looks and behaves the same. AI is parked.

**Decided (2026-11-07):** macOS app on WebKit · CloudKit sync · Arc import of spaces, pins, folders, themes, passwords and cookies · project lives in `~/Folio` (git).

## Evidence this plan rests on

- **Arc desktop data (this Mac):** (re-derived 2026-11-07: sidebar items live in `sidebar.containers[1]` as alternating id/object arrays; favorites are per-profile, per-Mac `topApps` containers; folder expansion is in `StorableWindows.json`; dates are seconds since 2001; now 228 items / 196 tabs) `~/Library/Application Support/Arc/StorableSidebar.json` holds 2 spaces and 227 sidebar items (195 tabs, 24 folders, 8 containers). Item fields: `id, parentID, childrenIds, title, isUnread, createdAt, data.{tab{savedURL, savedTitle, timeLastActiveAt}, list, itemContainer{containerType}}`. Space fields: `id, title, containerIDs, profile, customInfo{iconType, windowTheme}`. Passwords and cookies sit in the Chromium profile under `User Data/Default/` (`Login Data`, `Cookies`), encrypted with the Keychain item "Arc Safe Storage".
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
- [x] Tab stack: Today cards with zoom transition into the tab, swipe-to-page on the bottom bar, close (✕, swipe card up, menu) with undo (toast + shake). Pin/unpin. Pan-select (hold, drag across cards, release to open) and page snapshots on cards.
- [x] Web view: edge-swipe back/forward, bottom bar that collapses on scroll, glow progress line; live title/URL saved to the store. Custom pull-to-refresh indicator (not exercised live).
- [x] Search field: overlay with suggestions from open and pinned tabs plus history (an address already open as a tab shows only as "switch to tab"). Search-engine choice lives in Settings. Inline domain completion from history hosts and ~115 top domains.
- [x] Library: auto-archive of Today tabs with an interval setting (12h–30d/never, checked on foreground); Archive and History lists grouped by day, with search, restore, delete and clear. Closed tabs go to the Archive. History is local only (migration `v2-history`).
- [x] Incognito: in-memory tabs on a non-persistent website data store, no history, dark home and bar.
- [x] Downloads (non-renderable responses saved to Documents/Downloads, list/preview/share) and reader mode (own extractor, serif reader view).
- [x] Content blocking (`WKContentRuleList`, ~250 domains, compiles and attaches; live request blocking not proven) and cookie-banner hiding/reject script. *Gap:* The Guardian's Sourcepoint banner is not hidden.
- [x] Delight layer: springs and haptics at snap points, confetti (first pin, Clear Archive), favorite sparkle, alternate icons Peach/Electric/Violet/Midnight.
- [x] iPhone Duo (verified folded and unfolded using DeviceHub's hinge slider; half-open not yet checked): unfolded shows spaces sidebar + web (`ArrangementView`); half-open shows web on top and tab controls below; fold glow.
- [x] Share extension, home and lock-screen widgets, App Intents (open/search), `folio://` deep links, App Group database. *Open:* `com.apple.developer.web-browser` needs Apple's approval; the share sheet and adding a widget weren't run live.
- [ ] **Feel calibration:** record Arc Search at 120 fps (tab switch, space page, open/close tab, bottom-bar collapse). Measure durations and curves frame by frame, then match the springs.

## Phase 2: Sync
- [x] `CKSyncEngine` integration and state persistence. Record mapping for Space, SidebarItem, ArchiveItem and theme.
- [x] Conflicts: concurrent reorder, move into folder, delete versus edit. Tombstone cleanup.
- [x] **Transport switched to an iCloud Drive folder** (user decision, 2026-11-07: free team, app is for personal use). Each device writes its own append-only logs plus a snapshot; merges per field. Verified between the Mac app and an iOS simulator through a shared folder. CloudKit code is parked in `Sync/CloudKitSync.swift`.

## Phase 3: macOS app
- [x] Window with the sidebar: spaces swipe, pins grid, today tabs, folders, drag and drop, sidebar hidden/shown.
- [x] Command bar (⌘T / ⌘L), split view, peek previews, a mini window for external links, auto-archive, theme editor.
- [x] Keyboard shortcuts matching Arc's defaults, plus overrides read from `StorableKeyBindings.json`.

## Phase 4: Arc import (macOS)
- [x] Spaces, themes, icons, pins, folders, favorites and ordering → store → synced to the phone automatically.
- [~] Cookies (code done; decryption verified on synthetic vectors only): read "Arc Safe Storage" (macOS asks the user for approval), decrypt Chromium v10 values, write them to the matching profile's `httpCookieStore`. **Desktop only, never synced.**
- [~] Passwords (code done; Keychain write never run): decrypt `Login Data` and store as synchronizable Keychain internet passwords, plus web-form autofill. **Security review before shipping.**
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

**One-swing pass: rest of Phase 1, plus Phases 2–4 (2026-11-07)**

Work was split across six parallel helpers with separate file ownership, then integrated: sync starts in both apps and re-syncs on foreground; the Mac app gets the bookmark entitlement and http/https URL types so it can be the default browser.

Verified:
- Both apps build from the integrated tree.
- iOS launches on the Duo simulator. Migrations `v1`, `v2-history` and `v3-sync` ran, and 27 changes are queued for upload in `syncPending`. The Mac app launches with the same migrations.
- iOS, per helper (simulator screenshots, database rows):
  - Reader mode on Wikipedia.
  - A zip download, saved and listed.
  - Snapshots on cards; pan-select; domain completion.
  - Confetti; alternate icon switch.
  - `folio://` open, search and focus links.
  - The database is in the App Group container.
- Sync, offline harness (59/59):
  - Record mapping, with URLs and titles only in `encryptedValues`.
  - Triggers queue local writes and skip server-applied ones.
  - Conflicts: last-writer-wins, per-field merge, delete vs. edit, reorder ties, moves.
  - Tombstone purge; rebalancing.
  - With no entitlement it reports `unavailable`; with the entitlement but no account, `noAccount`.
- Mac, scripted run with screenshots and database rows:
  - Sidebar; command bar; split view (a crash was fixed); peek; pin/unpin.
  - Close to the archive; theme editor; incognito window.
  - Little Folio for external links.
- Arc import harness, on a copy of the real sidebar:
  - 2 spaces, 24 folders and 189 tabs. The other 7 are favorites from another Mac and one `arc:` URL.
  - Order preserved; re-import is idempotent.
  - Chromium decryption verified on synthetic vectors only.

Not verified:
- Live CloudKit (needs a paid team).
- Mac keyboard shortcuts, trackpad swipe and drag and drop (macOS blocked automated input).
- The import sheet UI, cookie install into WebKit, and the Keychain password write (never run, on purpose).
- The share sheet and adding a widget live; the pull indicator and haptics on a device.
- Duo unfolded and half-open postures.
- Live tracker blocking.

To enable sync once a paid team exists (in `project.yml`): add to both apps `com.apple.developer.icloud-services: [CloudKit]`, `com.apple.developer.icloud-container-identifiers: [iCloud.com.example.folio]`, aps-environment (iOS `aps-environment`, macOS `com.apple.developer.aps-environment`) and `DEVELOPMENT_TEAM`; on iOS also `INFOPLIST_KEY_UIBackgroundModes: remote-notification`. Then create the container in the developer portal, and deploy the schema to Production before shipping.

Security review before shipping import:
- The Arc Keychain key is only read from the Import button and is kept in memory only.
- Cookie and Login Data databases are copied to a 0700 temp folder that is deleted afterwards.
- Cookies go only to WebKit, so they are never synced.
- Passwords are saved as synchronizable internet passwords. Writing them likely needs `keychain-access-groups` and team signing.
- Re-import overwrites local edits to rows that came from Arc.

**Fold, toolbar rail and folder sync (2026-11-07)**
- **Fold:** DeviceHub's hinge slider drives the simulator's hinge; there is no `simctl`/`devicectl` command for it.
  - Unfolding with a tab open crashed (WebKit traps when two WebViews show one WebPage while the layouts swap).
  - Fixed with page ownership: `AppModel.claimPage`/`releasePage`. The new host waits until the old WebView is gone and shows the snapshot meanwhile.
  - The user folded and unfolded repeatedly afterwards; no new crash reports.
- **Download-only tabs:** a Today or private tab whose only navigation became a download is now removed. Before, it re-downloaded every time it was opened.
- **Toolbar rail:** the toolbar moved into the right-hand column (`ToolRail.swift`), below the camera/status cluster, using the `.occlusion` reserved region (on the cover screen: x 382–466, y 0–170).
  - Home and browser bars run vertically there; swiping up or down on the rail pages tabs.
  - Unfolded, the right pane's rail also carries the home controls.
  - Falls back to a bottom bar on screens without the column.
  - Verified on the cover screen; the unfolded rail is not checked yet.
- **Folder sync:**
  - Mac and iPhone pick the same iCloud Drive folder once (Settings ▸ Sync ▸ Choose Sync Folder…).
  - Verified with the real apps through a shared local folder: bootstrap, two rounds of edits on both sides, concurrent edits, and a third fresh device; full-table hashes matched.
  - Offline harness: 27/27.
  - Not verified: a real iCloud Drive folder and placeholders, the pickers and bookmarks after relaunch, and iOS background refresh.
  - The dev databases (Mac app, Folio Duo simulator) still hold sync test rows ("Created on Mac/iPhone", …).
- **Free team on a real iPhone:** a self-installed build stops launching after 7 days and needs reinstalling from Xcode.

### Toolbar rail v2 (2026-11-07)
- [x] Rail = two Liquid Glass docks (site/back/reload up top; new tab/tabs+badge/menu at thumb height) in a `GlassEffectContainer`
- [x] Collapse: scrolling down melts the top dock into a nub (`glassEffectID` morph), bottom dock dissolves; soft haptic; Reduce Motion → plain fade
- [x] Pop back: scroll up / near top / navigate / tap nub / tap or pull anywhere in the empty column
- [x] Tuck by hand: swipe the rail toward the edge, or ⋯ → Hide Toolbar (stays tucked until pulled back)
- [x] Site tile with live loading ring + lock; back button (hold for history); copy-link context menu; tab-count badge
- [x] Fix: `WebView` never reported scroll to `onScrollGeometryChange` → use `webViewOnScrollGeometryChange` (also fixes pull-to-refresh)
- [x] Fix: rail modifier rebuilt its content when insets were measured, stranding the page on its snapshot
- Verified in sim: cover screen (home + browser) and unfolded right pane; half-open (desk) not checked

### Mac daily driver (2026-11-07)
- [x] Arc sidebar import dry-run on real data: 2 spaces, 3 profiles, 24 folders, 16 favorites, 171 pinned, 2 unpinned; re-import idempotent
- [x] External links (default browser) open in Little Folio — verified with `open -a`
- [x] Downloads: non-displayable / attachment / `<a download>` responses → ~/Downloads with page cookies, toast + Dock bounce (verified with a real zip)
- [x] JS alert/confirm/prompt sheets + `<input type=file>` picker (built; not exercised at runtime)
- [x] Security review of credential import. Passwords: NO-SHIP → option removed from the UI (no autofill consumer; likely -34018 on Personal Team). Cookies: fixed local-machine profile filter, skip CHIPS-partitioned rows, Network/Cookies path, "Allow not Always Allow" copy, read-only Arc bookmark, reject unknown vNN blobs
- [ ] Install a Release build in /Applications and set it as default browser (System Settings → Desktop & Dock)
- [ ] Password autofill in Folio pages (prerequisite for password import)
- [ ] Open security-review lows: path in Keychain dup lookup, sweep tmp/folio-arc-* at launch, redacted Login description

### Ad blocking (2026-11-07)
- [x] EasyList (WebKit build, `easylist_min_content_blocker.json`, May 2025, 27.6k rules) bundled in Apps/Browser with Folio's own tracker list; on by default on Mac and iOS ("Block ads and trackers" in Settings)
- [x] Compiled once per bundled version (`ContentBlocking.easyListVersion`), then loaded from WebKit's store
- [x] Cleans the published list before compiling: 11 selectors WebKit can't parse, and an exception with an empty-domain site pattern that switched off all earlier rules on every site
- [x] Removed site-breaking hosts from Folio's list (t.co, licdn.com, gravatar.com, disqus.com, intercomcdn.com)
- Verified on Mac with a local probe page: ad script, EasyList-only ad host and analytics blocked; EasyList element hiding applied. iOS: builds; not run (iOS 27.1 simulators are gone)
- Pages opened in the first seconds of the very first launch (while EasyList compiles) aren't blocked until reloaded

## Production polish pass (2026-11-07)
Audit findings → slices (parallel, one owner each):
- [x] A. Pinned/favorite tabs stay anchored to their saved URL (both apps); live URL in memory; "back to pinned page"; active highlight in iOS pinned list — orchestrator
- [x] B. Site color: read page theme color, tint Mac sidebar + iOS rail/home chrome — agent
- [x] C. Real favicons replace monograms (shared cache, both apps) — agent
- [x] D. First-run onboarding: Mac (Arc / Chromium / bookmarks-HTML import, sync folder, default browser), iOS (sync folder, default browser); no sample data for real users — agent
- [~] E. Detail pass: Mac empty state, iOS empty home, onboarding icon mask, Little Folio/Incognito no longer restore on launch. RTL titles + full animation sweep still open (needs interactive sim)
- [x] F. Review (opus): M1 importer tombstoning scoped (export files never delete; folders holding user tabs kept), M2 starter records stamped epoch + no Personal removal while syncing + no favorite revival, M3 history keeps page titles, M4 redirect-aware wander check, favicons https-only + learned once + isolated JS world. Both apps + FolioKit build clean.

### Review — polish pass
- Verified: Mac + iOS + FolioKit builds; Mac screenshots (empty state, onboarding pages, site tint per agent shots); iOS cover-screen first run + empty home via simctl screenshots; window restore fix via launch with persistence ignored.
- Not verified (no sim panel access / no synthetic clicks): tapping through iOS onboarding, pinned "back" button flow, iOS site tint on device, unfolded layout; importer re-run after the M1 change.

### Device pass on Duo simulator (2026-11-07)
- Verified by tapping: iOS onboarding (welcome → sync → done, starter favorites), site tint (teal→gold fade, docks + column), pinned anchor (title kept, back arrow, return, arrow clears), favicons, unfolded split + active pinned highlight.
- Fixed: sync card contrast; removed iOS default-browser step (needs com.apple.developer.web-browser entitlement); column site wash; low-res favicons no longer stretched; Today→empty transition; unfolded empty browser pane restyled.
- Open: unfolded only — WebKit insets page content by the sensor column width, leaving a page-colored strip before the column (no SwiftUI WebView API to change it; hiding content background would bleed site color through background-less pages). Half-open posture unchecked.
- Unfolded layout reworked (user: "the side bar should always appear"): flat-open Duo now shows an Arc-style 300pt sidebar (space title, search, favorites, pinned, divider, New Tab + Today rows with close) beside the full-width browser; half-open keeps the browser/controls split. Verified on the simulator: sidebar stays while a tab opens and loads; new tab appears as an active row with its favicon.

### Unfolded sidebar collapse (2026-11-07)
- [x] Sidebar hides/shows: `sidebar.left` button in the sidebar header, and in the rail (replaces Tabs on the unfolded layout; desk posture keeps Tabs). State persisted in `@AppStorage("sidebarCollapsed")`.
- [x] Verified on the simulator: collapse from the header, reveal from the rail, collapse from the rail with apple.com open, state survives relaunch.
- Note: `.clipped()` on the HStack clipped the rail column and bottom strip out of view; removed.

## Award pass (2026-11-08) — full task list

Research basis: Safari 27.1 on iPhone Duo (bottom bar when folded; flat-open moves tabs to the top like iPad;
book pose runs two windows side by side), Chrome on Galaxy Fold (phone grid folded, tablet tab strip unfolded;
Flex mode reorients UI to the upper half), Arc (sidebar is the browser; hides on demand; floats over the page
when peeked).

### A. iPhone Duo postures (iOS)
- [x] Folded (cover): home with spaces; tab zooms out of its card; rail/bottom bar. (existing)
- [x] Flat, landscape (≥820pt): Arc sidebar inline, hide/show from header or rail; state persists.
- [x] Flat, portrait (<820pt): page full width; sidebar floats over it as a card (scrim, tap-out, closes on pick).
- [x] Bottom bar / rail "Tabs" button becomes the sidebar toggle wherever a sidebar exists.
- [x] Portrait: page starts below the status cluster instead of under it.
- [x] Book pose (half-open, fold top-to-bottom): sidebar fills the left half to the fold, page on the right.
- [x] Laptop pose (half-open, fold across): page on top, controls below (dark-mode fixed).
- [ ] Verify book and laptop poses on the Half-Open simulator (needs the hinge slider set by Chen).
- [~] Verify folded flow on the Folded simulator: fresh onboarding renders on the cover screen (simctl); stepping
      through needs Chen to approve the Folded simulator for the iOS-simulator tool.
- [ ] Transitions: fold ↔ unfold keeps the page (no reload), sidebar animates width.

### B. iCloud sync (agent)
- [x] CloudKit (CKSyncEngine) as primary transport, container iCloud.com.chenkahana.folio, entitlements + push.
- [x] Folder transport only as fallback; automatic migration; empty device joins library without duplicates.
- [x] Settings + onboarding: live iCloud status, Sync Now; no folder picking when iCloud works.
- [ ] Owner step: Mac App ID ↔ container link (server says "Invalid bundle ID for container"); sign in to
      iCloud on simulators/devices; verify two-device round trip. See tasks/sync-report.md.

### C. Arc import "as is" (agent)
- [x] Fidelity measured against real Arc data (aggregates only): spaces/order/icons/themes/favorites/pinned tree/
      folder expansion/today tabs/custom titles/profiles.
- [x] Close gaps; Arc theme → space gradient on both platforms.
- [x] Delightful Mac import UI with preview and completion (built; not yet clicked through).

### D. Mac from scratch
- [~] Quit Folio, moved library aside (backup: ~/tmp/codex/folio-mac-backup-20261108), relaunched with onboarding
      reset: one window, Welcome sheet shows. Walking Import Arc → iCloud → Done needs Chen's clicks.
- [ ] Every window type opens and restores sanely; no stray windows.

### E. Review
- [x] Independent code review of the diff (bugs, security, sync data loss) → tasks/review-round2.md (0 C / 4 M / 12 m).
- [x] Duo layout m9–m12: page keeps one structural position in every pose (laptop no longer rebuilds TabBrowser);
      book pose page starts past the crease; card resets on pose change and closes when any row is picked
      (verified: re-tapping the active tab closes the card; open card doesn't survive portrait→landscape→portrait);
      VoiceOver labels for space dots, bottom-bar Reload/Stop, favorite tiles, card close; floating card is modal.
- [x] Sync fixes M1, M2, M4, m1–m6; follow-up review round 3 (1 HIGH, 4 MED new) fixed — see tasks/review-round3.md.
- [x] Arc re-import fixes M3, m7, m8 (+ N3–N5).
- [x] Fix findings, final builds of both apps (iOS sim + macOS BUILD SUCCEEDED).
- [x] Fresh Mac: Welcome shows within ~3 s on an empty library (was ~10 s behind the first iCloud fetch).
- [x] Pull to refresh and rail collapse share one web-view scroll observer (verified: pull → WebPageProxy::reload;
      scroll down → rail collapses to nub).
- [x] Flat landscape with no tab: sidebar stays visible and its hide control is withheld (verified).

### F. Stress pass ("make it bullet proof", 2026-11-08)
- [x] iOS deep links: `folio://open` accepted any scheme → now http/https with a host only (javascript:, file:,
      tel:, empty, %00 and 60 KB URLs create no tab; app survives).
- [x] iOS: rows written by the share extension while away appear on return (reloadSidebar on .active; 210 → 213).
- [x] iOS folded grid: upward flick on a card closed the tab → swipe-to-close removed.
- [x] iOS folded grid: swipes starting on a card didn't scroll (SwiftUI hold-then-slide gesture held the touch).
      Pan-select removed: SwiftUI holds any other recognizer behind the card's button until touch-up, so a hold
      can't win without breaking scroll or tap (tried grid-level, in-label and UIKit scroll-view recognizers).
      Hold → context menu (Pin / Close) remains. Verified: scroll from a card, tap opens, 4 rapid open→home cycles.
- [x] iOS: 214 tabs render and scroll; 7 rapid rotations with a page loaded; no crash reports.
- [x] Mac cold launch with links (default browser, Folio not running) opened NOTHING: no window, links queued
      forever. openWindow is now registered from the menu commands, which exist without a window.
      Verified: 25 links → 25 Little Folio windows; javascript:/file:/folio:/data: and host-less URLs dropped.
- [x] Mac: 8× kill -9 / relaunch → integrity_check ok, no crash reports. Library restored to pre-stress state.
- [x] FolioKit harness (DB / sync / Arc fuzz): 13 bugs fixed (2 crashes, unreadable-library dates, 3 sync wedges, 2 data-loss, Arc re-import churn); all scenarios pass. See tasks/stress-report.md.
- [x] Final builds: iOS sim + macOS BUILD SUCCEEDED; diagnostic logging and harness removed.
- [x] Main-actor work over 50 ms at 20k items now runs on GRDB's database queue (async `writer.write`/`read`):
      applyServerChanges (iCloud fetch batches and conflicts), purgeTombstones, archiveStaleTabs, and a new
      `loadSidebar()` used by the Arc import view, the share extension and iOS `reloadSidebar` (which drops its
      snapshot if the live observation delivered a newer one meanwhile). Verified: 3,000 stale tabs archived at
      launch with the UI up, integrity ok; a row written while backgrounded appears on return; both apps build.

### G. App Store readiness (2026-11-08)
- [x] Mac bundle ID `com.example.folio.mac` → `com.chenkahana.folio` (universal purchase with iPhone). Fixed the
      "Invalid bundle ID for container" iCloud error: the Mac debug build fetched 29 records from iCloud.
- [x] Version 1.0 (1) from build settings in every bundle; `ITSAppUsesNonExemptEncryption = NO`.
- [x] Privacy manifest in app, share extension and widgets (no tracking, no data collected, required reasons).
- [x] iOS camera / microphone / location purpose strings (websites can ask; camera file uploads would crash without).
- [x] Password importer excluded from the build; Arc shortcuts panel opens in the real home, not the container.
- [x] Settings › About: privacy policy, support, EasyList (CC BY-SA 3.0) and GRDB (MIT) notices.
- [x] Standard iPhone (iOS 26.4 test build with the Duo-only APIs stubbed; not shipped): pages with a fixed header
      ran under the status bar → page now inset whenever the status bar is across the top. Duo cover screen unchanged.
- [x] Release archives + App Store exports: iOS ipa (production push/iCloud, no get-task-allow), Mac pkg (Apple
      Distribution + Mac installer cert, production). In build/archives (not committed).
- [x] docs/privacy.md, docs/app-store.md (listing, review notes, privacy answers, owner checklist), screenshots
      (iPhone 6.9" 1320×2868 ×5, Mac 1440×900 ×2) in docs/screenshots.
- [ ] Owner: deploy CloudKit schema to Production; create the App Store Connect record; upload; submit.
