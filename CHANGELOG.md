# Changelog

All notable changes to Boaz are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Mac: a link a page opens in a new window (`target="_blank"`, `window.open`) opens in a tab right below the page,
  rather than at the top of Today.
- Mac (DMG): an update's signature is checked before its DMG is opened.

### Fixed

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

[Unreleased]: https://github.com/chenkahana/Boaz/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/chenkahana/Boaz/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/chenkahana/Boaz/releases/tag/v0.1.0
