# Changelog

All notable changes to Boaz are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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

[Unreleased]: https://github.com/chenkahana/Boaz/compare/v0.2.4...HEAD
[0.2.4]: https://github.com/chenkahana/Boaz/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/chenkahana/Boaz/compare/v0.2.1...v0.2.3
[0.2.1]: https://github.com/chenkahana/Boaz/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/chenkahana/Boaz/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/chenkahana/Boaz/releases/tag/v0.1.0
