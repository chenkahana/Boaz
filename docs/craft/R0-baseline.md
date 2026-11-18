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
