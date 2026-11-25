RESUME HERE (2026-11-25 08:30 IST): released v0.4.38–v0.4.44 (#168–#173, #175). #78 slice 1 = v0.4.44 (PR #175, published 2026-11-25 06:25:17Z = 08:25 IST). Next risky: #78 slice 2 (craft/snapshots-3, master merged in aa6aa99; host ABI 57 + Swift, cap 20; base not uploaded yet) eligible ≥ 2026-11-26 08:25 IST after 0.4.44's soak checks AND ≥ 24 h after the GPU-crash-loop release from another session (patch 52, boaz-dump-will-be-check.patch; time TBD from team-lead). Before its PR: merge master into craft/snapshots-3, rebuild and re-stage the base (52 patches + ABI 57 host); don't touch /Volumes/BoazBuild until that session is done; upload the base (chromium-base.py pack --upload) at its PR. Known pre-existing: iCloud rejects a live folder's `liveSource` (not in the production CloudKit schema) since 2026-11-24 21:54 IST; Chen approved deploying the schema to Production (team-lead, 2026-11-25), no code change — confirm the errors stop at slice 2's soak check.

# Implementation

Chen approved implementation on 2026-11-18: build the R5 backlog items that don't need his yes, Wave A first, then
Wave B. One visible change per PR, each its own patch release. Items marked "waiting" touch a must-have or change
behaviour and wait for Chen's yes (R5.3 "Chen's yes" column).

## Wave A

- [x] #1 iPhone carousel header: "N Tabs" and Done never overlap at AX sizes (AX-8) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #2 iPhone rail: one 48 pt control size (IB-2, IB-9) — polish PR https://github.com/chenkahana/Boaz/pull/168 — v0.4.38
- [x] #3 DMG: page-load progress in the address pill (MW-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — v0.4.38
- [x] #4 Motion tokens, Reduce Motion inside the token (SY-1) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #5 Mac: the 14 model springs fade under Reduce Motion (AX-12) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #6 Mac command bar: selection follows pointer movement (MC-1) — PR https://github.com/chenkahana/Boaz/pull/151 — v0.4.30 (released v0.4.30)
- [x] #7 Mac toast UI test waits for the toast (AX-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — v0.4.38
- [x] #8 iPhone search field: 44 pt Clear Text button (IS-1) — PR https://github.com/chenkahana/Boaz/pull/149 — v0.4.28 (iPhone; shipped in release v0.4.30)
- [x] #9 Mac peek and sidebar: three one-off curves become tokens (MS-6) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #10 iPhone search panel: captions wrap by word at AX sizes (AX-10) — PR https://github.com/chenkahana/Boaz/pull/150 — v0.4.29 (iPhone; shipped in release v0.4.30)
- [x] #11 Duo half-open strip: 44 pt rows and close buttons (DU-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — v0.4.38
- [x] #12 iPhone carousel: a failed tab gets a designed card (IB-3) — PR https://github.com/chenkahana/Boaz/pull/148 — v0.4.27 (iPhone; shipped in release v0.4.30)
- [x] #13 iPhone page menu ends on an edge fade (IM-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — v0.4.38
- [x] #14 Mac library panel: tab labels at a readable size (ML-1) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #15 Mac sidebar: dragging a tab out gives its URL (MS-1) — PR https://github.com/chenkahana/Boaz/pull/153 — v0.4.31 (in release v0.4.34)
- [x] #16 DMG windows titled after their page (MS-13) — polish PR https://github.com/chenkahana/Boaz/pull/168 — v0.4.38
- [ ] #17 Restored tab: no "Saved preview" caption (MW-2) (waiting: Chen's yes, MH 13; folds into #78)
- [x] #18 Mac: unloaded tab keeps its snapshot (MW-4) — engine PR https://github.com/chenkahana/Boaz/pull/172 — v0.4.40
- [-] #19 Mac WebKit find bar without Replace (MW-9) — skipped: SwiftUI `WebPage` has no find API; a JS find would lose native match highlighting and count (Mac App Store build only)

## Wave B

- [x] #20 `Haptics` enum and haptic map (SY-2) — PR https://github.com/chenkahana/Boaz/pull/154 — v0.4.32 (in release v0.4.34)
- [x] #21 iPhone archive swipe: haptic at the commit threshold (IB-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #22 iPhone archive flick keeps the finger's speed (IB-5) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #23 iPhone page menu: drag-to-dismiss keeps velocity (IM-3) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #24 Mac trackpad haptics at sidebar limits, folder crossings and split snaps (MS-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #25 Type ramp tokens (SY-3) — PR https://github.com/chenkahana/Boaz/pull/155 — v0.4.33 (in release v0.4.34)
- [x] #26 iPhone page menu usable at AX5 (AX-9) — polish PR https://github.com/chenkahana/Boaz/pull/168 — v0.4.38
- [x] #27 Mac sidebar glyphs and command bar follow Settings › Sidebar text size (MS-7, MC-5) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #28 iPhone: page-menu tiles, onboarding button and Settings title scale with Dynamic Type (IM-4, OB-3, AX-11) — PR https://github.com/chenkahana/Boaz/pull/157 — v0.4.35 (iPhone; ships with v0.4.36)
- [x] #29 Spacing and radius tokens (SY-4) — PR https://github.com/chenkahana/Boaz/pull/156 — v0.4.34
- [x] #30 Mac: concentric card and panel corners from the radius scale (MS-10, ML-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [-] #31 State kit components (SY-5) — folded into the items that use each piece (no component ships without a caller); `PageFailureKind` came with #36
- [x] #32 English String Catalog, glossary and copy lint (SY-6) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36

## Wave C

- [x] #33 Search suggestions say what each row does (AX-4, MC-6) — PR https://github.com/chenkahana/Boaz/pull/169 — v0.4.39
- [x] #34 One name for the Archive, one empty-state voice (ML-3) — PR #169 — v0.4.39
- [x] #35 iPhone: reopened failed tab shows its failure at once (IB-8) — PR #169 — v0.4.39
- [x] #36 One load-failure page (MW-3, MW-5) — WebKit builds PR #169 v0.4.39; DMG view PR #172 v0.4.40
- [x] #37 Settings title case, no doubled "After" (ST-1, ST-2) — PR #169 v0.4.39; find bar (MW-6) PR #172 v0.4.40
- [x] #38 iPhone search: offline hint; empty state hidden behind the panel (IS-4, IS-2) — PR #169 — v0.4.39
- [x] #39 Swipe-toolbar tip waits for the page (IB-7) — PR #169 — v0.4.39
- [x] #40 Duo status pill `.percent` (DU-3) — already in 0.4.36 (#32)
- [x] #41 Plain-language errors (MS-14, WX-4) — PR #169 — v0.4.39
- [x] #42 Mac empty space New Tab row (MS-8) — already on master: the sidebar always shows New Tab, the page area a search hint
- [x] #43 One iCloud sign-in message (OB-5, ST-3) — PR #169 — v0.4.39
- [x] #45 Share extension labels (WX-5) — PR #169 — v0.4.39

## Wave C, batch 2 — PR https://github.com/chenkahana/Boaz/pull/170 — v0.4.41

- [x] #48 Split: holds at 50 %, double-click evens, slider to VoiceOver (MW-7)
- [x] #49 Split divider visible at rest (MS-12)
- [x] #50 Folders spring open during a drag (MS-11)
- [x] #51 Library panel ⌘1–⌘4, ⌘↑/⌘↓ (ML-5)
- [x] #54 Rubber band at sidebar/split limits (MS-5)
- [x] #56 Short window: Library panel fits, Today list fades (ML-2, MS-9)
- [x] #57 Materials: DMG split header focus tint, command bar solid under Reduce Transparency (MW-8, MC-4); DU-4 device check only
- [x] #64 Setup pages swipe (OB-4)
- [x] #67 Sidebar rows: VoiceOver custom actions (MS-3)
- [x] #68 Rail/bar Large Content Viewer + Voice Control names (AX-6, AX-7); AX-2 (iPhone UI-test hit areas) not done, test infra only
- [x] #71 Failed card spoken state (AX-3); OB-1 already fixed

## Wave C batch 3 + Wave D polish — PR https://github.com/chenkahana/Boaz/pull/171 — v0.4.42

- [x] #60 Carousel card context menu (IB-6)
- [x] #61 Tab fan long-press menu (IB-10); … long-press unchanged
- [x] #63 ⌘T / ⌘L with a hardware keyboard (IS-3); arrow keys through suggestions not done
- [x] #69 Reduce Transparency: solid space theme (AX-13); Increase Contrast: search highlight and page-menu fills (AX-14)
- [x] #58 Page menu groups captioned "This Tab" and "Boaz" (IM-2)
- [x] #70 Mac sidebar Pinned/Today rotors (AX-5)
- [x] #73 Widget favicons from the App Group (WX-3)
- [x] #74 iPhone Incognito look (IB-1) — Duo simulator checked
- [x] #76 Spotlight: pinned tabs + favorites, iPhone only (WX-1)
- [x] #77 Control Center / Lock Screen New Tab control (WX-2)

## Engine batch (risky) — PR https://github.com/chenkahana/Boaz/pull/172 — v0.4.40 (published 2026-11-24 04:41Z)

- [x] #18 unloaded tab keeps its snapshot (MW-4)
- [x] #37 DMG find bar title case (MW-6)
- [x] #36 DMG load-failure view uses `PageFailureKind`

## Wave C not shipped (decided)

- #44 sync last-synced/error state: already on master (`LibrarySync.Status.summary`: "Up to date · time", "Couldn't sync: …").
- #46 ⌘Z Undo Close Tab: skipped. A global ⌘Z competes with text undo in pages (MH 1); ⇧⌘T and the toast's Undo cover it.
- #47 sidebar keyboard focus: deferred to the GUI session: focusable rows may take first responder from Chromium on click; needs a real-app keyboard check.
- #52 Settings regrouped: skipped, no clear win, moves settings people know.
- #53 interactive space swipe, #55 command bar grows from the address: not started (M effort, gesture/MH 2,5 needs real-app check).
- #59 scrim over the rail: skipped; the rail stays tappable by design (README 2026-11-13).
- #62 ST-4, #66 DU-2: device-only measurements, no code.
- #65 command bar focus without polling: skipped; the polling is the safety net for Chromium focus (MH 1), needs DMG runtime work.
- #72 onboarding contrast: needs a measured contrast on the rendered glass; not changed blind.

## Wave D

- [x] #74, #76 (iPhone Spotlight), #77 — PR #171 — v0.4.42
- [x] #75 Handoff (SY-8): PR https://github.com/chenkahana/Boaz/pull/173 — v0.4.43: focused normal tab only, never Incognito, history or failed pages; Swift only (DMG receive uses the host's own BrowsingWeb handler, unverified), so not risky. Two-device check owed.
- [-] #76 Focus filter + Mac Spotlight: skipped. Spike 2026-11-24: the DMG bundle has no `Metadata.appintents` (the UI is a dylib inside Chromium's app, so App Intents are not extracted), and opening a Spotlight result needs the host's AppKit delegate (C++ host change + Chromium base rebuild). Revisit with a host-side App Intents extension.

## #78 Live tab snapshots

- Spike (2026-11-23): the host has no freeze or MHTML API (`Tools/chromium/host`: no `Freeze`/`GenerateMHTML`), so steps 1-3 of tab-snapshots.md need host C++ and a Chromium rebuild; capture is capped at 2048 px and 2 MP by the host (`visible_page_capture.cc`).
- [x] Slice 1 (Swift only, branch craft/snapshots-1): last look kept on disk per profile under Caches (200 MB LRU), deleted on close/archive/removal and lazily when the page changed, never for Incognito; capture sized to the window at backing scale within the host cap; "Saved preview" caption removed (MW-2, #17); docs/privacy.md line. Risky release ≥ 24 h after the engine batch.
- [ ] Slice 2 (branch craft/snapshots-3, on slice 1; builds green, not released): host ABI 57 adds `set_page_frozen` (WebContents::SetPageFrozen, hidden pages only), `save_mhtml` (GenerateMHTML to a file, 30 s deadline) and `read_scroll_position` (DevTools Page.getLayoutMetrics, no page script). Past 10 awake pages a hidden, idle page freezes instead of closing; frozen pages close past 20 resident pages (38b8094) or on a memory-pressure warning (half, oldest first) or critical (all). A page that closes while its tab stays (not Incognito, not a closing Today tab) saves itself as MHTML with a hidden `#boaz-last-look` marker at its scroll position (≤ 50 MB, in the 200 MB per-profile LRU with the images). Coming back, the saved page opens in the tab's profile with scripts off (MHTML is sandboxed: archive-only loads) at the marker, over the reloading live page; when the live page is ready it takes the snapshot's scroll if the user moved it, then the snapshot fades out (Reduce Motion: instant) and closes. A link clicked in the snapshot opens in the live page. Not done: MHTML on quit (would delay quit), Find inside the snapshot, inner scrollers in the snapshot (window scroll only; the live page restores them), the offline case shows the failure page over the snapshot. Runtime pass 2026-11-24 (dev app, 32 Wikipedia tabs): footprint across Boaz's processes 355 MB empty → 1.47 GB at 10 tabs → 2.48 GB at 20 → 3.57 GB at 30 (~110 MB a tab; a frozen page keeps its memory), so the cap went from 40 to 20 resident pages. Verified: a page past 10 gets `freeze` and on return `resume`, at its scroll position (25498 px); at 25 tabs the 5 oldest closed and saved MHTML (1.7–4.1 MB each); returning to the first one showed the snapshot at the exact spot within 0.3 s (scripts off, all images), then the live page at the same spot with no jump; after a relaunch a saved tab shows its snapshot before the live page loads. Incognito: checked in code only (saving and showing both skip private tabs). Not runtime-checked: link click inside a snapshot (the snapshot page isn't an automation target), Reduce Motion swap. Note for runtime passes with a custom HOME: launch with `--use-mock-keychain`, or Chromium raises a 'Keychain Not Found' dialog and every request stalls.

## Not started

- #78 Live tab snapshots (waiting: Chen's answers on on-disk snapshots and the frozen-page memory budget)
- Waves C and D: after A and B. #40 (DU-3 battery `.percent`) was folded into #32.
- Superseded single-item PRs closed: #146 (#1), #147 (#4), #152 (#14) → batch #158.
- Release note: per-PR releases collapsed while the runner was busy (pending release runs supersede each other; iPhone-only merges don't start one). v0.4.30's notes were extended with 0.4.27-0.4.29 and v0.4.34's with 0.4.31-0.4.33.

## Runtime checks owed

Done 2026-11-24 on the 0.4.42 dev app (own HOME, `--use-mock-keychain`, driven by AX press and DevTools, window-only captures):
- #3: while a page loads, a progress line runs along the bottom inside the address pill (caught at ~0.1–0.3 s); it's gone once loaded.
- #18: a tab scrolled to 15000 px, then pushed out by 10 newer tabs, shows its last-seen spot within 0.3 s of coming back and the reloaded page lands at 15000 px. (A scroll made while the tab is hidden isn't recorded, as expected.)
- #27: at Sidebar Text Size 17 the row titles, the "+" glyph and the command bar field text are larger than at the default.
- #30: at 1× the web card's corner sits concentric inside the window corner. No 2× display was attached, so the 2× check stays owed.

Still owed (need real input or a system setting):
- #5 Reduce Motion (Mac system setting, not changed on Chen's Mac): new tab, close, pin, split, sidebar toggle, space switch, peek fade instead of slide.
- #6 command bar (pointer): ⌘T with the pointer resting over the list area, type: top hit stays selected; move over row 3: it selects.
- #15 drag out (pointer): drag a tab into TextEdit (gets the URL) and into a sidebar folder (moves).
- #24 trackpad: haptic at sidebar 200/420 pt, split 20/50/80 %, drop slot entered, drop accepted.
- #28 setup "Sign In to iCloud" label on an iCloud-capable signed build.
- #30 at 2×.

## Decisions (2026-11-23, Chen delegated; each is reversible in the named place)

- #16: the engine's initial window title (`ChromiumAppWindow`) is left as "Boaz — Private"; the view renames the window on attach, so the engine file stays out of the polish release.
- #19 skipped (see above).
- #31 folded into its callers.
- #13: an edge fade (not snapping to whole rows); fade only while rows sit below (`PageSettingsPanel.moreBelow`).
- #26: at accessibility sizes the page menu is full height and its four tiles drop captions (Large Content Viewer shows the name on press and hold).
- #33: Mac history rows caption "History · host" (Safari's word).
- #34: "Archive" is the only name (glossary); empty titles "No Archived Tabs/History/Downloads".
- #35: a tab counts as failed until a load commits; while it retries the page shows "Can't Open This Page · Trying again…".
- #38: offline, the search panel stays small and says suggestions return when connected.
- #41: toasts say what failed in plain words and log the system error (`MacModel.showError`).
- #43: iPhone setup's primary button is Continue; Sign In to iCloud is the secondary button (`OnboardingView.primary/secondary`). Settings' signed-out line states "Not signed in to iCloud" next to the button.
- #45: share sheet "Pin to Sidebar" / "Add to Tabs".
- Soak clock: 0.4.37 published 2026-11-22 20:05 UTC (22:05 IST), so the next risky merge is ≥ 2026-11-23 22:05 IST.
- Soak evidence for 0.4.37 on this Mac (2026-11-23 20:40): /Applications/Boaz.app replaced 2026-11-22 22:21 IST through Sparkle (PersistentDownloads touched then), running since 07:40 today; no "No pop-up host" (the only WebKit-internals fallback) in 23 h of unified log, so About reads "No problems seen"; no Boaz crash reports since 2026-11-19. Not checked: iPhone sync convergence, and tabs/sign-ins by eye (Chen's devices).
- #74: Incognito violet = the Mac Incognito window's (`SiteEdges.incognito`).
- #77: one New Tab control; Search would do the same thing.
- #78 slice 1: snapshots live in Caches, not the library directory: a cache must never sit with data that can't be lost.
