# Changelog

All notable changes to Boaz are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.48] - 2026-11-25

### Changed

- Mac: Picture in Picture floats above every window, on every Space and display, including over full-screen apps,
  whichever app is active. Drag it anywhere, onto any display, and it settles neatly against the nearest edge or
  corner. It keeps its video's shape as you resize it.
- Mac: Picture in Picture has new controls, modeled on YouTube's player. They appear when the pointer is over the
  video and fade when it's still: play and pause, 10 seconds back and forward, a seek bar with the buffered range and
  a time preview, current time and length, volume and mute, playback speed, back to tab and close. Click the video to
  play or pause. YouTube's keys work too: space or K, J and L, the arrows, M, F (back to tab), 0–9, and < and > for
  speed.

## [0.4.46] - 2026-11-25

### Added

- A special-edition app icon, Sunset Drive: a teal pretzel in front of a banded neon sun, palm trees and a violet sea.
  Pick it in Settings › App Icon on the iPhone and the Mac; on the Mac it becomes the Dock icon.

## [0.4.45] - 2026-11-25

### Fixed

- Mac: maps and other WebGL pages (yad2's map, for one) stay working. A Chromium diagnostic check meant only to
  report a problem kept crashing Boaz's graphics process, and after a few crashes Chromium turned WebGL off until the
  next relaunch. The check now reports without crashing, as it does in Chrome.

## [0.4.44] - 2026-11-25

### Changed

- Mac: coming back to a tab whose page was unloaded shows how you last left it, sharp and at full size, while the page
  reloads, even after a relaunch. The image is kept in Boaz's cache folder (at most 200 MB per profile), deleted when
  the tab is closed, never written for Incognito tabs and never synced. The "Saved preview" caption is gone.

Crash reports reviewed: no GitHub issues opened since 0.4.37; no Boaz crash reports on the build Mac since 0.4.40
(two renderer reports on 2026-11-24 came from local development builds, not the released app). Known, pre-existing and
not from this release: since 2026-11-24 a live folder created on the Mac fails to upload to iCloud ("Cannot create or
modify field 'liveSource' in record 'SidebarItem' in production schema"); the rest of the library syncs, and the fix is
deploying the iCloud schema to production, not an app change. App Store Connect and Xcode Organizer crashes were not
checked (not signed in on this Mac).

## [0.4.43] - 2026-11-24

### Added

- Handoff between the iPhone and the Mac: the page in the tab you're looking at can be picked up on your other
  device. Incognito tabs, history and failed pages are never offered.

## [0.4.42] - 2026-11-24

### Added

- iPhone: Incognito looks different: dark violet chrome, "Private" on the bar's new-tab button, and its own empty
  page.
- iPhone: a New Tab control for Control Center, the Lock Screen and the Action button.
- iPhone: pinned tabs and favorites show up in Spotlight (nothing else is indexed; the index stays on the iPhone).
- iPhone: press and hold a tab card for Copy Link, Share and Archive Tab; press and hold the tab fan for New Tab,
  Incognito and Archive Tab.
- iPhone with a hardware keyboard: ⌘T opens a new tab and ⌘L the address.
- Mac: VoiceOver's rotor can jump between pinned tabs and between Today tabs.

### Fixed

- The medium widget shows your favorites' real site icons instead of letters.
- Mac: with Reduce Transparency on, a translucent space theme turns solid instead of washing out to grey.
- iPhone: with Increase Contrast on, the highlighted search suggestion and the page menu's tiles stand out more.

### Changed

- iPhone: the page menu labels its two groups, "This Tab" and "Boaz".

Crash reports reviewed: no GitHub issues opened since 0.4.37; no Boaz crash reports on the build Mac since
2026-11-19 (one disk-writes resource report for a Chromium helper on 2026-11-23, as on 2026-11-20; not a crash).
App Store Connect and Xcode Organizer crashes were not checked (not signed in on this Mac).

## [0.4.41] - 2026-11-24

### Added

- Mac: double-click the split divider to even the panes; the divider holds at the middle while dragging, with a
  tap on a trackpad.
- Mac: folders spring open when a dragged tab rests over them.
- Mac: in the Library panel, ⌘1–⌘4 and ⌘↑/⌘↓ move between Media, Downloads, Spaces and Archive.
- Mac: VoiceOver's Actions rotor on a sidebar tab offers Archive (or Unload), Pin, Rename and Open in Split View.
- iPhone: setup pages turn with a swipe.
- iPhone: press and hold a rail or bar button at accessibility text sizes to see it large; Voice Control also
  answers to "Menu" and "More" for the … button.

### Fixed

- Mac: the split divider shows at rest, not only under the pointer.
- Mac: the sidebar and split divider stretch a little past their limits and settle back, instead of stopping dead.
- Mac: in a short window the Library panel fits beside the sidebar, and a Today list cut off at the bottom fades
  there.
- Mac: the command bar is solid with Reduce Transparency on, and a split's focused pane is easier to tell on the
  DMG.
- VoiceOver on iPhone says when a tab's card is a page that couldn't open.

Crash reports reviewed: no GitHub issues opened since 0.4.37; no Boaz crash reports on the build Mac since
2026-11-19. App Store Connect and Xcode Organizer crashes were not checked (not signed in on this Mac).

## [0.4.40] - 2026-11-24

### Fixed

- Mac: switching to a tab whose page was unloaded keeps showing its last look while the page reopens, instead of a
  blank "Opening page…" spinner, and no error flashes while the page attaches.
- Mac: a page that won't load uses the same titles and symbols as the iPhone: "Can't Open This Page", "You're
  Offline" or "This Page Stopped Responding".
- Mac: the find bar's buttons read "Previous Match", "Next Match" and "Close Find Bar".

Soak: 0.4.37, the last engine release, ran for 28 hours on the build Mac (installed through Sparkle 2026-11-22
22:21 IST, running since 2026-11-23 07:40) with no WebKit-internals fallbacks logged and no Boaz crash reports.
iPhone sync convergence was not checked.

Crash reports reviewed: no GitHub issues opened since 0.4.37; no Boaz crash reports on the build Mac since
2026-11-19 (tonight's crashpad reports belong to another app). App Store Connect and Xcode Organizer crashes were
not checked (not signed in on this Mac).

## [0.4.39] - 2026-11-23

### Fixed

- A page that won't load says which of three things happened, with the same title and symbol on the Mac and the
  iPhone: "Can't Open This Page", "You're Offline" or "This Page Stopped Responding".
- iPhone: reopening a tab whose page failed shows "Can't Open This Page" while it tries again, instead of a blank
  page.
- iPhone: the "Swipe the toolbar" tip waits until the page has finished loading.
- iPhone: offline, the search panel says that suggestions return when you're connected, and the empty browser's
  New Tab button no longer shows through behind the panel.
- Mac: errors in toasts and the share sheet are plain sentences; the system's details go to the log.
- VoiceOver on iPhone says what each search suggestion does (Search, Open Address, Switch to Tab, History); on the
  Mac, history rows in the command bar say "History".

### Changed

- The Archive has one name everywhere, and empty lists read "No Archived Tabs", "No History", "No Downloads".
- Settings labels are title case on both platforms, and "Archive Inactive Tabs After" no longer repeats "After".
- iPhone setup leads with browsing: Continue is the main button, and Sign In to iCloud is offered beside it.
- Share sheet buttons read "Pin to Sidebar" and "Add to Tabs".

## [0.4.38] - 2026-11-23

### Fixed

- Mac: page loading shows as a thin bar in the address field after a short pause, instead of a spinner over the
  page.
- Mac: each window is named after its page in the Window menu, Mission Control and the Dock; Incognito windows
  are named "Incognito".
- iPhone: the tab fan, + and … are one 48 pt size, so the tab fan is easier to hit.
- iPhone Duo: rows and close buttons in the half-open tab strip are 44 pt tall.
- iPhone: the page menu fades its last visible row when more rows sit below, instead of cutting it in half.
- iPhone: at accessibility text sizes the page menu opens full height, its Back, Forward, Reload and Share tiles
  show only their symbols (press and hold to read the name), and row titles wrap instead of truncating.
- The Mac toast UI test waits for the toast instead of racing it.

Crash reports reviewed: no GitHub issues opened since 0.4.37; no Boaz crash reports on the build Mac. App Store
Connect and Xcode Organizer crashes were not checked (not signed in on this Mac).

## [0.4.37] - 2026-11-22

### Fixed

- iPhone: a script-opened window (a PayPal or bank checkout step) keeps its connection to the page that opened it, so the result reaches the page.
- iPhone: a blocked pop-up now says so, with a button to open it once.
- iPhone Duo: the portrait status bar is the live system one (battery, cellular, Wi-Fi) instead of a drawn copy.
- Mac: links for other apps (`mailto:`, `tel:`) ask before opening the app, instead of showing a raw error page.
- Search: text containing `&`, `+`, `=` or `?` is sent to the search engine intact.
- A single unreadable per-site setting no longer resets every site's settings, and a sync folder that can no longer be opened says so.

### Added

- iPhone: a per-site "Open in Apps" setting for links that would otherwise leave Boaz for the site's app.
- Settings › About shows whether Boaz's WebKit workarounds (pop-ups) are working.

## [0.4.36] - 2026-11-19

### Fixed

- iPhone: at the largest text sizes, the tab count above the cards no longer runs into Done.
- iPhone: swiping a card up to archive it gives a tap at the point where letting go archives, and the card leaves
  or drops back at the speed of the finger.
- iPhone: the page menu follows the finger's speed when dragged closed, with a tap where letting go closes it.
- Mac: with Reduce Motion on, opening and closing tabs, pinning, split view, the sidebar, spaces and the peek fade
  instead of sliding.
- Mac: the Library panel's Media, Downloads, Spaces and Archived Tabs labels are 11 pt and wrap instead of
  shrinking to about 7 pt.
- Mac: the sidebar's small symbols and the command bar follow Settings › Sidebar text size.
- Mac: the page card's corners follow the window's corners at every size.

### Added

- Mac: on a trackpad, a tap when the sidebar reaches its narrowest or widest, when split view passes the middle or
  its limits, when a dragged tab moves over a new spot, and when it drops.

### Changed

- Animations come from one set of motion tokens that follow Reduce Motion on their own; the peek and sidebar hover
  use them too.
- Plurals and percentages are written by Foundation, and every target has an English String Catalog for reviewing
  Boaz's copy against docs/copy.md.

## [0.4.35] - 2026-11-19

### Fixed

- iPhone: at large text sizes the page menu's Back, Forward, Reload and Share captions shrink to fit instead of
  clipping, the setup button no longer clips, and the Settings title grows with the text.

## [0.4.34] - 2026-11-19

### Changed

- Spacing and corner radii come from one set of layout tokens on both platforms. Nothing looks different yet.

## [0.4.33] - 2026-11-19

### Changed

- Mac: chrome text sizes come from one type ramp based on Settings › Sidebar text size. Nothing looks different yet.

## [0.4.32] - 2026-11-19

### Changed

- Haptics come from one named map on both platforms. Nothing feels different yet; later releases add the missing
  ones.

## [0.4.31] - 2026-11-19

### Fixed

- Mac: dragging a tab, pinned tab or favorite out of the sidebar into Notes, Mail, Finder or another browser gives
  its page's address instead of an internal id.

## [0.4.30] - 2026-11-19

### Fixed

- Mac: in the command bar, a pointer resting where the suggestions open no longer takes the selection from the top
  hit; moving the pointer over a row still selects it.

## [0.4.29] - 2026-11-19

### Fixed

- iPhone: at accessibility text sizes, "Switch to Tab" in search suggestions sits under the page's address instead
  of breaking mid-word beside it.

## [0.4.28] - 2026-11-19

### Fixed

- iPhone: the search field's Clear Text button is easier to hit (44 pt), without changing how the field looks.

## [0.4.27] - 2026-11-19

### Fixed

- iPhone: a tab whose page failed to load shows its icon and "Can't Open This Page" among the tabs, not a blank
  white card.

## [0.4.26] - 2026-11-18

### Fixed

- Mac: Boaz no longer quits when a website asks for the camera and microphone together.

## [0.4.25] - 2026-11-17

### Added

- Mac: the page's right-click menu has Summarize Page, Ask About This Page and, for selected text, Explain, all
  with Apple's on-device model.

### Fixed

- Mac: spaces of every profile share one window, as in Arc: switching to another profile's space no longer opens a
  second window.
- Mac: sidebar tabs and favorites take every click and drag; the hover preview no longer swallows the click that
  closes it.

## [0.4.24] - 2026-11-17

### Fixed

- Mac: switching to a space of another profile no longer opens its tabs in WebKit, where chrome://extensions
  was an unsupported address and that profile's extensions were missing. Each profile has its own Chromium
  window, as in Chrome; picking another profile's space shows that profile's window in the same place, and
  switching back brings the first window back with its pages as they were.
- Mac: Apple Intelligence names every tab that joins Pinned; it used to leave some long titles as they were.

## [0.4.23] - 2026-11-17

### Added

- Mac: Apple Intelligence names every tab as it joins Pinned, whether you pin it, drag it there or a Pull Requests
  live folder adds it: "chore(deps): resolve react-dev-utils' immer to 9.0.21 (CVE-2021-23436)" becomes a short
  title like "Immer CVE Fix". A tab you rename keeps your name, and a live folder retitles a pull request only when
  its title changes on GitHub.

### Fixed

- Mac: the Pull Requests live folder showed no icon in the DMG; it shows the GitHub mark again.

## [0.4.22] - 2026-11-16

### Changed

- Mac: Pull Requests live folders read github.com with your own GitHub sign-in in Boaz, as Arc does, instead of
  a GitHub app. Nothing to authorize and no token: every pull request you can see on github.com shows up,
  including ones in organizations that block third-party apps. The folder's menu offers Sign in to GitHub when
  the space's profile isn't signed in, and Single Sign-On › Authorize <organization>… when an organization's
  SAML session has expired.

## [0.4.20] - 2026-11-16

### Added

- Mac: Customize Space has Arc's theme color picker. Click or drag on a field of hues to pick up to three colors
  for the space's gradient, with pages of ready colors below it; choose Automatic, Light or Dark; give the
  backdrop a texture (grain, paper, dots or linen) and set its strength on the wave; and turn the dial to let the
  desktop show through the sidebar. The window shows each change as you make it, until you save or cancel.

## [0.4.19] - 2026-11-16

### Changed

- Mac: live folders are now off until you turn them on per profile in Settings › Accounts.

## [0.4.18] - 2026-11-16

### Changed

- Mac: the automated UI tests choose the Library's download filter by keyboard and open windows at the minimum size
  directly, fixing two of the three failing tests. No change to how Boaz works.

## [0.4.17] - 2026-11-16

### Added

- Mac: zooming with ⌘+, ⌘− or ⌘0 shows the new zoom level in a small tag at the window's top right for a moment.

## [0.4.16] - 2026-11-16

### Added

- Mac: ⌘T, ⌘L and Open in Split View suggest searches from your search engine as you type, below your open tabs.
  Arrow keys show the selected search in the field, or the tab's or page's address; back on the first row, your
  own text returns. Not in private windows, and not for addresses.

### Fixed

- Mac (DMG): the Chromium build now records the pages you visit, so they appear in the command bar's suggestions and the
  Library. Private windows still record nothing.

## [0.4.15] - 2026-11-16

### Fixed

- Mac (DMG): ⌘⇧R reloads the page bypassing the cache wherever focus is, not only after clicking into the page, and
  in little windows too. It is also in View › Reload Ignoring Cache (#129).

## [0.4.14] - 2026-11-16

### Fixed

- Mac (DMG): Boaz no longer refuses to start with "Boaz found libraries in both its previous sandbox and Application
  Support". It keeps using the library it used before, picking the one with your tabs and history the first time,
  and leaves the other untouched. Debug builds now keep a library of their own (#127).

## [0.4.13] - 2026-11-16

### Added

- Library panel: the button at the bottom of the sidebar opens Media, Downloads, Spaces and Archived Tabs. Downloads
  can be searched and filtered by kind, are grouped by date with thumbnails and where they came from, and open,
  drag out, show in Finder or move to the Trash. View › Downloads… (⌥⌘L) opens it.
- Mac: GitHub Pull Requests live folders. Sign in to GitHub in Settings › Accounts, then New Live Folder › GitHub
  Pull Requests adds a pinned folder of your pull requests that refreshes every minute, with each one's CI status.
  Choose Created by Me, Review Requests, Team Review Requests, Assigned or Mentioned, and which repositories.
  Folders can also be moved to another space, have their links copied, and get their own icon.
- A new pretzel app icon: by default a flat blue knot on white, or on black in dark mode, like the system's own
  icons, with 20 more styles to choose from, among them Glossy (3D), Neon, Wood, Gold, Holo Foil and Candy Cane. Pick
  one in Settings › App Icon on the Mac; the Dock keeps it even while Boaz is closed.

### Changed

- Mac (DMG): extensions work as in Chrome. The toolbar pins follow Chromium's Extensions page, popups open from
  keyboard shortcuts and the extension itself, the right-click menu is Chrome's, side panels open beside the page,
  and extensions can ask for site access from the toolbar. Install, update and permission prompts are back.
- Mac (DMG): private windows work like Chrome's incognito. A profile's private windows share one session, which
  ends (with its cookies) when the last one closes, and extensions allowed in incognito run in them.
- Mac (DMG): typing chrome://, chrome-extension:// or about: addresses opens them instead of searching.

### Fixed

- Mac (DMG): sign-in pages that VPN and single sign-on apps such as GlobalProtect open in Boaz can send you back to
  the app every time, not only the first time an app opens in a session.
- Mac (DMG): pop-up windows show their address again.
- Mac: ⌘W closes the tab, not the whole window, after a click in the sidebar.
- Deleting a folder archives the tabs in it; Clear Archive empties the Archive window straight away.

## [0.4.12] - 2026-11-16

### Fixed

- Mac (DMG): links that open other apps (Zoom, Teams, Slack…) ask "Open <App>?" in a sheet on the Boaz window, with
  Always allow for the site, instead of a separate floating dialog. A Zoom join link typed or pasted in the address
  bar opens Zoom again instead of being silently refused.

## [0.4.11] - 2026-11-15

### Changed

- Mac (DMG): install extensions with the Chrome Web Store's own Add to Chrome button; the Add to Boaz overlay is gone.
  Manage Extensions… opens Chromium's Extensions page (on/off, details, site access, shortcuts, Load unpacked),
  replacing Boaz's own extensions sheet and its Install Extension… and Load Developer Extension… items.

### Fixed

- Mac (DMG): removing an extension, from the Extensions page or the store's Remove from Chrome, asks in a sheet on
  the Boaz window instead of a dialog half off screen.

## [0.4.10] - 2026-11-15

### Added

- Mac (DMG): Share… in the right-click menu for pages, links and images opens the macOS share picker (AirDrop,
  Mail, Notes…); images are shared as files. Send to Your Devices, in the right-click menu and the tab's menu, sends
  the page to your iPhone, iPad or another Mac.

## [0.4.9] - 2026-11-15

### Fixed

- Mac (DMG): Boaz no longer refuses to launch with "found libraries in both its previous sandbox and Application
  Support" after a development build of Boaz ran on the same Mac. Development builds now keep their own library.

## [0.4.8] - 2026-11-15

### Added

- Mac (DMG): right-click selected text to search it with your search engine (Settings › General); the item names it,
  such as Search DuckDuckGo for “…”. Search Image with Google Lens and Search Page with Google Lens open Google Lens
  results in a new tab below.

### Fixed

- Mac (DMG): Search Google for “…” in the right-click menu no longer quits Boaz.

## [0.4.7] - 2026-11-15

### Added

- Mac (DMG): right-click a link to open it in an Incognito window or in split view next to the current tab, or
  right-click a page or image to show a QR code for it, which you can copy or save. The right-click menu shows your own
  shortcuts for Back, Forward, Reload, View Page Source and Picture in Picture.

### Fixed

- Mac (DMG): opening an Incognito window no longer quits Boaz.

## [1.0.2] - 2026-11-15

### Fixed

- iPhone: links to installed apps open those apps, including universal links.
- iPhone: page errors distinguish connection failures, missing websites, and unsupported links.

## [0.4.6] - 2026-11-15

### Added

- Mac: right-clicking a tab in the sidebar offers more of Chrome's tab items: New Tab Below, Add to New Folder, Move
  to Folder, Move Tab to New Window, Mute Tab, Close Other Tabs and Close Tabs Below. Items have icons and are grouped
  as in Chrome.

## [0.4.5] - 2026-11-15

### Added

- Mac (DMG): the right-click menu has more of Chrome's items: Save As…, Print…, View Page Source, Open Link in New
  Window, Save Link As…, Copy Link to Highlight, Copy and Save Video Frame, Speech and Writing Direction. Items have
  icons, and the edit items show their shortcuts.
- Mac (DMG): Edit › Paste and Match Style (⌥⇧⌘V).

## [0.4.4] - 2026-11-15

### Added

- Mac: Settings › Sites sends links to a site to a space. A link to that site from another app opens in the mini
  window with that space's profile, and Open in Boaz puts it in that space.

### Fixed

- Mac (DMG): the mini window opened from links in other apps has a compact, one-line header.
- Mac (DMG): Okta FastPass sign-in reaches Okta Verify. Other sites that ask to reach devices on your network now
  ask you first instead of being blocked.
- Mac (DMG): ⌘⇧R reloads the page without its cache, as in Chrome.
- Mac: in full screen, the sidebar's top bar moves left into the space the window buttons leave.

## [0.4.3] - 2026-11-15

### Fixed

- Mac (DMG): a link opened in a new tab (middle-click, ⌘-click or a link that opens one) goes right below the tab
  you're in, not at the top, and shows its page title and favicon without your switching to it.

## [0.4.2] - 2026-11-14

### Added

- Mac (DMG): right-click selected text and choose Explain, and Apple Intelligence explains it on this Mac, using the
  page for context. Without a selection, Ask About This Page… opens the page's questions.

## [0.4.1] - 2026-11-14

### Fixed

- Mac (DMG): Boaz › Check for Updates… is back, and Boaz checks for updates daily again. 0.3 and 0.4.0 never
  started the updater, so download this version once from GitHub; later updates install themselves.

## [0.4.0] - 2026-11-14

### Added

- Mac (DMG): Boaz runs on Chromium, with Chrome Web Store extensions and Chromium's DevTools. The Mac App
  Store and iPhone apps stay on WebKit. Upgrading from an earlier version keeps your library, settings, saved passwords and signed-in sites.
- iPhone: Boaz can be your default browser (Settings › Apps › Default Apps › Browser App), so links from other apps
  open in it. Settings › Default Browser shows whether it is and opens iOS Settings to choose it.
- Mac (DMG): extensions sit beside the address, as in Arc. Pin the ones you use; the puzzle button lists them all,
  opens their popups and manages them.

### Fixed

- Mac (DMG): right-click shows a menu again: a short one with the link, image, text and Inspect items that apply.
- Mac (DMG): websites can ask to use the camera, microphone and location. The Mac app didn't declare them before.
- Mac (DMG): logging out or restarting the Mac quits Boaz instead of being held up.
- iPhone: saving a photo from a website (Save to Photos, or Save Image from the share sheet) no longer closes
  Boaz. iOS now asks for permission to add to your photo library instead.
- iPhone: a link sent to Boaz again (tapped twice, or replayed after a cold launch) goes back to its tab instead of
  opening a duplicate.

### Changed

- Mac (DMG): Boaz presents itself as Chromium. Engine menus, badges and prompts are gone; video Chromium can't play
  still opens in WebKit, without asking.
- Mac (DMG): Settings is a standard Mac settings window with a tab for each pane.
- Mac: Boaz uses less energy. The shadow around a web page is no longer redrawn each time the page redraws, and in
  Low Power Mode Boaz checks iCloud for changes from your other devices every 10 minutes instead of every 2.

## [0.2.6] - 2026-11-12

### Fixed

- Mac: pressing the scroll wheel on a sidebar tab acts on that tab, not on the first pinned tab above it.

## [0.2.5] - 2026-11-12

### Added

- Mac and iPhone: Boaz suggests your saved passwords on a site's sign-in form and offers to save new ones after you
  sign in, kept in your iCloud Keychain and shown only after you unlock with Touch ID, Face ID or your passcode.
  Settings › Passwords lists and lets you delete them, and imports passwords exported as CSV from Chrome, Edge,
  Brave, Arc, Firefox, Safari or the Passwords app.
- Mac: pressing the scroll wheel on a pinned tab that's already unloaded removes it from Pinned to the Archive, after
  a warning you can turn off with "Don't ask again". On a Today tab it still archives the tab, and on a loaded pinned
  tab it unloads it.

### Fixed

- Mac: pressing the scroll wheel on a link, or on an image or button inside one, opens it in a new background tab
  in Today, as ⌘-click does, and leaves the page you're on where it was.
- iPhone: favorites and tabs in Tabs on Your Mac show the site's own icon, full and sharp as on the Mac, rather than
  a letter. A site with no icon at its root (ChatGPT, Gemini) names one in its page, and Boaz now reads it there.
- iPhone: going back to a tab returns to exactly where you left it. A ChatGPT chat read at its last message no longer
  comes back halfway up, or at the top: a page out of sight is laid out at another size, and the place it was read
  at on screen is what it now goes back to, under its preview until it is there.

## [0.2.4] - 2026-11-11

### Added

- Mac: a Develop menu for building and testing sites. Responsive Design Mode (⌥⌘R) shows the page at a phone,
  tablet or laptop size with Safari's matching user agent; the User Agent menu switches to Safari, Chrome, Firefox,
  Edge or any string; Emulate Media switches to print styles or a light or dark appearance; the Vision Simulator
  shows the page as people with color blindness, blurred vision or low contrast see it; and Disable JavaScript turns
  off the page's scripts. The JavaScript Console (⌥⌘C) runs code in the page and shows what it logs, View Page Source
  (⌥⌘U) and Show Storage… show its markup, cookies and local storage, Capture Visible Area and Capture Full Page
  save a screenshot to Downloads, Export as PDF… saves the page, and Empty Caches (⌥⌘E) reloads it fresh without
  signing you out. Each setting stays with its tab until the tab closes (`docs/devtools.md`).
- Mac and iPhone: Web Inspector works in every build. Right-click a page on the Mac and choose Inspect Element;
  Safari's Develop menu on a Mac can inspect pages on the iPhone.

### Changed

- iPhone: the phone's tabs are one stack, newest first, and no longer belong to a space. There is no space on the
  phone: no space name, color or switching, no pinned tabs or favorites of its own. The Mac's spaces, with their
  pinned tabs, favorites and open tabs, are in Tabs on Your Mac, and tapping any of them opens a copy on top of the
  stack, leaving the Mac's item as it is. Deleting, renaming or reordering a space on the Mac no longer touches the
  phone's tabs, and the Mac never shows them. Tabs opened on the phone before this move into the stack on first
  launch; tabs from before 0.2.3, which recorded no device, stay in their space and show in Tabs on Your Mac.
- iPhone: Tabs on Your Mac looks like the Mac's sidebar. Swipe between spaces or pick one from the space buttons at
  the bottom. Each space shows its favorites, its pinned tabs and folders (tap a folder to open it), and then the
  Today tabs open on your Mac. Tapping any of them opens the page in a new tab on the phone, in front of your other
  tabs, and leaves the Mac's tab where it is. It opens on the space you looked at last.
- iPhone: the page's "…" menu has Copy URL (it was Copy Link, and missing when the page had no address; now it's
  dimmed). It shows "Copied URL", in Incognito too.
- Mac and iPhone: tabs you haven't opened move to the Archive after 7 days, not after a day. An interval you picked in
  Settings stays as it was.

### Fixed

- Mac and iPhone: a tab comes back where you left it, for a week. A page Boaz unloaded to save memory, one the system
  stopped, and every page after a relaunch scroll back to where you were, inside the page's own scrolling areas
  too (a chat, a mail list), and a chat you left at its newest message comes back at its newest message. Before, the
  iPhone kept only the page's own scroll, and the Mac nothing, so a chat came back at its top. On iPhone the tab's
  preview shows until the page is back in place. Private tabs' places are never written to disk.

- iPhone: tab previews last past a quit. They were saved in Caches/Snapshots, a folder iOS keeps for its own app
  switcher images and that refuses the app's writes on a device, so a card showed the site's icon after a relaunch.
- iPhone: a pinned tab, or a tab open on another device, picked from search opens as one of the phone's tabs, on
  top of the stack. Before, the pinned tab itself opened: it showed, but was missing from the tab fan, and it changed
  the Mac's pinned tab. Search lists the phone's own tabs first ("Switch to Tab"), then the Mac's.
- Mac: a page that failed to load because the connection was down or dropped (after the Mac wakes, or on a Wi-Fi
  change) loads again on its own: once a second later, then whenever the network comes back, Boaz comes forward or
  the Mac wakes. A failure isn't shown while that first retry is pending.

## [0.2.3] - 2026-11-11

### Changed

- Mac: favorite tiles take on their icon's main color, and change with it when you add a favorite or a site changes
  its icon. Black, white and gray icons keep the neutral tile.
- Mac: the sidebar is roomier. Tab titles are a point larger (Settings › General › Sidebar text size is now 14, 15
  or 17 pt), rows are a little taller with a small gap between them, and the line above Today and the space buttons
  at the bottom have more room.

### Fixed

- Mac: tabs opened on the iPhone no longer show up in the sidebar's Today. Each device keeps its own Today; the
  iPhone still lists the Mac's tabs under Tabs on Your Mac and opens the one you pick in a new tab on the phone.
- iPhone: coming back to Boaz after a while no longer leaves a page on "Can't Open This Page". A page whose
  connection dropped while Boaz was in the background, or that iOS closed to free memory, loads again on its own:
  on returning to the app, once more a moment after a first failed try, and again when the network comes back.

## [0.2.1] - 2026-11-11

### Added

- Mac (DMG) and iPhone: Picture in Picture. A playing video floats when you leave it (another tab or space; on Mac
  a minimized or hidden window, another desktop or a full-screen app; on iPhone, leaving Boaz) and comes back when
  you return; bringing it back from its window shows its tab. It works for players embedded from other sites, never
  takes over another app's Picture in Picture, and floats a site's video on its own only where the site allows it.
  View › Picture in Picture (⌥⌘P) on the Mac and the page menu on iPhone float the video on request. Settings ›
  General turns the automatic part off on the Mac. The App Store build for Mac doesn't have it: WebKit offers it there
  only through a setting the App Store doesn't allow.
- iPhone: a video keeps playing after you leave Boaz.
- iPhone: ready to be the default browser once Apple grants the entitlement it needs (off until then;
  `web-browser.yml`). The app declares `http` and `https`, and links from other apps open in a new tab.

### Changed

- Mac: the window keeps the space's theme on every site. The sidebar no longer takes on the color of the page, and
  Settings › General › Tint chrome with site colors is gone; Customize Space sets the window's colors. iPhone still
  tints its edges to match the page.

- Mac: a link a page opens in a new window (`target="_blank"`, `window.open`) opens in a tab right below the page,
  rather than at the top of Today.
- Mac (DMG): an update's signature is checked before its DMG is opened.

### Fixed

- iPhone: the tab fan shows the tab you're on, on top, with the one before it behind; before, it left the current tab
  out, so a tab just opened seemed missing from it.
- iPhone and Mac: sign-in pop-ups ("Sign in with Google", Apple, Microsoft and the like) work. A `window.open` that
  asks for a pop-up window opens in a sheet that keeps `window.opener`, so the page that opened it gets the result,
  and it closes itself when done. Before, `window.open` returned nothing.
- iPhone: a link that opens a new window (`target="_blank"`, or `window.open` without pop-up features) loads in its
  tab; before, nothing happened.
- iPhone and Mac: a background tab that's playing audio or video, using the camera or microphone, or in full screen
  keeps running when more tabs open; before, the oldest page was closed past 8 (iPhone) or 10 (Mac) open pages,
  whatever it was doing.
- iPhone and Mac: site icons are drawn at their real size, with no gray box behind them. Square artwork gets an app
  icon's rounded corners, and a black or white logo that would vanish against the background sits on a contrasting
  tile. Icons are sharper: the largest image in a site's `.ico` is kept, a page's small favicon no longer replaces a
  sharper icon already saved, and icons saved small by earlier versions are fetched again once.
- Mac: favorites fill rows as evenly as they can (six are two rows of three), and the space's name lines up with
  the tab titles below it.

## [0.2.0] - 2026-11-11

### Added

- Mac: the DMG build updates itself with Sparkle. It checks GitHub Releases once a day, and from Boaz › Check for
  Updates…. People on 0.1.0 download 0.2.0 from the Releases page once; later versions arrive in the app. The App
  Store build doesn't contain Sparkle.
- Mac: Customize Space… brings the space editor and the color editor into one sheet, from the space's right-click
  menu, its dot, the View menu or a double-click on its name. It sets the name, icon and color (a palette or any
  color), the Light and Dark background colors, a one- or two-color gradient, the accent, the appearance (System,
  Light or Dark), grain and the light streak, with a live preview in Light and Dark. The theme syncs with the space.
- Mac: Settings › General › Sidebar text size: Small (13 pt), Medium (14 pt, the default) or Large (16 pt).
- Mac: View › Reload Ignoring Cache and Cookies (⇧⌘R) clears the current site's cookies and stored data in the tab's
  profile, and only that site's, then reloads the page from the server.
- Mac: a middle click (the wheel button) on a tab in the sidebar closes it, as in Safari and Chrome, even on a window
  in the background: a Today tab goes to the Archive and a pinned tab unloads.
- Passkeys in web pages on iPhone and Mac, through the system's passkey sheet, ready to turn on once Apple grants the
  entitlement they need (off until then; `passkeys.yml`).
- Mac: Chrome extensions, through WebKit's web extension support, per profile. The Extensions menu loads an unpacked
  folder or a `.crx`/`.zip`; the DMG build also installs from the Chrome Web Store, by address or ID or from the Add
  to Boaz button on an extension's store page. Boaz shows what an extension asks for before adding it. Toolbar
  buttons sit under the address field, and Manage Extensions… turns them on or off, opens their options or removes
  them. Some Chrome APIs aren't available; see `docs/extensions.md`.
- Mac: a middle click on a link, or a ⌘-click on a link or a form's button, opens it in a new tab right below the
  current one and stays on the page; ⌘⇧-click opens it in front.

### Changed

- Mac: ⌘-click on a link opens it in a background tab rather than a peek. A link that would leave a pinned tab
  still opens in a peek.

- Mac: a calmer sidebar. The system font at 14 pt (15 pt semibold space title), 32 pt rows on a 4 pt grid, one flat
  selection fill and half of it on hover, with no glow, shadow or border. Favorites are flat tiles that lift only on
  hover. Dimmer text and icons now read at 4.5:1 or better on every theme, in Light and Dark. One animation curve,
  and nothing moves with Reduce Motion. The rules are in `docs/design.md`.
- Mac: a space's grain texture and light streak are off unless its theme turns them on.
- Mac: any space can be deleted while another remains, including a profile's last one; that removes the profile too,
  with its favorites moving to the Archive and its site data deleted, and the confirmation says so. Delete Space… is
  in the space's right-click menu, on its header and its dot.

### Fixed

- Mac: switching spaces always shows a tab from the new space: the one last used there, else its most recent tab,
  else an empty New Tab page. A favorite the two spaces share stays open (#37).
- Mac: ⌘S (or its rebound shortcut) folds and unfolds the sidebar wherever the keyboard focus is, a web page included,
  and on a Hebrew or other non-Latin keyboard layout too. Held down, it folds once.
- Mac: deleting a profile closes its pages on every Mac before removing its site data; a removal that fails is retried
  at the next launch.
- Mac: ⇧⌘T no longer loses a closed tab whose space was deleted; it stays in the Archive.
- Mac: changing a space's color keeps an imported Arc theme's texture, vibrancy and fixed appearance.
- Mac: deleting the space whose Customize Space sheet is open, here or on another Mac, closes the sheet.
- Mac: text in Settings reads at 4.5:1 or better in Light and Dark. Values use the label color, and footnotes a
  secondary color stronger than the system's (about 4:1 in Light).

## [0.1.0] - 2026-11-10

First public beta. The Mac app is a notarized DMG on GitHub Releases; the iPhone app is built from source.

### Added

- The Mac app can be downloaded as a notarized DMG from GitHub Releases.

- Spaces with their own color themes, pinned tabs, folders and favorites.
- Today tabs that move to the Archive after a period without use.
- iCloud sync of the library through the private CloudKit database, with a folder-based fallback.
- iPhone Duo layouts for the folded, open, book and laptop postures.
- Mac app with sidebar, command bar, split view, rebindable shortcuts, downloads and a Quick Window for links
  from other apps.
- Import from Arc (spaces, pinned folders, favorites, themes, shortcuts and optional cookies) and from Chrome, Brave,
  Edge and Safari bookmarks.
- Ad and tracker blocking, cookie-banner declining on iPhone, Incognito tabs and a reader view.
- Share extension, search widget, App Shortcuts, the `boaz://` URL scheme and alternate app icons.
- Privacy manifest, privacy policy and an About section with third-party notices.

[Unreleased]: https://github.com/chenkahana/Boaz/compare/v0.4.20...HEAD
[0.4.20]: https://github.com/chenkahana/Boaz/compare/v0.4.19...v0.4.20
[0.4.19]: https://github.com/chenkahana/Boaz/compare/v0.4.18...v0.4.19
[0.4.18]: https://github.com/chenkahana/Boaz/compare/v0.4.17...v0.4.18
[0.4.17]: https://github.com/chenkahana/Boaz/compare/v0.4.16...v0.4.17
[0.4.16]: https://github.com/chenkahana/Boaz/compare/v0.4.15...v0.4.16
[0.4.15]: https://github.com/chenkahana/Boaz/compare/v0.4.14...v0.4.15
[0.4.14]: https://github.com/chenkahana/Boaz/compare/v0.4.13...v0.4.14
[0.4.13]: https://github.com/chenkahana/Boaz/compare/v0.4.12...v0.4.13
[0.4.12]: https://github.com/chenkahana/Boaz/compare/v0.4.11...v0.4.12
[0.4.11]: https://github.com/chenkahana/Boaz/compare/v0.4.10...v0.4.11
[0.4.10]: https://github.com/chenkahana/Boaz/compare/v0.4.9...v0.4.10
[0.4.9]: https://github.com/chenkahana/Boaz/compare/v0.4.8...v0.4.9
[0.4.8]: https://github.com/chenkahana/Boaz/compare/v0.4.7...v0.4.8
[0.4.7]: https://github.com/chenkahana/Boaz/compare/v0.4.6...v0.4.7
[0.4.6]: https://github.com/chenkahana/Boaz/compare/v0.4.5...v0.4.6
[0.4.5]: https://github.com/chenkahana/Boaz/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/chenkahana/Boaz/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/chenkahana/Boaz/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/chenkahana/Boaz/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/chenkahana/Boaz/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/chenkahana/Boaz/compare/v0.2.6...v0.4.0
[0.2.6]: https://github.com/chenkahana/Boaz/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/chenkahana/Boaz/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/chenkahana/Boaz/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/chenkahana/Boaz/compare/v0.2.1...v0.2.3
[0.2.1]: https://github.com/chenkahana/Boaz/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/chenkahana/Boaz/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/chenkahana/Boaz/releases/tag/v0.1.0
