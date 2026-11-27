# Full QA cycle

How to run a complete QA pass on Boaz for iPhone and Mac before a release or after a large change. A full cycle takes
about half a day. Go through the sections in order and write every problem down as you find it (see
[Reporting](#reporting)). Fix after the pass, not during it, so one fix can't hide the next bug.

## 1. Prepare

**Build.** Start from the commit you are testing, then generate the project and build:

```sh
git switch master && git pull --ff-only
make bootstrap        # checks the toolchain, generates Boaz.xcodeproj
make build            # BoazKit plus both apps, unsigned: the same check CI runs
```

To run the apps, open `Boaz.xcodeproj` in Xcode and run `Boaz-iOS` or `Boaz-macOS` with your team selected. Test a
**Release** build at least once per cycle (Product › Scheme › Edit Scheme › Run › Build Configuration), because
Debug builds are slower and include `#if DEBUG` code.

**Use a separate iCloud account for sync.** A team-signed build syncs spaces, pins and tabs into whichever iCloud
account the device is signed in to. Use a test Apple Account on the test devices so QA data never mixes with your
real library. Debug builds talk to the CloudKit **development** environment. Release builds (including
`make device DEVICE=<udid>`), the DMG, TestFlight and the App Store use **production**. The two are separate
databases, so a Debug build never syncs with the DMG; check sync with Release builds too.

**Start from a clean state.** First runs and upgrades are where most bugs live, so test both:

| | Fresh install | Upgrade |
|---|---|---|
| iPhone (device or simulator) | Delete the app. On a simulator: `xcrun simctl uninstall <udid> com.chenkahana.boaz` | Install the last released build, use it for a bit, then install the new one over it |
| Mac | Quit Boaz, then move `~/Library/Containers/com.chenkahana.boaz` aside (it holds the library, `boaz.sqlite`, and settings) | Run the new build on top of an existing container |

The Mac container is your own Boaz data if you use Boaz day to day. Move it, don't delete it, and move it back
afterwards.

**Devices.**
- iPhone: a standard iPhone **and** an iPhone Duo. The iOS simulator only drives the Duo's folded cover screen, and
  posture can't be changed there, so the open, book and laptop layouts need a real Duo.
- Mac: test once at the minimum window size (720 × 492) and once at full screen on a large display.
- Run both apps in light and in dark appearance.

## 2. Screens and menus

On each screen, check what the user sees: text isn't cut off or overlapping, fonts and sizes match the screens around
them, colors have enough contrast (watch secondary text on tinted backgrounds), spacing is even, and empty, loading
and error states look intentional. Check RTL text too (for example ynet.co.il).

### iPhone

- [ ] **Onboarding**: every page, with iCloud on and off. Buttons are readable, Back and Continue work, and it never
      shows again after you finish.
- [ ] **Bottom bar** (standard iPhone, unfolded Duo held upright): the tab fan, **+** (New Tab) and **…** (page
      menu). The page ends above the bar and is never covered by it. Open a new tab: it's the fan's top card at once,
      with the previous tab behind it.
- [ ] **Side rail** (folded Duo): the same controls stacked below the status icons, and the page's edge colors in the
      safe areas.
- [ ] **Search panel** (New Tab): suggestions from the search engine, open tabs and history; typing an address versus
      a search; nothing is sent in Incognito or with suggestions off.
- [ ] **Tab carousel** (tap the tab fan): tap a card to open it, swipe up to archive it, and the gear opens Settings.
- [ ] **Page menu**: every item. Back, Forward, Reload, Share, Pin, Reader, Find on Page, Translate, Listen to Page,
      text size, desktop/mobile site, Website Settings (camera, microphone, pop-ups, content blocking).
- [ ] **Settings**: every row, and every link in About opens the right page.
- [ ] **Incognito**: enter and leave it. Nothing shows up in history, Today or the tab carousel afterwards.
- [ ] **Duo postures** (real device): folded, open (sidebar next to the page), book, laptop. Move the hinge while a
      video plays: the page must never reload.
- [ ] **Outside the app**: share a link to Boaz from Safari (share extension), the search widget, the App Shortcuts
      "Search in Boaz" and "Open in Boaz", and these links in Safari:
      `boaz://open?url=https://example.com`, `boaz://search?q=test`, `boaz://search`.
      `boaz://open?url=javascript:alert(1)` must do nothing.
- [ ] **Alternate app icons** in Settings.
- [ ] **Default browser** (once Apple grants the entitlement; `docs/default-browser.md`): Settings shows the button
      or the confirmation correctly; set Boaz as the default in Settings › Apps › Default Apps and confirm a link
      tapped in Mail or Notes opens it, with the URL's path, query and fragment unchanged, cold and warm; a
      Universal Link to another app still opens that app.

### Mac

- [ ] **Onboarding**: Welcome, Bring your browser, Make default browser, You're all set. Secondary buttons are
      readable in both appearances.
- [ ] **Main window**: empty space, sidebar with pinned, favorites and Today, a long renamed tab title, the sidebar
      hidden and the peek on hovering the left edge, full screen.
- [ ] **Command bar**: ⌘T (empty) and ⌘L (current address). The text field is focused every time; alternate ⌘T and
      ⌘L about 10 times and type straight away each time.
- [ ] **Every menu in the menu bar**: Boaz, File, Edit, View, History, Tabs, Spaces, Window, Help. Every item does
      something, and every shortcut shown works.
- [ ] **Context menus**: a Today row, a favorite tile, a space dot, the sidebar **+**.
- [ ] **Page context menus**: right-click a page, a link, an image, an image inside a link, a selection, an empty
      editable field, a misspelled word, a password field, a video, an audio element, an iframe, and an item from an
      extension with `contextMenus`, in a normal window, an Incognito window and a Quick Window. Every shown item
      works, disabled items are disabled, every shown shortcut fires from the menu bar, and there are no doubled or
      edge separators. Save As, Save Link As and Print open on the right window; View Page Source opens a
      `view-source:` tab; Open Link in New Window opens a full Boaz window; Copy Link to Highlight copies a
      `#:~:text=` URL.
- [ ] **Spaces**: new space, theme editor, switching with ⌃1… and ⌘⌥→, deleting a space.
- [ ] **Folders**: create, rename, ungroup, drag tabs in and out, drag to reorder.
- [ ] **Split view**, **Find in page**, **Peek** (a link that opens a new window from a pinned tab), **Summarize
      Page**, **Ask This Page**, **Tidy Tabs**.
- [ ] **Links in new tabs**: a middle-click or ⌘-click on a link opens it in a background tab right below the current
      one; ⌘⇧-click opens it in front.
- [ ] **History** and **Archive** windows: today's visits sit under "Today", and ⌘W closes the window.
- [ ] **Settings**: General (the About links are visible without scrolling), Privacy, Sync (Sync Now is disabled when
      sync can't run), Shortcuts (rebind one key, then reset it). ⌘W closes the window.
- [ ] **Incognito window** and its command bar.
- [ ] **Quick Window**: `open -a Boaz https://example.com` from Terminal opens it, File › New Quick Window
      opens it, and "Open in Boaz" moves the page into the main window.
- [ ] **Import**: from Arc (use a copy of an Arc data folder, not your own), and from Chrome, Brave, Edge and Safari
      bookmarks.
- [ ] **Window**: the sidebar is never see-through to other apps' windows, and keeps the space's theme on every
      site, dark or light; the selected row stays readable on every theme.

## 3. Behavior that must hold

- [ ] **Restore**: quit and relaunch. The same space, tab and scroll position come back on both apps, with several
      Mac windows open.
- [ ] **Background (iPhone)**: open a tab, then go to the Home Screen right away. Force-quit from the app switcher
      and reopen: the tab must still be there.
- [ ] **Today and the Archive**: Archive Today's Tabs, check the tabs appear in the Archive, reopen one.
- [ ] **Sync** (two devices on the test Apple Account): pin, favorite, rename and delete on one device and see each
      change on the other. Each device keeps its own Today list, and the iPhone can open the Mac's tabs. Then turn on
      Airplane Mode, make changes, turn it off, and check that nothing is lost or duplicated.
- [ ] **Password sync** (team-signed builds on the test Apple Account, iCloud Keychain on both): save a password on
      the DMG and fill it on the iPhone, then the reverse. Change the password on one device and fill the new one on
      the other; delete it on one (one confirmation) and it's gone from the other. Turn iCloud Keychain off on one
      device: what it saves stays there. The
      dev-signed DMG (`com.chenkahana.boaz.chromium.dev`) sees none, by design.
- [ ] **AutoFill (iPhone)**: Settings › Passwords › Use Boaz Passwords in Other Apps, accept iOS's prompt, and the row
      reads Used in Other Apps. In Safari, a login field's key icon › Boaz asks for Face ID, lists the site's
      sign-ins first, searches, and fills the one picked. The suggestion above the keyboard fills after Face ID too;
      Cancel at Face ID fills nothing. With no saved passwords the list says No Saved Passwords.
- [ ] **Load errors**: an unknown host (`https://nonexistent.invalid`), connection refused (`http://localhost:9`),
      offline. Each shows an error page with the address kept, no padlock, and Reload retries it.
- [ ] **Redirects**: a site that redirects (for example `http://ynet.co.il`) leaves one History entry, not two.
- [ ] **Odd input** in the address bar: `javascript:…` and `file://…` become searches and never run. A 3,000-character
      URL, plain words, and emoji all behave.
- [ ] **Accessibility**: VoiceOver reads every control with a sensible label. The largest Dynamic Type size (iPhone)
      doesn't cut text off. Reduce Motion is respected, and every Mac control can be reached from the keyboard.

## 4. Speed and stress

Measure a Release build. Write down the number for each row and compare it with the previous cycle. Anything worse
than the previous cycle is a bug.

| What | How | Baseline (Mac, Debug, before #12) |
|---|---|---|
| Launch to first window | Time from launch until the window is drawn, warm | 1.7–2.9 s |
| New tab to page title | `open -a <copy> <url>` (the 150-tabs row's own mechanism), until the title shows | 0.7–3.1 s, depending on the site |
| Typing in the command bar with a large history | Import or load about 50,000 visits, then type; each keystroke must feel instant | ~14 ms of main-thread time per keystroke |
| Many tabs | Open 150 tabs. The time to open the next one must stay flat | Grew from 1.1 s to 1.8 s |
| Archive Today's Tabs with 150+ tabs | Time until the sidebar settles | 2.9 s |
| Memory | `footprint -p Boaz` with 10 and with 150 tabs | 85–150 MB for the app process, peak 273 MB |

These numbers were taken by hand on WebKit Debug builds before #12 (PR #22 added the table; no method, machine or
run count was recorded), on an engine this product no longer ships. They are kept only for reference, one cycle,
until `Tools/perf/` below produces a dated, comparable Chromium-engine column to replace this note.

### Method (PLAN-04): `Tools/perf/`

`Tools/perf/perf.py` re-runs every row above against the *published* release DMG — never a local build, and never
the installed Boaz — on a copy re-branded as the development identity (`com.chenkahana.boaz.chromium.dev`,
the same one `make device`'s dev builds use) with no entitlements, launched under a throwaway `HOME` +
`CFFIXED_USER_HOME`, with Sparkle and iCloud sync off. Must-have #13 (Chen's real library and CloudKit are
untouchable) is enforced by guards that abort the whole run — the copy's identity, non-empty entitlements on it,
another dev-identity process already running, or any change to Chen's real `~/Library/Application Support/Boaz`,
`~/Library/Containers/com.chenkahana.boaz` or its defaults domain, measured before and after each row — rather
than by hoping the isolation holds.

- **Run it:** `Tools/perf/run.sh [dmg-tag] [N]` (default `v0.4.48`, `N=7`). Only on the orchestrator's go, with the
  Mac idle and on AC power, and never while Chen is screen-sharing — every row opens a real window, and typing/
  archive (skipped by default; see below) also drive the keyboard. Chen's own production Boaz may stay running
  (different bundle id); no other `com.chenkahana.boaz.chromium.dev` process may be, PLAN-16 dev builds included.
  Takes about 25 minutes. Writes `results.json` and `results.md` (the table below's format) under
  `~/tmp/codex/boaz-perf/<UTC timestamp>/`.
- **Fixtures:** `Tools/perf/seed` (SwiftPM, `BoazKit`'s public API only — `recordVisit`, `save`, `updateSpace`)
  seeds each row's throwaway `HOME` with the 50,000-visit history or the 10/150 Today-tab variants it needs, at
  the path the dev identity actually resolves (`.../Application Support/com.chenkahana.boaz.chromium.dev/Boaz/`).
- **Isolation history**: the first version of this harness kept the copy's bundle id as production and relied on
  `CFFIXED_USER_HOME` to confine `defaults`/`NSUserDefaults` to the throwaway HOME. Confirmed live that this
  doesn't hold on an unsandboxed process (cfprefsd resolves the real UID's home regardless of the environment),
  and that wrapping the launch in `sandbox-exec` doesn't fix it either (cfprefsd writes on the client's behalf, so
  the client's own sandbox doesn't redirect it) — a plain `defaults write` landed in the real
  `~/Library/Preferences` either way. The fix re-brands the copy as the development identity instead of fighting
  cfprefsd: any prefs write that still escapes HOME redirection lands in that identity's own domain, never Chen's
  production one. In-process path resolution (`FileManager`, `NSHomeDirectory`) does honor the fixed HOME, so the
  store and the Chromium profile stay isolated as before; see plan/items/04-performance-baselines.md's Approach
  for the full writeup, including why a dedicated macOS user (the gold standard) is offered to Chen rather than
  required.
- **Reworked (2026-11-26):** launch, new tab, many-tabs and memory now drive the app only through the automation
  channel (`Tools/chromium/automation_client.py`, same as PLAN-16) or `open -a <copy> <url>` — the OS's own
  URL-open-in-app mechanism, not CDP and not synthetic input — so none of them need an Accessibility grant any
  more. The omnibox (typing) and the sidebar's context menu (archive) are native chrome that CDP can't reach and
  Boaz has no scripting dictionary or URL scheme for, so those two still drive System Events and are skipped by
  default (`perf.py all --include-accessibility-rows` to include them once granted; reported as
  "needs Accessibility grant (Chen)" otherwise).
- **What needs Chen first:** typing/archive need an Accessibility grant for whatever runs the harness, per above.
  `Tools/perf/perf.py guard-check` reports whether the isolation guards currently pass without launching anything.
  The iPhone columns stay "not measured (needs device)" until Chen picks a spare or disposable device.
- **Status:** tooling built and self-tested without launching any GUI app (`swift build` on the seed tool with a
  verified store at the dev-identity path, `window-wait.swift` against a window-less pid, `perf.py`'s guards —
  including a live run that correctly caught a real PLAN-16 dev build already running — isolation staging
  (download, verify, mount, re-brand, re-sign, verify) and the page server exercised for real; see
  plan/items/04-performance-baselines.md's Progress log). No GUI row has been run yet — this table's baseline
  column is unchanged until a live session produces one.

To see where main-thread time goes, run `sample Boaz 5 -file out.txt` while doing the slow thing, or use Instruments
(Time Profiler, plus Allocations for memory).

**Stress, with no crash, hang or wrong state allowed:**

- [ ] Press each of these 20–30 times quickly: ⌘T, ⌘W, ⌘D (pin), ⌘R, ⌃Tab, ⌘⌥→. Afterwards there must be no
      duplicate bars or tabs, and pins and tabs must be where you expect.
- [ ] Resize the window while a page loads. Enter and leave full screen and split view repeatedly.
- [ ] iPhone: flick through the tab carousel with 100+ tabs, archive tabs quickly in a row, and switch between apps
      while a page loads.
- [ ] Afterwards, check `~/Library/Logs/DiagnosticReports` (Mac) and Settings › Privacy & Security › Analytics &
      Improvements › Analytics Data (iPhone) for new `Boaz` crash reports.

## 5. UI tests

`make uitest` runs `Tests/BoazUITests` (XCUITest) against the Mac app: every screen opened the way a user opens it
(`ScreenTests.swift`), an everyday flow end to end (`SmokeTests.swift`), plus the Library panel, App Icon and live
folder suites. Each screen must be hittable, inside its window, have every control labeled, no overlapping buttons, and
pass the system accessibility audit (all of it but contrast, which samples the screen and varies from run to run;
check contrast by eye, as in section 2); a screenshot of each lands in `build/UITestResults.xcresult`. CI runs the same
target on every pull request and every push to master and release branches, and uploads that result bundle as the
run's `UITestResults` artifact (kept 7 days when the run fails, 3 when it passes).

- **Run:** `make uitest`. To look at a failure: `xcrun xcresulttool get test-results summary --path
  build/UITestResults.xcresult`, and `xcrun xcresulttool export attachments --path build/UITestResults.xcresult
  --output-path <dir>` for the screenshots and accessibility hierarchy dumps (`manifest.json` maps them to tests).
- **UI test health:** a green tick says nothing failed, not that everything ran. Read the **Mac UI tests** job's
  summary on the run page: passed, failed and skipped counts, then the name and message of each failed and skipped
  test. For a red run, download the `UITestResults` artifact, unzip it, and run the two `xcresulttool` commands above
  on it; add `--test-id "Suite/test()"` to export one test's attachments. Each failure carries the app's
  accessibility hierarchy at the moment it failed (the largest `.txt`), a screenshot, and a screen recording of the
  whole test (`.mp4`); the recording usually shows a flake's cause. The expected skips, all on CI's WebKit build:
  `ChromiumExtensionsUITests` ×9 (no `BOAZ_UITEST_APP`), `ScreenTests.testAISheet` (no Apple Intelligence on the
  runner), `ScreenTests.testRemovePinnedTabConfirmation` (the runner isn't trusted for Accessibility, so it can't
  middle-click) and `ScreenTests.testQRCodeSheet` (quarantined, #187). Any other skip is new and needs a look. A test
  is quarantined only after a root-cause attempt fails: one issue per test titled `UI test quarantined: Suite.test`
  (run links, failure text, hypothesis), and `throw XCTSkip("Quarantined: #NNN …")` as the test's first line. Never
  `-skip-testing` or `continue-on-error`. Pushes to master and release branches each finish their own run (a later
  push doesn't cancel it), so every red run on them stays visible.
- **Chromium build:** set `BOAZ_UITEST_APP=<path to the staged .app>` to run the same suite against it instead of the
  WebKit app the scheme builds.
- **Isolation:** the test build is ad hoc signed with its own bundle id, `com.chenkahana.boaz.uitest`, so its sandbox
  container, defaults and Keychain are never the installed Boaz's. `-BoazUITest YES` (`UITestMode`) gives each launch
  a fresh store in a temporary folder, seeded from `Tests/BoazUITests/Fixtures/*.json`, wipes the test build's
  defaults, turns off iCloud sync and onboarding (`-BoazResetOnboarding YES` brings it back), and keeps GitHub on canned
  answers. Fixture pages are `data:` URLs, so tests don't use the network. Downloads (and the Library panel's
  list of them) go to a temporary folder, never `~/Downloads`.
- **First run on a Mac:** XCUITest needs Automation Mode, which macOS asks an administrator to approve once (or run
  `sudo automationmodetool enable-automationmode-without-authentication`). Don't use the Mac while the suite runs: it
  moves the pointer and types.

## Reporting

Report each problem as a GitHub issue with:

- a short title saying what is wrong, not where it was found;
- the device and OS, the build (commit or TestFlight number) and the appearance (light or dark);
- steps to reproduce, then what happened and what you expected;
- a screenshot or screen recording for anything visual, and the numbers for anything slow;
- a severity: **P1** breaks a core flow or loses data, **P2** clearly wrong or slow, **P3** polish.

A cycle is done when every checkbox above is ticked or has an issue filed against it, and no P1 is open.
