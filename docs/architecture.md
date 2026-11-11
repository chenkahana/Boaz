# Architecture

Boaz is two native SwiftUI apps (iPhone and Mac) and two iOS extensions over one Swift package, **BoazKit**. This
document explains how the pieces fit together and the rules each layer follows.

## Targets

| Target | Platform | Sources | Bundle ID |
|---|---|---|---|
| Boaz-iOS | iOS 27.1+ (iPhone; iPad in compatibility mode) | `Apps/iOS`, `Apps/Shared`, `Apps/Browser` | `com.chenkahana.boaz` |
| Boaz-macOS | macOS 26+ | `Apps/macOS`, `Apps/Shared`, `Apps/Browser` | `com.chenkahana.boaz` |
| ShareExtension | iOS | `Apps/Extensions/ShareExtension`, `Apps/Shared` | `com.chenkahana.boaz.share` |
| Widgets | iOS | `Apps/Extensions/Widgets`, `Apps/Shared` | `com.chenkahana.boaz.widgets` |
| BoazKit | iOS 17+, macOS 14+ (Swift package) | `Packages/BoazKit` | — |

The iPhone and Mac apps share one bundle ID, so they are one App Store record (universal purchase) and one iCloud
App ID. The iOS app and its extensions share the app group `group.com.chenkahana.boaz`, where the library database
lives. Targets, entitlements and Info.plist keys are defined in [`project.yml`](../project.yml); the Xcode project is
generated from it.

## Concurrency

App targets use Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: views and models are main-actor by default.
BoazKit has no default isolation. Everything that touches SQLite, CloudKit or the file system runs off the main
actor through BoazKit's `async` API, so the UI never blocks on I/O. When several reloads race, a generation counter
makes sure only the newest result is applied.

## Data model

All records are GRDB value types in `Model/Records.swift`:

- **Profile**: a browsing profile, with its own `WKWebsiteDataStore` (cookies and site data).
- **Space**: belongs to a profile; has a name, icon, color theme (`WindowTheme`) and order.
- **SidebarItem**: a tree per space. Containers (`pinned`, `unpinned` = Today, `favorites`) hold folders and tabs.
  Order is explicit, so every device shows the same sequence. An iPhone's tabs are its **mobile stack**: tabs with
  its `deviceID`, in no space and under no container (`isMobileTab`), listed newest first. They sync like any item,
  but the Mac, which lists tabs by their containers, never shows them, and space edits on the Mac never touch them.
- **ArchiveItem**: a closed or auto-archived tab.
- **HistoryVisit**: local only. History is never synced.

`BoazStore` is the single source of truth on each device. It opens a `DatabasePool` (WAL mode) in the app group,
runs versioned migrations (`v1`, `v2-history`, `v3-sync`, …) and exposes reads such as `loadSidebar()` and writes
such as `archiveStaleTabs()`. A shipped migration is never edited; schema changes add a new one.

`StarterLibrary` seeds a new library with fixed IDs, so two devices that start fresh merge into one library instead
of duplicating it.

## Sync

```mermaid
sequenceDiagram
    participant UI as App
    participant Store as BoazStore (SQLite)
    participant Queue as Pending changes
    participant Engine as CKSyncEngine
    participant CK as Private iCloud DB
    UI->>Store: write (pin, move, close…)
    Store->>Queue: trigger records the change
    Engine->>Queue: drain
    Engine->>CK: upload in batches
    CK-->>Engine: server changes
    Engine->>Store: applyServerChanges (3-way merge)
    Store-->>UI: sidebarUpdates()
```

- **Transport.** `LibrarySync` is the only sync object the apps use. When the build has the iCloud entitlement and
  an account is signed in, `CloudKitSync` mirrors the store to the private database (zone `Boaz`) with
  `CKSyncEngine`. Otherwise a folder the user picks (`FolderSync`) is the fallback. Only one transport runs at a time;
  both drain the same queue.
