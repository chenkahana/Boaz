# Shared Chromium window/tab host: design proposal

Status: **selected implementation direction; no implementation or runtime proof**. Read-only inspection of local CEF `57389f04a61ab0e9603d9f96602843d0e08bb11c` and Chromium `8954d18543712dc11b97c3aca0a6e714aa2d7dcd` under `/Volumes/BoazBuild/cef/chromium_git`. No build, tests, or app launch performed.

## Recommendation

Keep one real Chromium `Browser`/`BrowserWindowInterface`, one `TabStripModel`, and one Chrome `BrowserView` per visible Boaz window. Adapt that model through a small CEF window/tab controller, rather than treating each `CefBrowserView` as a Boaz tab. Keep native SwiftUI controls in a supported native-view host inside the original Views hierarchy. The native-host wrapper API is a separate orchestrator-owned design.

Do not remove the one-Chrome-BrowserView guard and assume the problem is solved. That would allow multiple browser-window owners inside one widget while leaving extension window identity, command routing, focus, lifecycle, and split behavior undefined. Independent hidden Chromium windows per Boaz tab are also unsuitable: extension `windowId`, active-tab selection, and window operations would describe different windows from those the user sees.

## Existing hooks and constraints

All paths below are relative to the inspected source roots.

| Source | Evidence and consequence |
|---|---|
| CEF `libcef/browser/views/browser_view_impl.cc`, `AddedToWidget` | Rejects another Chrome BrowserView when the widget already has a theme profile. This is a window-ownership constraint, not a tab-count limit in Chromium. |
| CEF `libcef/browser/chrome/chrome_browser_host_impl.cc`, `Create` | Creates a Browser, calls `chrome::AddTabAt`, then obtains its active WebContents. Existing Chromium tab creation already causes creation of a corresponding CEF browser host. |
| Same file, `CreateBrowser` | A CEF BrowserView converts a normal Browser to `TYPE_POPUP`, marks it trusted, and supplies its ChromeBrowserView/window widget. A native-tab host must explicitly preserve normal window semantics while independently hiding unwanted chrome. |
| CEF `chrome_browser_delegate.cc`, `OnWebContentsCreated` / `SetAsDelegate` | Attaches BrowserWebContentsDelegate and creates a `ChromeBrowserHostImpl` for a new tab, or updates its Browser association on transfer. New tabs inherit window creation settings/client/context; a per-tab client contract needs an explicit hook if required. |
| CEF `chrome_browser_host_impl.cc`, `Attach` / `SetBrowser` | Existing attachment associates WebContents, platform delegate, browser callbacks, and Browser ownership. Reuse this path; do not manufacture a second WebContents wrapper with independent ownership. |
| CEF `chrome_browser_host_impl.cc`, `OnSetFocus` | Selects the containing tab through `chrome::SelectNumberedTab`. Selecting and focusing are related but should be separate operations in the new API. |
| CEF `chrome_browser_host_impl.cc`, `CloseBrowser` / `DoCloseBrowser` | TabStripModel mutation is non-reentrant; forced close is posted asynchronously. Preserve before-unload/close sequencing and existing `OnBeforeClose`. |
| CEF `libcef/browser/chrome/views/browser_platform_delegate_chrome_views.cc` | Stores a weak reference to one CefBrowserView and forwards each browser/WebContents lifecycle into it. This single-page coupling must be split from window ownership; new tabs cannot all overwrite one BrowserView's page state. |
| Chromium `chrome/browser/ui/tabs/tab_strip_model.h` | `AppendWebContents`, `InsertWebContentsAt`, `AddWebContents`, `ActivateTabAt`, `CloseWebContentsAt`, and detach/insert methods already implement real tab ownership. Inactive tabs remain owned in this model; ordinary selection does not destroy them. |
| Chromium `tab_strip_model_observer.h` | `OnTabStripModelChanged`, `OnTabChangedAt`, and `OnTabStripModelDestroyed` provide model changes, selection, and terminal notification. Observe extension/user-created changes as well as Boaz requests. |
| Chromium `chrome/browser/extensions/extension_tab_util.cc` | `GetTabId`, `GetWindowId`, and `GetWindowIdOfTab` derive extension IDs from real WebContents/window controllers. Expose these actual IDs for correlation; do not substitute CefBrowser identifiers. |
| Chromium `chrome/browser/ui/tabs/tab_strip_model.h` | `AddToNewSplit`, `UpdateSplitLayout`, `UpdateSplitRatio`, `UpdateTabInSplit`, and split detach/restore methods manage a real split collection. |
| Chromium `chrome/browser/ui/views/frame/browser_view.h` | `OnSplitTabChanged`, `ShowSplitView`, `HideSplitView`, and `MaybeUpdateSplitView` display multiple contents inside the same BrowserView. Prefer this existing split implementation if it supports Boaz behavior. Feature/configuration availability and CEF overrides still require runtime proof. |

The root experiment established a separate hard constraint: page accessibility appears with the original CEF content root and disappears when the spike replaces that root with an AppKit sibling wrapper. The production route must retain that root. `views::NativeViewHostMac` is the proposed integration point for SwiftUI, subject to the orchestrator's API/lifetime review and actual keyboard/accessibility/fullscreen acceptance.

