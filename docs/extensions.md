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
    get the ZIP. WebKit DMG build only; see below. The Chromium DMG has neither: the store page's own Add to Chrome
    button installs through Chromium's `chrome.webstorePrivate`, with Boaz's install prompt, and **Manage Extensions…**
    opens Chromium's own `chrome://extensions` (Load unpacked, details, site access, shortcuts, removal).
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

## Chromium DMG

The Chromium DMG runs Chromium's own extension system; none of the WebKit code above is compiled into it
(`#if !BOAZ_CHROMIUM`). Boaz draws the toolbar, popups and prompts natively, but Chromium decides what they do, so an
extension behaves as it does in Chrome. The host side is in [`Tools/chromium/host`](../Tools/chromium/host):

- **Toolbar.** `extension_actions.mm` registers Chromium's `ExtensionsToolbarViewModel` as the window's
  `ExtensionsContainer`, as Chrome's Android toolbar does. Pins and their order are Chromium's (`ToolbarActionsModel`,
  the profile's `extensions.pinned_extensions` pref); Boaz's older `chromiumPinnedExtensions` setting is moved into it
  once. Icons are Chromium's toolbar icons with the badge (text and background color) drawn in, at 2x. Right-click
  shows Chromium's action menu (pin, site access, options, remove, inspect popup). The request-access button
  ("Allow", with the extensions' icons) appears when an extension with withheld site access asks for the current
  site (`permissions.addHostAccessRequest`), and Chromium's reload prompt follows a grant.
- **Popups.** `action.openPopup()`, `_execute_action` and clicks open the popup at the action's button, or at the
  extensions button when it isn't pinned. It closes as Chrome's does: on a click back in the window, a tab switch, or
  the window closing; not when it opens a dialog or DevTools.
- **Commands.** Manifest `commands` (`_execute_action` and custom ones) run from the window and its popups; edits in
  `chrome://extensions/shortcuts` apply at once. Global (system-wide) shortcuts go through Chromium's own Mac
  listener; they haven't been checked in Boaz.
- **Side panel.** `sidePanel.open()`, `openPanelOnActionClick` and the action menu's **Open side panel** show the
  extension's panel at the window's trailing edge; drag its edge to resize it, close it with its × button
  (`sidePanel.onClosed` fires). Tab-specific panels follow the active tab.
- **Windows.** `windows.create({type: "popup"})` and `window.open` with window features open a window with one page
  and a read-only address field, as Chrome does. Extensions can move, highlight and group tabs (`tabs.move`,
  `tabs.group`).
- **Install feedback.** Chromium's post-install bubble, install errors, and the "disabled because it needs new
  permissions" prompt use Chromium's text and buttons, drawn as a popover or sheet.
- **Private windows.** As Chrome's incognito, a profile's private windows share one off-the-record session (its
  cookies and logins last until the profile's last private window closes) and get that profile's extensions that
  have **Allow in Incognito** on in `chrome://extensions`. Pins can't change there, as in Chrome.

`Tools/chromium/fixtures/parity-extension` is an unpacked MV3 extension that exercises each of these; load it with
`--load-extension=<path>` in an isolated profile.

### Chrome Web Store and Arc

The store page says **Add to Chrome** and shows a "Switch to Chrome?" card in Boaz. Arc's store page doesn't show
the banner. Inspecting Arc's app found no generic store mechanism to copy; the difference comes from how Arc
identifies itself to Google's sites (it presents as Chrome). Boaz doesn't spoof Chrome's identity. Installing works either way: the store's own button installs through Chromium's
`chrome.webstorePrivate` with Boaz's native prompt.

## App Store

Downloading extension code from the Chrome Web Store risks rejection under App Review Guideline 2.5.2 (apps may not
download code that adds or changes features). So **Install from Chrome Web Store…** and the Add to Boaz button exist
only in the WebKit DMG build: `project-dmg.yml` sets the `DIRECT_DISTRIBUTION` compilation condition, and the App
Store and Chromium (`BOAZ_CHROMIUM`) builds don't compile that code. Load Unpacked… and Install from File… remain in
both builds: the user picks the files, as with any document, but App Review may still question them. If it does, wrap their menu items in
`#if DIRECT_DISTRIBUTION` as well.