- **Change capture.** Database triggers write every local change to `SyncPendingChange`, so no write path can forget
  to sync.
- **Conflicts.** `SyncMerge` does a per-field three-way merge against the last server copy (`SyncRecordMeta`). A field
  changed on one side keeps that change; a field changed on both sides goes to the newer edit. The folder transport
  uses per-field timestamps (`RecordState`) so devices converge without a server.
- **Deletes** are kept as tombstones for 30 days so slower devices learn about them, then purged; the purge is
  queued like any change, so the CloudKit record goes too. Arc-imported rows keep their tombstones, so re-importing
  from Arc doesn't bring back what was removed in Boaz.
- **What syncs:** profiles, spaces, sidebar items, the archive and the device list (`SyncRecordType`). Each Today
  tab records the device it was opened on; each device lists and archives only its own, the iPhone its mobile stack.
  History, Incognito tabs, page snapshots and cookies never leave the device.

## Browsing

Both apps render pages with WebKit. Shared glue in `Apps/Browser` handles:

- **Content blocking:** EasyList compiled into `WKContentRuleList`s, on by default for every page.
- **Downloads**, **favicons** (fetched from each site directly) and **site colors** for the iPhone's tinted
  edges.

Platform specifics live in each app: on iPhone, cookie-banner declining, the reader view, pull to refresh and the
navigation policy; on Mac, the sidebar window, split view, command bar, rebindable shortcuts and Chrome extensions
([extensions.md](extensions.md)).

**Picture in Picture** (`Apps/Browser/PictureInPicture.swift`). A script in every frame, in its own
`WKContentWorld`, reports each frame's best video (playing, at least 120×68 pt, not a muted backdrop loop; the last
played first, then sound, then size). Floating calls into that frame through the page's `WKWebView`
(`backingWebView`, read through reflection), which WebKit counts as a user action, so embedded players in other
sites' frames float too. Each app floats a playing video when its tab leaves view or the app or window does, and
brings back what it floated when the user returns. On the Mac, WebKit floats video only with the preference
`_allowsPictureInPictureMediaPlayback`, which has no public setter: only the DMG build (`DIRECT_DISTRIBUTION`) sets it,
so the App Store build has no Picture in Picture and no menu item or setting for it. If a WebKit update renames that
preference or the `WKWebView` property, Picture in Picture stops and nothing else does. The iPhone app declares the
`audio` background mode, which iOS needs for a video to keep playing, or float, once the app is left.

**Passkeys.** WebKit handles WebAuthn (`navigator.credentials.create` and `get`) itself and shows the system's
passkey sheet, so neither app has passkey code of its own. For any site beyond the app's associated domains, the
system requires the managed entitlement `com.apple.developer.web-browser.public-key-credential`, which Apple grants
per App ID (requested for `com.chenkahana.boaz`, team DPF8459C2J, as request Z6525VUX9T). Both apps get it from [`passkeys.yml`](../passkeys.yml), which
`project.yml` includes with `enable: false` until the grant: signing with an entitlement the App ID lacks fails. To
turn passkeys on, set `enable: true` and run `make project`, which writes it into the iPhone and Mac entitlements
(the DMG build includes `project.yml`, so it follows). `ASAuthorizationWebBrowserPublicKeyCredentialManager` isn't
needed: it lists saved passkeys for browsers that draw their own sign-in suggestions.

**Default browser on iPhone.** iOS only offers "Default Browser App" to apps holding the managed entitlement
`com.apple.developer.web-browser`, which Apple grants per App ID through its default browser entitlement request
form. The iPhone app gets it from [`web-browser.yml`](../web-browser.yml), which `project.yml` includes with
`enable: false` until the grant, the same way as passkeys. The iPhone app already declares the `http` and `https`
schemes Apple requires, and `DeepLink` opens those links in a new tab. The Mac needs no entitlement to be the default
browser.

