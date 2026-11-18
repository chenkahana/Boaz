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
