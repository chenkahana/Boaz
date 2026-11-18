# Craft research: checklist

Research and docs only: no app code, no version bump, no CHANGELOG, no release. Resume point and log:
[`PROGRESS.md`](PROGRESS.md). Binaries (recordings, Instruments traces, large screenshots) live outside git under
`~/tmp/codex/boaz-craft/` on Chen's Mac; the phase files reference them by path.

Code base for this pass: `origin/master` at `66c3d63` (0.4.25), worktree `~/.worktrees/Boaz/craft-research`, branch
`docs/craft-research`.

### R0. Baseline capture → [`R0-baseline.md`](R0-baseline.md)
- [x] R0.1 Builds installed: Mac DMG (Chromium), Mac App Store (WebKit), iPhone standard, iPhone Duo
- [x] R0.2 Recordings per flow (Light and Dark)
- [x] R0.3 Instruments: Animation Hitches and App Launch traces
- [x] R0.4 `R0-baseline.md` written

### R1. Surface inventory → [`R1-inventory.md`](R1-inventory.md)
- [x] R1.1 iPhone surfaces × states
- [x] R1.2 Mac surfaces × states
- [x] R1.3 Widgets, extensions and system surfaces
- [x] R1.4 `R1-inventory.md` complete

### R2. Pillar audit → [`R2-findings.md`](R2-findings.md)
- [x] R2.1 Mac sidebar
- [x] R2.2 Mac command bar
- [x] R2.3 Mac web pane and split view
- [x] R2.4 Mac library panel
- [x] R2.5 Settings (Mac and iPhone)
- [x] R2.6 Onboarding (Mac and iPhone)
- [x] R2.7 iPhone bottom bar, tab fan and carousel
- [x] R2.8 iPhone search panel
- [x] R2.9 iPhone page menu
- [x] R2.10 Duo postures
- [x] R2.11 Widgets and extensions
- [x] R2.12 Accessibility: system audit (Accessibility Inspector / XCUITest audit)
- [x] R2.13 Accessibility: VoiceOver walk of the five main flows
- [x] R2.14 Accessibility: Dynamic Type AX3 and AX5
- [x] R2.15 Accessibility: Increase Contrast, Reduce Motion, Reduce Transparency
- [x] R2.16 `inputs/ux-review-2026-11-09.md` re-verified (fixed / open / obsolete per finding)
- [x] R2.17 Per-surface craft scores (0–3 per pillar)

### R3. Reference teardown → [`R3-references.md`](R3-references.md)
- [x] R3.1 Safari on iPhone
- [x] R3.2 Safari on Mac
- [x] R3.3 Arc
- [x] R3.4 Chrome
- [x] R3.5 Dia
- [x] R3.6 Orion
- [x] R3.7 "Steal this" list mapped to R2 findings

### R4. Systems design → [`R4-systems.md`](R4-systems.md)
- [x] R4.1 Motion tokens and transition catalog
- [x] R4.2 Haptic map (iPhone and Mac)
- [ ] R4.3 Layout tokens (spacing, radius, concentric rule, hit targets)
- [ ] R4.4 Type ramp
- [ ] R4.5 Copy rules, glossary and String Catalog adoption
- [ ] R4.6 State kit
- [ ] R4.7 Handoff design (iPhone ↔ Mac)

### R5. Backlog → [`R5-backlog.md`](R5-backlog.md)
- [ ] R5.1 Every finding scored
- [ ] R5.2 Grouped into workstreams
- [ ] R5.3 Sliced into PRs, Chen-yes items marked
- [ ] R5.4 Stop for Chen's review

---

# Boaz: the craft pass (research plan, 2026-11-18)

**Goal.** Boaz should feel like Apple could have shipped it, on the iPhone and the Mac: every motion intentional,
every state designed, every control where a Mac or iPhone user expects it. This is research and planning only. No
code changes until Chen approves the backlog at the end of phase R5.

**Sister handoffs.** The same research runs on Edison (`~/Edison/tasks/ux-polish-research-handoff.md`) and Jimmy
(`~/Jimmy/tasks/ux-polish-research-handoff.md`). All three use the rubric in section 2 and the scoring in section 5,
so the results compare across apps and shared fixes (motion tokens, haptics, copy rules) can be reused.

**Code read for this plan:** `origin/master` at `66c3d63` (0.4.25) in `~/.worktrees/Boaz/release`. Local `master`
is 8 commits behind with a dirty `.codex/memories/lessons.md`; pull before starting.

---

## 1. Guardrails