**Pop-ups.** A sign-in pop-up ("Sign in with Google", Apple or Microsoft) posts its result to `window.opener`, which
only survives if the pop-up lives in the `WKWebView` WebKit creates for it. `WebPage` has no new-window hook (checked
through the macOS 27.2 and iOS 27.2 SDKs), so `Apps/Browser/PagePopups.swift` reaches the `WKWebView` behind a tab's
`WebPage` with `Mirror` (`backingWebView(of:)`, a stored property, no private selector) and puts a UI delegate in
front of WebPage's own one, forwarding every method it doesn't implement. WebPage creates its WKWebView lazily and
WebKit asks for a `window.open` view without a navigation decision first, so the delegate goes in on the page's
first navigation decision, before any of its scripts run. A `window.open` that asks for a size, a position or no
toolbars (Safari's rule for a window) opens in a sheet, with the opener's configuration as WebKit passes it, so the
data store (incognito stays in memory), content blockers and extensions carry over. It closes on `window.close()`,
its close button, or when the opener's view goes. Any other new window (a `target=_blank` link, `window.open`
without features) opens in a tab below the opener on Mac (a peek for pinned tabs) and in place on iPhone, where a
site whose pop-ups are blocked gets nothing for the windows its scripts open. WebPage's own delegate doesn't create
windows, so before this a `window.open` got `null` on both apps and a `target=_blank` link did nothing on iPhone.
Windows a pop-up opens load in the pop-up.

When the SDK changes, check, on both apps:

- `WebPage` or `WebView` gained a new-window API: switch to it and delete `PagePopups`' delegate.
- `backingWebView(of:)` still finds the view, and the tab's `uiDelegate` is still a `WebKit.`-prefixed class. If
  either fails, new windows keep their old placement and the app logs `No pop-up host` once (subsystem
  `com.chenkahana.boaz`, category `popups`); Mac extensions lose per-tab scripting the same way.
- JavaScript alert, confirm and prompt, file inputs, camera and microphone prompts and fullscreen still work on a
  page that has opened a pop-up: those go through the forwarded delegate.

## iPhone Duo postures

`RootView` picks a layout from the size class and the hinge **state**; the raw hinge angle only drives effects such
as the fold glow.

| Posture | Layout |
|---|---|
| Folded (cover screen) | `CompactShell`: the page, with the tab stack opening into the tab carousel |
| Open, wide | Sidebar beside the page; the sidebar can be hidden |
| Open, narrow | Page full width; the sidebar floats over it as a card |
| Book (fold vertical) | Sidebar fills the left half up to the fold, page on the right |
| Laptop (fold horizontal) | Page on the upper half, Today tabs and the address bar on the lower half |

Every open posture uses the same view tree (`UnfoldedShell`), so the web view is never rebuilt as the device folds.
The fold position comes from the system's reserved regions rather than from hard-coded sizes. Standard iPhones use
the folded layout.

## Importers (Mac)

- **Arc sidebar:** reads `StorableSidebar.json` and recreates profiles, spaces, pinned folders, favorites and themes
  in the same order.
- **Arc shortcuts:** maps `StorableKeyBindings.json` overrides onto Boaz's commands.
- **Arc cookies (opt-in):** decrypts Arc's cookie database with the "Arc Safe Storage" Keychain key (macOS asks the
  user first) and writes the cookies only into the matching profile's local `WKWebsiteDataStore`. They are never
  stored in the Boaz database or synced.
- **Bookmarks:** Chrome, Brave, Edge and Safari bookmark files become pinned tabs and folders.

Boaz does not import saved passwords. `ArcPasswordImporter.swift` is excluded from the package build.

## Privacy and security

- Boaz uses no analytics, crash reporting or third-party SDKs that collect data. `PrivacyInfo.xcprivacy` declares no
  tracking and no collected data, plus the required-reason APIs used.
- The Mac app is sandboxed. It reads other browsers' data only from folders the user selects, through
  security-scoped bookmarks.
- See [privacy.md](privacy.md) for the user-facing policy and [SECURITY.md](../SECURITY.md) for vulnerability
  reporting.
