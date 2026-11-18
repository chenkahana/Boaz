RESUME HERE: #1 AX-8 carousel header — starting (worktree ~/.worktrees/Boaz/craft-1-carousel-header).

# Implementation

Chen approved implementation on 2026-11-18: build the R5 backlog items that don't need his yes, Wave A first, then
Wave B. One visible change per PR, each its own patch release. Items marked "waiting" touch a must-have or change
behaviour and wait for Chen's yes (R5.3 "Chen's yes" column).

## Wave A

- [ ] #1 iPhone carousel header: "N Tabs" and Done never overlap at AX sizes (AX-8)
- [ ] #2 iPhone rail: one 48 pt control size (IB-2, IB-9) (waiting: Chen's yes, MH 7, 9)
- [ ] #3 DMG: page-load progress in the address pill (MW-1) (waiting: Chen's yes, MH 1)
- [ ] #4 Motion tokens, Reduce Motion inside the token (SY-1)
- [ ] #5 Mac: the 14 model springs fade under Reduce Motion (AX-12)
- [ ] #6 Mac command bar: selection follows pointer movement (MC-1)
- [ ] #7 Mac toast UI test waits for the toast (AX-1) (waiting: Chen's yes, MH 14)
- [ ] #8 iPhone search field: 44 pt Clear Text button (IS-1)
- [ ] #9 Mac peek and sidebar: three one-off curves become tokens (MS-6)
- [ ] #10 iPhone search panel: captions wrap by word at AX sizes (AX-10)
- [ ] #11 Duo half-open strip: 44 pt rows and close buttons (DU-1) (waiting: Chen's yes, MH 9)
- [ ] #12 iPhone carousel: a failed tab gets a designed card (IB-3)
- [ ] #13 iPhone page menu ends on a whole row or an edge fade (IM-1) (waiting: Chen's yes, MH 7)
- [ ] #14 Mac library panel: tab labels at a readable size (ML-1)
- [ ] #15 Mac sidebar: dragging a tab out gives its URL (MS-1)
- [ ] #16 DMG windows titled after their page (MS-13) (waiting: Chen's yes, MH 2)
- [ ] #17 Restored tab: no "Saved preview" caption (MW-2) (waiting: Chen's yes, MH 13; folds into #78)
- [ ] #18 Mac: unloaded tab keeps its snapshot (MW-4) (waiting: Chen's yes, MH 1)
- [ ] #19 Mac WebKit find bar without Replace (MW-9) (waiting: Chen's yes, MH 10)

## Wave B

- [ ] #20 `Haptics` enum and haptic map (SY-2)
- [ ] #21 iPhone archive swipe: haptic at the commit threshold (IB-4)
- [ ] #22 iPhone archive flick keeps the finger's speed (IB-5)
- [ ] #23 iPhone page menu: drag-to-dismiss keeps velocity (IM-3)
- [ ] #24 Mac trackpad haptics at sidebar limits, folder crossings and split snaps (MS-4)
- [ ] #25 Type ramp tokens (SY-3)
- [ ] #26 iPhone page menu usable at AX5 (AX-9) (waiting: Chen's yes, MH 7)
- [ ] #27 Mac sidebar glyphs and command bar follow Settings › Sidebar text size (MS-7, MC-5)
- [ ] #28 iPhone: page-menu tiles, onboarding button and Settings title scale with Dynamic Type (IM-4, OB-3, AX-11)
- [ ] #29 Spacing and radius tokens (SY-4)
- [ ] #30 Mac: concentric card and panel corners from the radius scale (MS-10, ML-4)
- [ ] #31 State kit components (SY-5) (waiting: Chen's yes, MH 1, 11)
- [ ] #32 English String Catalog, glossary and copy lint (SY-6)

## Not started

- #78 Live tab snapshots (waiting: Chen's answers on on-disk snapshots and the frozen-page memory budget)
- Waves C and D: after A and B.

## Runtime checks owed

(none yet)
