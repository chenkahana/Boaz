# Extensions (Mac)

The Mac app runs Chrome-style web extensions (Manifest V2 and V3) through WebKit's `WKWebExtension`, the engine
behind Safari's web extensions. The code is in [`Apps/macOS/Extensions`](../Apps/macOS/Extensions).

## How it works

- **One controller per profile.** `Extensions.controller(profileID:)` makes a `WKWebExtensionController` per profile,
  keyed by the profile's data store, and `BrowserState.makePage` attaches it to every page of that profile. An
  extension installed in one profile doesn't see the others. Incognito pages get no controller and run no extensions.
- **Installing.** From the Extensions menu:
  - **Install from Chrome Web Store…** takes a store address (`chromewebstore.google.com/detail/<name>/<id>`) or an
    ID. On a store detail page an **Add to Boaz** button appears over the page. Boaz downloads the CRX from Google's
    update service (`clients2.google.com/service/update2/crx`), as Chrome does, and strips the CRX2/CRX3 header to
    get the ZIP. DMG build only; see below.
  - **Load Unpacked…** takes a folder with a `manifest.json`.
  - **Install from File…** takes a `.crx` or `.zip`.

  Every route shows what the extension asks for (permissions and sites) before it's added; adding it grants exactly
  that. Later requests (`permissions.request`, new sites) ask again.
- **Storage.** `~/Library/Containers/com.chenkahana.boaz/Data/Library/Application Support/Extensions/`:
  `installed.json` lists each extension with its profile, granted permissions and sites, and whether it's on; the
  extension itself is `<profile>/<id>/extension.zip` (WebKit reads the ZIP directly) or `<profile>/<id>/Extension`
  (a copy of an unpacked folder). Each extension keeps a fixed `webkit-extension://<uuid>/` origin, so its storage
  survives relaunches. Nothing here syncs.
- **What's wired.** Toolbar buttons under the address field (icon, badge, popup or `action.onClicked`); `tabs` and
  `windows` (a Boaz window is a window; its tabs are the current space's tabs); opening tabs and the options page;
  permission prompts. **Manage Extensions…** lists the profile's extensions, with an on/off switch, Options, and
  Remove.

## Limits

WebKit doesn't implement these Chrome APIs (macOS 26), so extensions that depend on them fail or lose those features:

- `bookmarks`, `history`, `topSites`, `sessions`, `readingList`
- `downloads`
- `identity`, `gcm`, `instanceID`
- `notifications`, `tts`, `ttsEngine`
- `debugger`, `devtools.*`
- `proxy`, `privacy`, `contentSettings`, `fontSettings`
- `offscreen`, `sidePanel`, `tabGroups`
- `pageCapture`, `tabCapture`, `desktopCapture`
- `idle`, `power`, `system.*`, `enterprise.*`, `management`
- Blocking `webRequest` (Manifest V2 ad blockers); `declarativeNetRequest` works instead.

Boaz doesn't yet wire these, though WebKit has them: extension keyboard shortcuts (`commands`), extension items in
the page's right-click menu (`contextMenus`/`menus`), `sidebarAction`, and `runtime.sendNativeMessage`. A new window
from an extension opens its tabs in the current window.

WebPage (SwiftUI) doesn't expose its `WKWebView`, which WebKit needs to match a tab to its scripts
(`scripting.executeScript`, `tabs.sendMessage`). `backingWebView(of:)` finds it by reflection. If a WebKit update
renames the property, tabs still list and switch, but scripts can't target them; check this after major macOS updates.

## App Store

Downloading extension code from the Chrome Web Store risks rejection under App Review Guideline 2.5.2 (apps may not
download code that adds or changes features). So **Install from Chrome Web Store…** and the Add to Boaz button exist
only in the DMG build: `project-dmg.yml` sets the `DIRECT_DISTRIBUTION` compilation condition and the App Store
build doesn't compile that code. Load Unpacked… and Install from File… remain in both builds: the user picks the
files, as with any document, but App Review may still question them. If it does, wrap their menu items in
`#if DIRECT_DISTRIBUTION` as well.
