RESUME HERE (2026-11-23 16:40 IST): round 2. Polish PR #168 (0.4.38: #7 #2 #3 #16 #11 #13 #26) and Wave C batch 1 PR #169 (0.4.39) in CI. Engine batch (#18 + engine halves of #16/#36/#37) waits for the 0.4.37 soak: merge no earlier than 2026-11-23 22:05 IST (0.4.37 published 20:05 UTC). Then #78, Wave C rest, Wave D (each risky one soaks 24 h). Decisions log at the end of this file.

# Implementation

Chen approved implementation on 2026-11-18: build the R5 backlog items that don't need his yes, Wave A first, then
Wave B. One visible change per PR, each its own patch release. Items marked "waiting" touch a must-have or change
behaviour and wait for Chen's yes (R5.3 "Chen's yes" column).

## Wave A

- [x] #1 iPhone carousel header: "N Tabs" and Done never overlap at AX sizes (AX-8) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [ ] #2 iPhone rail: one 48 pt control size (IB-2, IB-9) — polish PR https://github.com/chenkahana/Boaz/pull/168 — 0.4.38 (in CI)
- [ ] #3 DMG: page-load progress in the address pill (MW-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — 0.4.38 (in CI)
- [x] #4 Motion tokens, Reduce Motion inside the token (SY-1) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #5 Mac: the 14 model springs fade under Reduce Motion (AX-12) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #6 Mac command bar: selection follows pointer movement (MC-1) — PR https://github.com/chenkahana/Boaz/pull/151 — v0.4.30 (released v0.4.30)
- [ ] #7 Mac toast UI test waits for the toast (AX-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — 0.4.38 (in CI)
- [x] #8 iPhone search field: 44 pt Clear Text button (IS-1) — PR https://github.com/chenkahana/Boaz/pull/149 — v0.4.28 (iPhone; shipped in release v0.4.30)
- [x] #9 Mac peek and sidebar: three one-off curves become tokens (MS-6) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #10 iPhone search panel: captions wrap by word at AX sizes (AX-10) — PR https://github.com/chenkahana/Boaz/pull/150 — v0.4.29 (iPhone; shipped in release v0.4.30)
- [ ] #11 Duo half-open strip: 44 pt rows and close buttons (DU-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — 0.4.38 (in CI)
- [x] #12 iPhone carousel: a failed tab gets a designed card (IB-3) — PR https://github.com/chenkahana/Boaz/pull/148 — v0.4.27 (iPhone; shipped in release v0.4.30)
- [ ] #13 iPhone page menu ends on an edge fade (IM-1) — polish PR https://github.com/chenkahana/Boaz/pull/168 — 0.4.38 (in CI)
- [x] #14 Mac library panel: tab labels at a readable size (ML-1) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #15 Mac sidebar: dragging a tab out gives its URL (MS-1) — PR https://github.com/chenkahana/Boaz/pull/153 — v0.4.31 (in release v0.4.34)
- [ ] #16 DMG windows titled after their page (MS-13) — polish PR https://github.com/chenkahana/Boaz/pull/168 — 0.4.38 (in CI)
- [ ] #17 Restored tab: no "Saved preview" caption (MW-2) (waiting: Chen's yes, MH 13; folds into #78)
- [ ] #18 Mac: unloaded tab keeps its snapshot (MW-4) — engine batch, after the 0.4.37 soak (≥ 2026-11-23 22:05 IST)
- [-] #19 Mac WebKit find bar without Replace (MW-9) — skipped: SwiftUI `WebPage` has no find API; a JS find would lose native match highlighting and count (Mac App Store build only)

## Wave B

