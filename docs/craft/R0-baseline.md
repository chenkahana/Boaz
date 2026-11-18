# R0. Baseline capture

Code: `origin/master` 66c3d63 (0.4.25). Binaries live under `~/tmp/codex/boaz-craft/` on Chen's Mac (not in git);
paths below are relative to that folder.

## R0.1 Builds

| Build | Status | How | Notes |
|---|---|---|---|
| iPhone, Duo simulator (folded cover screen) | Installed | `xcodebuild -scheme Boaz-iOS -configuration Debug -destination 'generic/platform=iOS Simulator'`, installed on a dedicated simulator "Boaz Craft Duo" (`BE5E8A2D-3386-44E3-A3A6-291A38270B25`, iOS 27.1) | Debug build. The folded cover screen shows the **side rail**, not the bottom bar. |
| iPhone, standard device (bottom bar) | **Needs device** | `make device DEVICE=<udid>` | The iOS 27.1 simulator runtime (the deployment target) only offers the iPhone Duo device type; iPhone 17 Pro exists only for iOS 26.4. The bottom bar layout (must-have 7) can't be seen in a simulator. |
| iPhone Duo open, book, laptop | **Needs device** | Real Duo | The simulator can't change posture (`docs/qa.md` §1). |
| Mac App Store build (WebKit) | Built, run isolated | Debug, ad hoc signed, bundle id `com.chenkahana.boaz.uitest`, launched with `-BoazUITest YES` and a `Tests/BoazUITests/Fixtures` library (fresh temp store, no iCloud) via `open -g` so it never takes focus | Same UI code as the App Store build. Static captures only: a background app ignores keystrokes, and activating it would take over Chen's session. |
| Mac DMG (Chromium) | Chen's install only | `/Applications/Boaz.app` is 0.4.25, the same commit | Chen is running it with his library and Chromium profile. Not launched a second time (must-have 13: never touch `~/Library/Containers/com.chenkahana.boaz` or `~/Library/Application Support/Boaz/Chromium`). **Needs Chen session** for every DMG runtime capture. |

Harness (research scaffolding, not in git): `harness/` holds an XCUITest bundle that drives the installed iPhone app in
the simulator by bundle id (taps, typing, screenshots, `performAccessibilityAudit`), generated from an untracked
`craft.yml` that includes `project.yml`. `run-ios.sh <Class/test> <name> [record]` runs one flow and optionally
records the primary display with `simctl io recordVideo`. `mac-shot.sh <name> <fixture> <light|dark> [WxH]` captures
the isolated Mac build's window with `screencapture -l` without activating it. `tools/ax` dumps the Mac menu bar
through the Accessibility API by pid.

### Needs Chen session (Mac, exact steps)

Run these on the DMG with a throwaway profile, or on the isolated test build, while nobody else uses the Mac:

1. `make uitest` from `~/.worktrees/Boaz/craft-research` (moves the pointer; ~10 min). Screenshots of every screen land
   in `build/UITestResults.xcresult`; export with `xcrun xcresulttool export attachments --path
   build/UITestResults.xcresult --output-path ~/tmp/codex/boaz-craft/uitest-mac`.
2. QuickTime › New Screen Recording, 120 Hz display, for each flow in R0.2's Mac list, Light then Dark.
3. Instruments › Animation Hitches attached to Boaz while doing: sidebar drag, space switch (⌃1/⌃2), ⌘T then type,
   split view open/close, library panel open/close. Instruments › App Launch on a cold launch of the DMG.

## R0.2 Recordings

Simulator recordings are 60 Hz (`simctl io recordVideo`); 120 Hz frame-stepping needs a ProMotion device. Every
recording has a matching screenshot set with an accessibility hierarchy dump (`.txt`) and, per screen, an XCUITest
accessibility audit (`.audit.txt`).

| Flow | Platform | Light | Dark | Screenshots |
|---|---|---|---|---|
| Fresh install: onboarding → empty browser → search panel → type → first page → page menu → second tab → error page → Library → Settings | iPhone (Duo folded) | `rec/main.mov` | `rec/main-dark.mov` | `shots/ios/main/`, `shots/ios/main-dark/` (01–16) |
| Relaunch → tab carousel → page through → swipe up to archive (Undo toast) → open card → toolbar swipe → page menu bottom → Archive Tab | iPhone (Duo folded) | `rec/tabs.mov` | `rec/tabs-dark.mov` | `shots/ios/tabs/`, `shots/ios/tabs-dark/` (20–27) |
| Main window with a library (standard fixture), empty library, one space, minimum size 720 × 492 | Mac (WebKit, isolated) | `shots/mac/mac-light-main.png`, `shots/mac/min-light-*.png`, `shots/mac/empty-light-*.png` | `shots/mac/std-dark-*.png` | static only |
| Menu bar inventory (titles, shortcuts) | Mac (WebKit, isolated) | `shots/mac/menus-webkit-adhoc.txt` | | Enabled state is not meaningful: a background app has no key window, so most items read disabled |

Not recorded, and why:

- **Standard iPhone bottom bar, Duo open/book/laptop and the posture change**: needs device (see R0.1).
- **Every Mac flow in motion** (launch, ⌘T/⌘L command bar, sidebar drag, space switch, split view, library panel,
  settings, onboarding) and **every DMG (Chromium) screen**: needs Chen session. Keystrokes and clicks only reach an
  active app, and activating one takes over the Mac Chen is using.

## R0.3 Instruments and launch numbers

| Measure | Result | Evidence | Caveat |
|---|---|---|---|
| iPhone launch to first frame (`XCTApplicationLaunchMetric`, 5 runs, 2–3 tabs open) | **2.39–2.92 s** (median 2.50 s) | `results/launch-ff-*.xcresult` | Debug build on the simulator. Plan target is ≤ 400 ms on a device Release build; re-measure there before treating this as a regression. |
| iPhone launch until responsive (`waitUntilResponsive: true`) | **3.60–4.31 s** (median 4.19 s) | `results/launch-*.xcresult` | Same. The ~1.5 s gap between first frame and responsive says the main thread stays busy after the first frame (restore, snapshots, sync); worth a device Time Profiler trace. |
| iPhone App Launch trace | Recorded ×3 | `traces/ios-launch-{1,2,3}.trace` | The simulator records CPU and thread state but leaves the lifecycle table empty, so phases (dyld, `didFinishLaunching`, first frame) need a device. |
| iPhone Animation Hitches | **Not supported** in the simulator ("Hitches is not supported on this platform") | `traces/ios-hitches-1.trace`, `traces/hitch.log` | Needs device. The flow to trace is ready: `Motion/testMotion` (carousel ×3, paging, page menu, scroll). |
| Mac (WebKit, Debug, isolated) launch to window on screen | **0.36–0.66 s** (3 runs) | measured by polling `CGWindowList` after `open -g` | Window exists; first content frame not measured. DMG cold launch: needs Chen session. |
| Mac Animation Hitches, Mac App Launch template | Not recorded | | Needs Chen session (R0.1 steps). |