- `docs/must-haves.md` gates every item. Polish that touches a must-have (one window for every profile, Chromium for
  every page, the iPhone bottom bar taking its own height, no Spaces on iPhone, Duo postures, sync, on-device AI,
  library never lost) needs Chen's yes before it ships. Check them at plan time and again in the real app at
  verify time.
- Runtime first. Every finding in the backlog needs a screenshot, screen recording or Instruments trace from the
  real app, not just a code reading. Code sweeps (section 3) point at where to look; they don't prove a bug.
- One item, one PR, one patch release (`patch-release-every-pr`). Polish lands in small PRs, not a big-bang
  redesign.
- `docs/craft/inputs/ux-review-2026-11-09.md` (2026-11-09, Folio era, 40 findings) is input, not done work. Re-check each finding against
  current master; many lines have moved and the Mac is now Chromium.

---

## 2. The rubric: what makes an iPhone an iPhone and a Mac a Mac

Twelve pillars. Each has checks that can be answered yes or no in the running app. The audit (R2) walks every
surface through every pillar.

### P1. Motion has physics, and one voice
- One small set of named curves per platform (for example: `quick` for hover and selection, `standard` for
  panels, `emphasized` for presenting and dismissing, `gesture` for anything a finger drives). No one-off curves.
- Gesture-driven motion is interruptible and keeps the finger's velocity at release. A flick that ends a drag hands
  its speed to the spring; nothing restarts from zero.
- Things move from where they came from: a tab card grows into the page it opens and shrinks back to its place in
  the fan; a sheet leaves the way it arrived; a closed tab collapses toward where it lived.
- Rubber-banding at every scroll and drag limit; no hard stops.
- No animation on first appearance of content that was already there (launch, restore, relaunch), no layout jump
  after the first frame, no flash of an empty state before data arrives.
- 120 Hz on ProMotion iPhones and Macs: zero hitches in the main flows, measured.
- Reduce Motion: movement becomes a cross-fade, nothing slides or scales. Every animated call site honors it.

### P2. Touch and click feel physical
- Haptics on iPhone mark meaningful moments only: a snap, a commit, crossing a threshold, success or failure.
  Never on every scroll tick or every tap.
- Mac trackpad haptics (`NSHapticFeedbackManager`) when something snaps or aligns: sidebar width, split divider,
  reorder slot.
- Press states on every tappable control (highlight within one frame, not on release).
- Hit targets 44 pt on iPhone; on the Mac, the whole row or tile is clickable, not just its glyph.
- Hover on the Mac: every interactive element answers the pointer, with the right cursor (resize, link,
  I-beam) and a tooltip on every icon-only control.

### P3. Geometry is exact
- Corner radii are concentric: an inset card's radius equals the container's radius minus the inset. Continuous
  (squircle) corners everywhere.
- One spacing scale and one radius scale per platform, used through tokens; no literal paddings that are "close".
- Optical alignment: icons and text centered by eye (SF Symbol baselines, glyph-heavy icons nudged), not by
  bounding box.
- Nothing clips, overlaps or truncates badly at the smallest window, largest Dynamic Type, longest title, RTL
  page, or Duo posture.

### P4. Type is system type
- SF Pro via text styles, so Dynamic Type works on iPhone. Fixed point sizes only where a layout truly can't grow,
  and then with `@ScaledMetric` or the large content viewer.
- Weights and sizes follow one hierarchy per screen; tabular digits for changing numbers (zoom, counts, progress).
- Titles truncate in the middle or the tail according to what identifies them (host names keep the end).

### P5. Color and materials behave
- Light, Dark and Increase Contrast all pass 4.5:1 for text (the sidebar rules in `docs/design.md` extend to every
  surface).
- Glass and materials have a solid fallback under Reduce Transparency.
- Tint comes from one place (the space theme on the Mac, the site color on iPhone) and never fights the page.
- Incognito looks unmistakably different without looking broken.

### P6. Every state is designed
- Empty, loading, partial, offline, error, permission-denied and first-run states exist for every list and panel,
  with the same tone and layout family.
- Loading under ~300 ms shows nothing; longer shows progress in place (no centered spinner replacing content).
- Errors say what happened and offer the next action (Try Again, Open Settings), in plain words.
- Destructive actions confirm or offer Undo; never both missing, rarely both present.

