RESUME HERE (2026-11-23): round 2 in progress. Branch craft/batch-2-gated (pushed, 53d9959, merges cleanly on master 54690f5) holds #7, #2, #3, #16, #18. It touches Apps/macOS/Engine, so it is a soak release under docs/release.md (0.4.37 touched sync; next risky release after 2026-11-23 20:05 and Chen's soak checks). Split polish vs engine commits. Remaining round 2: #11, #13, #19, #26, #31, #78, Wave C (41), Wave D (4). Every release: crash-report check line in the notes.

# Implementation

Chen approved implementation on 2026-11-18: build the R5 backlog items that don't need his yes, Wave A first, then
Wave B. One visible change per PR, each its own patch release. Items marked "waiting" touch a must-have or change
behaviour and wait for Chen's yes (R5.3 "Chen's yes" column).

## Wave A

- [x] #1 iPhone carousel header: "N Tabs" and Done never overlap at AX sizes (AX-8) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [ ] #2 iPhone rail: one 48 pt control size (IB-2, IB-9) (waiting: Chen's yes, MH 7, 9)
- [ ] #3 DMG: page-load progress in the address pill (MW-1) (waiting: Chen's yes, MH 1)
- [x] #4 Motion tokens, Reduce Motion inside the token (SY-1) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #5 Mac: the 14 model springs fade under Reduce Motion (AX-12) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #6 Mac command bar: selection follows pointer movement (MC-1) — PR https://github.com/chenkahana/Boaz/pull/151 — v0.4.30 (released v0.4.30)
- [ ] #7 Mac toast UI test waits for the toast (AX-1) (waiting: Chen's yes, MH 14)
- [x] #8 iPhone search field: 44 pt Clear Text button (IS-1) — PR https://github.com/chenkahana/Boaz/pull/149 — v0.4.28 (iPhone; shipped in release v0.4.30)
- [x] #9 Mac peek and sidebar: three one-off curves become tokens (MS-6) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #10 iPhone search panel: captions wrap by word at AX sizes (AX-10) — PR https://github.com/chenkahana/Boaz/pull/150 — v0.4.29 (iPhone; shipped in release v0.4.30)
- [ ] #11 Duo half-open strip: 44 pt rows and close buttons (DU-1) (waiting: Chen's yes, MH 9)
- [x] #12 iPhone carousel: a failed tab gets a designed card (IB-3) — PR https://github.com/chenkahana/Boaz/pull/148 — v0.4.27 (iPhone; shipped in release v0.4.30)
- [ ] #13 iPhone page menu ends on a whole row or an edge fade (IM-1) (waiting: Chen's yes, MH 7)
- [x] #14 Mac library panel: tab labels at a readable size (ML-1) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #15 Mac sidebar: dragging a tab out gives its URL (MS-1) — PR https://github.com/chenkahana/Boaz/pull/153 — v0.4.31 (in release v0.4.34)
- [ ] #16 DMG windows titled after their page (MS-13) (waiting: Chen's yes, MH 2)
- [ ] #17 Restored tab: no "Saved preview" caption (MW-2) (waiting: Chen's yes, MH 13; folds into #78)
- [ ] #18 Mac: unloaded tab keeps its snapshot (MW-4) (waiting: Chen's yes, MH 1)
- [ ] #19 Mac WebKit find bar without Replace (MW-9) (waiting: Chen's yes, MH 10)

## Wave B

- [x] #20 `Haptics` enum and haptic map (SY-2) — PR https://github.com/chenkahana/Boaz/pull/154 — v0.4.32 (in release v0.4.34)
- [x] #21 iPhone archive swipe: haptic at the commit threshold (IB-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #22 iPhone archive flick keeps the finger's speed (IB-5) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #23 iPhone page menu: drag-to-dismiss keeps velocity (IM-3) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #24 Mac trackpad haptics at sidebar limits, folder crossings and split snaps (MS-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #25 Type ramp tokens (SY-3) — PR https://github.com/chenkahana/Boaz/pull/155 — v0.4.33 (in release v0.4.34)
- [ ] #26 iPhone page menu usable at AX5 (AX-9) (waiting: Chen's yes, MH 7)
- [x] #27 Mac sidebar glyphs and command bar follow Settings › Sidebar text size (MS-7, MC-5) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [x] #28 iPhone: page-menu tiles, onboarding button and Settings title scale with Dynamic Type (IM-4, OB-3, AX-11) — PR https://github.com/chenkahana/Boaz/pull/157 — v0.4.35 (iPhone; ships with v0.4.36)
- [x] #29 Spacing and radius tokens (SY-4) — PR https://github.com/chenkahana/Boaz/pull/156 — v0.4.34
- [x] #30 Mac: concentric card and panel corners from the radius scale (MS-10, ML-4) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36
- [ ] #31 State kit components (SY-5) (waiting: Chen's yes, MH 1, 11)
- [x] #32 English String Catalog, glossary and copy lint (SY-6) — batch PR https://github.com/chenkahana/Boaz/pull/158 — v0.4.36

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