- [x] #20 `Haptics` enum and haptic map (SY-2) — PR https://github.com/chenkahana/Boaz/pull/154 — v0.4.32 (in release v0.4.34)
- [x] #21 iPhone archive swipe: haptic at the commit threshold (IB-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #22 iPhone archive flick keeps the finger's speed (IB-5) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #23 iPhone page menu: drag-to-dismiss keeps velocity (IM-3) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #24 Mac trackpad haptics at sidebar limits, folder crossings and split snaps (MS-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #25 Type ramp tokens (SY-3) — PR https://github.com/chenkahana/Boaz/pull/155 — v0.4.33 (in release v0.4.34)
- [ ] #26 iPhone page menu usable at AX5 (AX-9) — polish PR https://github.com/chenkahana/Boaz/pull/168 — 0.4.38 (in CI)
- [x] #27 Mac sidebar glyphs and command bar follow Settings › Sidebar text size (MS-7, MC-5) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #28 iPhone: page-menu tiles, onboarding button and Settings title scale with Dynamic Type (IM-4, OB-3, AX-11) — PR https://github.com/chenkahana/Boaz/pull/157 — v0.4.35 (iPhone; ships with v0.4.36)
- [x] #29 Spacing and radius tokens (SY-4) — PR https://github.com/chenkahana/Boaz/pull/156 — v0.4.34
- [x] #30 Mac: concentric card and panel corners from the radius scale (MS-10, ML-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [-] #31 State kit components (SY-5) — folded into the items that use each piece (no component ships without a caller); `PageFailureKind` came with #36
- [x] #32 English String Catalog, glossary and copy lint (SY-6) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36

## Wave C

- [ ] #33 Search suggestions say what each row does (AX-4, MC-6) — PR https://github.com/chenkahana/Boaz/pull/169 — 0.4.39 (in CI)
- [ ] #34 One name for the Archive, one empty-state voice (ML-3) — PR #169
- [ ] #35 iPhone: reopened failed tab shows its failure at once (IB-8) — PR #169
- [ ] #36 One load-failure page (MW-3, MW-5) — WebKit builds in PR #169; DMG view in the engine batch
- [ ] #37 Settings title case, no doubled "After" (ST-1, ST-2) — PR #169; find bar (MW-6) in the engine batch
- [ ] #38 iPhone search: offline hint; empty state hidden behind the panel (IS-4, IS-2) — PR #169
- [ ] #39 Swipe-toolbar tip waits for the page (IB-7) — PR #169
- [x] #40 Duo status pill `.percent` (DU-3) — already in 0.4.36 (#32)
- [ ] #41 Plain-language errors (MS-14, WX-4) — PR #169
- [x] #42 Mac empty space New Tab row (MS-8) — already on master: the sidebar always shows New Tab, the page area a search hint
- [ ] #43 One iCloud sign-in message (OB-5, ST-3) — PR #169
- [ ] #45 Share extension labels (WX-5) — PR #169

## Not started

- #78 Live tab snapshots (waiting: Chen's answers on on-disk snapshots and the frozen-page memory budget)
- Waves C and D: after A and B. #40 (DU-3 battery `.percent`) was folded into #32.
- Superseded single-item PRs closed: #146 (#1), #147 (#4), #152 (#14) → batch #158.
- Release note: per-PR releases collapsed while the runner was busy (pending release runs supersede each other; iPhone-only merges don't start one). v0.4.30's notes were extended with 0.4.27-0.4.29 and v0.4.34's with 0.4.31-0.4.33.

## Runtime checks owed

- #5 Reduce Motion (Mac system setting): new tab, close, pin, split, sidebar toggle, space switch, peek fade instead of slide.
- #24 trackpad: haptic at sidebar 200/420 pt, split 20/50/80 %, drop slot entered, drop accepted.
- #27 Settings › Sidebar text size 17: glyphs and command bar field/rows grow.
- #30 web card corner beside the window corner on a 2× display.
- #28 setup "Sign In to iCloud" label on an iCloud-capable signed build.

- #6 command bar (pointer): ⌘T with the pointer resting over the list area, type: top hit stays selected; move over row 3: it selects.
- #15 drag out (pointer): drag a tab into TextEdit (gets the URL) and into a sidebar folder (moves).

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
