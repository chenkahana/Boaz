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
