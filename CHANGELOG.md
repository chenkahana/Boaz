# Changelog

All notable changes to Boaz are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Mac: the DMG build updates itself with Sparkle. It checks GitHub Releases once a day, and from Boaz › Check for
  Updates…. People on 0.1.0 download 0.2.0 from the Releases page once; later versions arrive in the app. The App
  Store build doesn't contain Sparkle.
- Mac: Customize Space… brings the space editor and the color editor into one sheet, from the space's right-click
  menu, its dot, the View menu or a double-click on its name. It sets the name, icon and color (a palette or any
  color), the Light and Dark background colors, a one- or two-color gradient, the accent, the appearance (System,
  Light or Dark), grain and the light streak, with a live preview in Light and Dark. The theme syncs with the space.
- Mac: Settings › General › Sidebar text size: Small (13 pt), Medium (14 pt, the default) or Large (16 pt).

### Changed

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
- Mac: ⌘S (or its rebound shortcut) folds and unfolds the sidebar wherever the keyboard focus is, a web page included.
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

[Unreleased]: https://github.com/chenkahana/Boaz/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/chenkahana/Boaz/releases/tag/v0.1.0