### P7. Words are product
- One capitalization rule per element type (Apple: title case for buttons, menu items and window titles;
  sentence case for descriptions and alerts' messages).
- Real ellipsis (…) on items that open a further step; none on items that act at once.
- Same name for the same thing everywhere (Archive, Today, Pinned, Favorites, Space).
- Plurals handled ("1 Tab", "2 Tabs") through a String Catalog, which also makes Boaz localization-ready.

### P8. Keyboard and menus (Mac first, iPhone with a hardware keyboard second)
- Every command is in the menu bar, with its shortcut shown, enabled only when it applies, and its title
  reflecting state (Show Sidebar / Hide Sidebar).
- Full Keyboard Access reaches every control; focus rings visible; Tab order is the visual order.
- Esc closes the topmost transient thing; Return confirms the default; ⌘. cancels.
- ⌘Z undoes the last library change (close, move, pin, delete folder, rename), not only via a toast.

### P9. Direct manipulation everywhere
- Drag works in and out of the app: tabs, links, images, favorites, folders, downloads; drop targets highlight;
  drags show a real preview; spring-loading opens folders while hovering.
- Right-click on every object, with the same menu as its "…" button.
- Swipe actions on iPhone lists have full-swipe behavior and match the context menu.

### P10. The system is part of the app
- Handoff: the page open on the iPhone appears in the Mac's Dock (and the reverse), via `NSUserActivity`.
- Spotlight (pinned tabs, favorites), Shortcuts / App Intents, Focus filters (a Focus picks the space), Control
  Center and Lock Screen controls on iPhone, Services menu on the Mac.
- State restoration: relaunch puts back windows, scroll positions, selected tab, open panels.
- Share sheet, Quick Look, Writing Tools and Translation where the system offers them.

### P11. Speed you can feel
- Cold launch to interactive page under the platform target (iPhone ≤ 400 ms to first frame with content; Mac
  window with the restored page ≤ 1 s). Measured, then held in CI if feasible.
- Typing in the command bar and search never drops a key, including the first one after ⌘T/⌘L.
- No timer-based waits in user-visible paths: no "sleep 50 ms and try again" deciding when focus or layout lands.

### P12. Accessibility is a first-class surface
- VoiceOver: every control labeled, headers marked, custom actions for gestures (next tab, close, pin, archive),
  rotors for long lists, announcements for toasts and completions.
- Voice Control: visible labels match the accessible names.
- Accessibility Inspector audit clean on every screen; Dynamic Type at AX5 usable on iPhone.

---

## 3. What the code already tells us (deterministic sweep, 66c3d63)

Evidence from `rg` counts over `Apps/` and `Packages/BoazKit/Sources` (158 Swift files, ~36k lines). These are
leads for R2, not verdicts.

| # | Pillar | Evidence | Lead |
|---|---|---|---|
| E1 | P1 | ~40 distinct animation curves in 30 files: 22 different `.spring(response:dampingFraction:)` pairs, plus `.easeOut` at 0.12/0.18/0.2/0.25/0.4, `.smooth` at 0.2/0.25/0.3/0.4, `.snappy`, `.bouncy`. Only three named tokens exist (`SidebarStyle.motion`, `TabStack…motion`, `BottomPanelStyle.motion`), two of them named `motion` with different values; `TabStack.swift:568,583,692` uses `MacRowStyle.motion` on iPhone. | Motion feels assembled rather than designed. Needs a motion system (P1). |
| E2 | P1 | Zero `matchedGeometryEffect` / `navigationTransition(.zoom)` / `matchedTransitionSource`. | Tab card → page and page → fan don't share geometry; the iPhone's signature "it came from there" moment is missing. Confirm in recordings. |
| E3 | P2 | 11 `sensoryFeedback` call sites, all iOS; zero Mac haptics. No haptic on pin, close, archive-swipe commit, space switch (Mac), sidebar resize or split snap. | Haptic map needed for both platforms. |
| E4 | P5 | 17 `glassEffect` and several materials; Customize Space added transparency (#137); zero `accessibilityReduceTransparency` handling. | Reduce Transparency fallbacks missing everywhere. |
| E5 | P4 | 54 `.font(.system(size:))`, 2 `@ScaledMetric`, 2 `dynamicTypeSize`. iOS: `RootView` 3, `ToolRail` 2, `TabStack` 1, `TabBrowser` 1, `AppIconPicker` 1, `SpaceIcon`/`SpaceEditor` 4; Mac: `LibraryPanel` 13, `Sidebar` 7, `LiveFolderViews` 7, `CommandBar` 4. | iPhone text that doesn't follow Dynamic Type; Mac sizes that ignore the sidebar text-size setting. |
| E6 | P7 | No String Catalog; 2 `String(localized:)`. Empty states disagree on case: iOS "Archive is empty", "No history", "No downloads" (`LibrarySheet.swift:59`, `DownloadsView.swift:46`) vs Mac "No Tabs", "No Downloads", "No History" (`LibraryPanel.swift:174`, `LibraryViews.swift:182`), and Mac "Archive is empty" (`LibraryViews.swift:68`). | Copy rules + String Catalog (P7). |
| E7 | P11 | 59 `Task.sleep` calls; the user-visible ones include the command bar's focus retry (10 × 50 ms, `CommandBar.swift:126-160`), window attach polling (25 × 20 ms, `BrowserWindow.swift:185`), restore polling (100 ms, `BrowserWindow.swift:158,166`), tab preview delay (`ChromiumTabPreview.swift:34`), find bar debounce. | Possible lost first keystroke, frame jumps on restore. Verify with recordings before touching. |
| E8 | P10 | Zero `NSUserActivity`, `CSSearchable`, `SetFocusFilterIntent`, `ControlWidget`, Services. App Intents in 1 file. | Handoff between Boaz on iPhone and Mac is the single most "Apple" missing feature for a two-device browser. |
| E9 | P8 | No `UndoManager` use. Undo exists only as a toast button and Reopen Closed Tab (⌘⇧T). | Mac ⌘Z for library edits. |
| E10 | P12 | 103 labels but 4 hints, 0 rotors, 0 large-content-viewer, Increase Contrast handled in 2 places (sidebar only). | VoiceOver and AX-size pass. |
| E11 | P3 | `MacRadius` tokens (6/8/10/12/16) exist, but literal radii 18, 20, 22, 24 appear 9 times; iOS has no radius tokens. 195 literal paddings. | Token pass; check concentric corners on the Mac content card against the macOS 26 window radius. |
| E12 | P6 | 15 `ContentUnavailableView`s with mixed tone; Mac load-failure view exists (`WebPane.swift:36`) with a quiet auto-retry. | Inventory every state per surface in R1. |

From the README screenshots (dated 2026-11-13, may be stale; re-capture in R0):
- iPhone page menu: the disabled Back and Forward tiles show a smeared shadow; the panel's last row is cut off by
  the bottom bar; the scrim dims the page but not the bar under it.
- Mac: address field shows a bare host with no site identity or security affordance (judgment call against Arc).

---

## 4. Research phases

Each phase ends with a file in `docs/craft/` and a one-paragraph summary to Chen.

### R0. Baseline capture (half a day)
- Build and install current master: Mac DMG (Chromium), Mac App Store build (WebKit), iPhone on a standard device
  and on the Duo in all four postures.
- Record every main flow at 120 Hz (QuickTime on Mac, screen recording on iPhone) in Light and Dark: launch, open
  tab, switch tab, close tab, new tab and search, command bar, page menu, sidebar drag, space switch, split view,
  library panel, settings, onboarding, Duo posture change.
- Instruments: Animation Hitches and App Launch templates for the same flows. Save traces.
- Output: `docs/craft/R0-baseline.md` with links to recordings and the hitch and launch numbers.

### R1. Surface inventory (half a day)
- List every screen, panel, sheet, menu, popover, toast, widget and extension on both platforms (start from
  `docs/qa.md` §2 and `Tests/BoazUITests/ScreenTests.swift`).
- For each: its states (empty, loading, error, offline, permission, first-run), its entry and exit transitions, its
  keyboard path and its context menu.
- Output: `docs/craft/R1-inventory.md`, one table row per surface × state.

### R2. Pillar audit (2 days)
- Walk every surface in R1 through P1–P12. Every finding gets: pillar, surface, platform, evidence (frame from
  R0, screenshot, trace or `file:line`), severity, effort, and which must-have it touches.
- Re-verify each finding in `docs/craft/inputs/ux-review-2026-11-09.md` and mark it fixed, still open, or obsolete.
- Accessibility Inspector audit on every Mac and iPhone screen; VoiceOver walk of the five main flows; Dynamic Type
  at AX3 and AX5; Increase Contrast; Reduce Motion; Reduce Transparency.
- Output: `docs/craft/R2-findings.md`.

### R3. Reference teardown (1 day)
- Same flows in Safari (iPhone and Mac), Arc, Chrome, Dia, Orion. Record the five moments where each feels best:
  tab open/close, tab overview, address entry, page menu, sidebar or tab strip drag.
- For each moment write down the mechanics, not the look: curve, duration, what moves, haptic, how it handles
  interruption. Frame-step the recordings.
- Output: `docs/craft/R3-references.md`, with a "steal this" list mapped to R2 findings.

### R4. Systems design (1 day)
Design the shared systems before any per-screen fix, so fixes land as token changes:
- **Motion tokens** per platform (names, curves, durations, Reduce Motion fallback), plus the transition catalog
  (present, dismiss, push, morph, collapse) and which surfaces use which.
- **Haptic map**: event → feedback type, iPhone and Mac.
- **Layout tokens**: spacing scale, radius scale with the concentric rule, hit-target minimums.
- **Type ramp**: text style per role, where `@ScaledMetric` is allowed.
- **Copy rules**: capitalization, ellipsis, glossary, error-message pattern, String Catalog adoption.
- **State kit**: one empty/error/loading component family per platform.
- Output: `docs/craft/R4-systems.md` (becomes `docs/design.md` sections once approved).

### R5. Backlog and sequencing (half a day)
- Score every finding (section 5), group into workstreams (section 6), slice into PRs of one visible change each.
- Mark items that need Chen's yes (must-have adjacent, visible behavior change, new system integration).
- Output: `docs/craft/R5-backlog.md` . **Stop here for Chen's review.**

---

## 5. Scoring

Each finding: **Severity** (S1 broken or inaccessible, S2 visibly unpolished in a main flow, S3 noticed by a careful
user, S4 nit) × **Reach** (every session, daily, occasional, rare) ÷ **Effort** (S, M, L). Ship order is S1 first,
then highest score. A finding that only a token change fixes moves to the systems PR, not its own PR.

Per-surface craft score (0–3 per pillar, 36 max) is recorded in R2 and re-scored after each workstream, so progress
is visible and comparable with Edison and Jimmy.

---

## 6. Workstreams (after approval)

| WS | Scope | Depends on |
|---|---|---|
| W1 Motion system | Tokens, replace ~40 curves, zoom/morph transitions for tab ↔ page and fan ↔ carousel, velocity hand-off on drags, Reduce Motion audit | R4 |
| W2 Touch & pointer | Haptic map on both platforms, press states, hit targets, cursors, tooltips | R4 |
| W3 Geometry & type | Radius/spacing tokens, concentric corners, Dynamic Type on iPhone, sidebar text-size on all Mac panels | R4 |
| W4 States & copy | State kit, every empty/error/offline state, copy rules, English String Catalog with plurals, grammar agreement and `FormatStyle` (§7.3) | R4 |
| W5 Mac nativeness | Menu completeness and state titles, Full Keyboard Access, ⌘Z via `UndoManager`, drag in/out, Services | R2 |
| W6 iPhone nativeness | Page menu panel fixes, swipe actions, context-menu previews, large content viewer, Control Center control | R2 |
| W7 System integration | Handoff iPhone ↔ Mac (approved, §7.2), Spotlight, Focus filters, App Intents, state restoration | R4; Spotlight and Focus filters still need Chen's yes |
| W8 Speed | Replace timer-based focus/restore waits, launch time, hitch budget, keystroke-loss test | R0 numbers |
| W9 Accessibility | VoiceOver actions and rotors, announcements, Increase Contrast and Reduce Transparency fallbacks | W1, W3 |

Verification for every PR: before/after recording of the affected flow, the must-haves it touches checked in the
real app, and the R2 craft score for that surface updated.

---

## 7. Decisions (Chen, 2026-11-18)

1. **Apps to beat:** Safari on iPhone, Arc on the Mac. R3 measures every moment against these two first; Chrome,
   Dia and Orion are secondary references.
2. **Handoff between iPhone and Mac: yes.** W7 is approved in scope. R4 designs it: the page open on one device
   shows in the other's Dock and App Switcher via `NSUserActivity`, Incognito tabs never advertise, and the receiving
   side opens the page in the right place (Mac: the current space's Today; iPhone: a new tab on top of the fan). It
   must respect must-haves 10, 11 and 13; check them in the real app.
3. **Language: English only, done properly.** No translations. The String Catalog is there for English quality,
   not localization:
   - every user-facing string in one `Localizable.xcstrings` per target, so copy is reviewed in one place against
     the R4 copy rules;
   - plurals and agreement handled by the catalog and automatic grammar agreement (`^[\(count) tab](inflect: true)`),
     never `"\(n) Tabs"`;
   - dates, times, sizes, percentages and lists through `FormatStyle` (`.relative`, `ByteCountFormatStyle`,
     `.list(type: .and)`), never hand-built strings;
   - an English glossary (Archive, Today, Pinned, Favorites, Space, Incognito, Live Folder) and a lint check in CI
     that fails on a literal user-facing string outside the catalog, if one can be made cheaply.
