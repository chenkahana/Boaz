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
      menu). The page ends above the bar and is never covered by it.
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
- [ ] **Spaces**: new space, theme editor, switching with ⌃1… and ⌘⌥→, deleting a space.
- [ ] **Folders**: create, rename, ungroup, drag tabs in and out, drag to reorder.
- [ ] **Split view**, **Find in page**, **Peek** (⌘-click a link), **Summarize Page**, **Ask This Page**, **Tidy
      Tabs**.
- [ ] **History** and **Archive** windows: today's visits sit under "Today", and ⌘W closes the window.
- [ ] **Settings**: General (the About links are visible without scrolling), Privacy, Sync (Sync Now is disabled when
      sync can't run), Shortcuts (rebind one key, then reset it). ⌘W closes the window.
- [ ] **Incognito window** and its command bar.
- [ ] **Quick Window**: `open -a Boaz https://example.com` from Terminal opens it, File › New Quick Window
      opens it, and "Open in Boaz" moves the page into the main window.
- [ ] **Import**: from Arc (use a copy of an Arc data folder, not your own), and from Chrome, Brave, Edge and Safari
      bookmarks.
- [ ] **Window**: the sidebar is never see-through to other apps' windows. When a dark site tints the sidebar, the
      selected row stays readable.

## 3. Behavior that must hold

- [ ] **Restore**: quit and relaunch. The same space, tab and scroll position come back on both apps, with several
      Mac windows open.
- [ ] **Background (iPhone)**: open a tab, then go to the Home Screen right away. Force-quit from the app switcher
      and reopen: the tab must still be there.
- [ ] **Today and the Archive**: Archive Today's Tabs, check the tabs appear in the Archive, reopen one.
- [ ] **Sync** (two devices on the test Apple Account): pin, favorite, rename and delete on one device and see each
      change on the other. Each device keeps its own Today list, and the iPhone can open the Mac's tabs. Then turn on
      Airplane Mode, make changes, turn it off, and check that nothing is lost or duplicated.
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
| New tab to page title | ⌘T, type an address, Return, until the title shows | 0.7–3.1 s, depending on the site |
| Typing in the command bar with a large history | Import or load about 50,000 visits, then type; each keystroke must feel instant | ~14 ms of main-thread time per keystroke |
| Many tabs | Open 150 tabs. The time to open the next one must stay flat | Grew from 1.1 s to 1.8 s |
| Archive Today's Tabs with 150+ tabs | Time until the sidebar settles | 2.9 s |
| Memory | `footprint -p Boaz` with 10 and with 150 tabs | 85–150 MB for the app process, peak 273 MB |

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

## 5. Automated UI runs (optional)

XCUITest can drive both apps for the screenshot and timing passes. On the Mac it needs Automation Mode, which macOS
asks an administrator to approve the first time (or run
`automationmodetool enable-automationmode-without-authentication` as an admin). Without Automation Mode, do the
cycle by hand.

## Reporting

Report each problem as a GitHub issue with:

- a short title saying what is wrong, not where it was found;
- the device and OS, the build (commit or TestFlight number) and the appearance (light or dark);
- steps to reproduce, then what happened and what you expected;
- a screenshot or screen recording for anything visual, and the numbers for anything slow;
- a severity: **P1** breaks a core flow or loses data, **P2** clearly wrong or slow, **P3** polish.

A cycle is done when every checkbox above is ticked or has an issue filed against it, and no P1 is open.