## Proposed public boundary

Names are illustrative and not yet frozen. Expose a reference-counted `CefChromeTabHost` associated with a window-level Chrome Views host. Keep Chromium types private to libcef. Public values contain CEF browser references, stable opaque tab/window IDs, actual extension IDs, ordered tab snapshots, selection, and split state. Never expose raw `Browser*`, `WebContents*`, or TabStripModel indices as durable handles.

- Create a host with one request context/profile and a window client. Create tabs through that host, supplying initial URL and client/extra-info policy. Each real WebContents has one CefBrowser lifecycle. Profile/context cannot change by tab insertion.
- Activate a stable tab handle; separately request focus. Preserve inactive WebContents and return current active identity. For split, distinguish focused pane from the set of displayed tabs.
- Close a tab through existing CEF close semantics. Report removal separately from final `OnBeforeClose`; never report successful destruction merely because close was requested. Close the window only after all remaining tabs resolve before-unload and close.
- Observe ordered insert/remove/move/selection/split changes caused by native UI, extension APIs, popups, or automation. Deliver snapshots or sequenced events on CEF UI thread. Avoid callbacks mutating TabStripModel reentrantly; queue client mutations until observer dispatch unwinds.
- Split two existing same-profile tabs using Chromium's split model, preserving both tab IDs and one window ID. Define ratio/orientation and exit-split behavior. Reject unsupported states explicitly; do not detach WebContents into arbitrary NSViews.
- Transfer between eligible windows only through existing detach/insert ownership paths, preserving tab identity and emitting actual window changes. Cross-profile transfer is rejected. This can remain unsupported in the first bounded host proof but is required before full parity.
- Invalidate the controller when its Browser/window is destroyed; reject operations afterward. A CefBrowser reference does not keep a destroyed BrowserWindow alive. Cancel host operations once, retaining only safe CEF references until their documented lifecycle endpoint.

Sleeping/discarded pages remain a later policy layer. Keep Chromium tab metadata/identity stable while implementing the agreed ten-live-page policy; do not equate CEF-reference retention with retaining a live renderer. Exact discard/restore behavior is outside this packet.

## Fork touchpoints and scope

The maintainable route extends CEF's Chrome window integration instead of duplicating Chromium's tab model. Likely edits:

1. New public controller/delegate headers plus generated C API/wrapper files and build declarations.
2. CEF ChromeBrowserView/window construction: normal Browser semantics with configurable native controls and hidden Chrome tab strip/toolbars. Preserve original widget/content root.
3. ChromeBrowserDelegate tab creation and host association: map each WebContents to one CefBrowser and dispatch model events through the controller.
4. Chrome Views platform delegate / CefBrowserView ownership: distinguish window content host from per-tab page lifecycle; prevent a tab close from destroying the shared host.
5. Small TabStripModel observer adapter and split operations. Prefer existing Chromium APIs; any required Chromium patch must be separately identified rather than hidden in the CEF layer.
6. NativeViewHost-backed public native UI view: separately owned by the orchestrator, but its window/root lifetime must agree with the tab controller.

Removing the guard alone is the lower-line-count option but the higher architectural risk. A normal Browser/TabStripModel adapter is larger, yet retains Chromium's extension and ownership semantics. It still requires confirming that CEF's customized ChromeBrowserView does not suppress normal split/layout behavior.

## Maintenance estimate — judgment

Expect a multi-file CEF feature, not a 300-line patch: roughly 10–20 handwritten CEF source/header/build touchpoints before generated wrappers, plus any narrowly demonstrated Chromium adaptation. Initial implementation and one two-tab/split/native-UI proof are plausibly 1–2 engineer-weeks; extension, lifecycle, accessibility, and product parity may take substantially longer. This estimate excludes build-host time, DRM, migration, and release qualification. Treat it as sizing, not a delivery promise.

For every CEF update, inspect changes to BrowserWindowInterface creation, TabStripModel/TabInterface, BrowserView split layout, extension IDs, and the CEF platform delegate. Keep the adapter isolated, pin every fork revision, regenerate C API artifacts, and record upstream conflicts. A 72-hour security update target needs enough capacity to rebuild and rerun critical identity/lifecycle/native-host checks; a small diff alone does not establish that capability.

## First proof and blockers

Freeze the controller contract only after review. First implementation proof: one real normal Chromium window, two tabs with different visible documents, native SwiftUI selection, inactive-state retention, close with before-unload, and extension `tabs.query` showing both IDs under the same real window ID. Then show both as a split while extension activation/focus tracks the focused pane. Verify a third tab opened by an extension is reflected in native UI.

Require page accessibility and native control accessibility together, fullscreen transitions, keyboard commands, rapid tab close, active/inactive renderer failure, profile isolation, and orderly window shutdown. Until these pass, both the controller and native-view-host route remain unaccepted architecture. The subsequent user instruction authorizes implementation of this direction. Runtime acceptance is still required.
