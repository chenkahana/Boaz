# S2a extension actions and native controls

Pinned source: CEF `57389f04a61ab0e9603d9f96602843d0e08bb11c`, Chromium `156.0.8078.88`.

## Evidence

The integrated extension ledger records a successful real uBlock action popup with the diagnostic normal Chrome toolbar. It identified `example.com` and injected the Remove an element overlay into that visible page. This establishes one working Chrome action path; it does not establish a native Boaz action host.

The public [`GetChromeToolbar`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/include/views/cef_browser_view.h#L83-L92) returns a whole toolbar view after attachment. [`OverrideCreateToolbar`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/chrome/views/chrome_browser_view.cc#L85-L109) creates only normal or location modes, or no toolbar. There is no extension-only mode.

The returned object is [`CefToolbarViewImpl : CefViewImpl<..., CefView, ...>`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/chrome/views/toolbar_view_impl.h#L17-L20), not a CefPanel. Thus `AsPanel()->GetChildViewAt()` is not a supported route to individual toolbar controls. Even panel child conversion uses [`view_util::GetFor(..., false)`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/views/panel_impl.h#L200-L214), which returns only [registered CEF wrappers](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/views/view_util.cc#L54-L60). It does not expose arbitrary Chromium descendants as CEF views.

Moving the complete toolbar into another CefPanel remains whole-toolbar placement. No public API found exposes a native NSView for an individual extension action, detaches the extensions container, or invokes a selected extension action by ID with a native anchor. [`IsChromeToolbarButtonVisible`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/include/cef_command_handler.h#L105-L113) controls supported built-in buttons; it supplies neither an extension-action model nor an extension popup host. Command dispatch accepts Chromium command IDs, not an arbitrary extension ID and active-tab grant.

Chromium's [`ExtensionActionShowPopupFunction`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/extensions/api/extension_action/extension_action_api.cc#137) checks toolbar support and visibility before using the browser's extensions container. A missing toolbar fails with `Browser window has no toolbar.` Loading `popup.html` as a page does not execute that action path or establish its active-tab permission grant.

## Decision

S2a using the pinned, unmodified public CEF API is NO-GO for the required combination of native Boaz extension controls, genuine action semantics on visible tabs, and no Chrome toolbar/omnibox. The diagnostic normal toolbar passes a useful prerequisite, but does not pass that product gate. This verdict concerns the inspected public API, not an assertion that Chromium cannot support custom integration.

Clipping, transparent or offscreen Chrome controls, accessibility-driven button clicks, and substituting popup URLs do not resolve the gate. They leave unsupported focus, accessibility, targeting, or permission behavior. Reparenting the whole toolbar is also insufficient.

## S2b feasibility boundary

A native-parent patch alone would not resolve extension action hosting. Before accepting a custom-build route, a bounded patch must demonstrate both window ownership and real action integration within the same total limit of 300 changed lines under `libcef/`.

Candidate investigation, not an approved implementation:

1. At `ChromeBrowserView` and `CefToolbarViewView`, determine whether a real, visible extension-only toolbar composition can preserve Chromium's extensions container and popup anchor contracts while omitting creation of other Chrome controls. Merely hiding a retained omnibox is excluded. Existing CEF subclasses are the only permitted patch sites; required Chromium edits exceed this contract.
2. Determine how Boaz obtains action IDs, titles, icons, badges, enabled state, and change events, then invokes an action for an explicit visible browser and native anchor. Use Chromium's real invocation path so activeTab grants and popup lifecycle remain correct. Public CEF headers cannot be changed under the `libcef/`-only restriction; a new bridge/export mechanism would need an explicit reviewed contract. No such supported bridge has been demonstrated.
3. Account for close/navigation cancellation, focus return, permissions, multiple profiles, action removal, and both split panes. Window parenting and extension work share the 300-line ceiling; do not budget each separately.

There is no source-backed complete patch design within that ceiling yet. Counting hypothetical lines would conceal the missing interface and ownership design. The custom-build route remains blocked on that design or Chen changing the patch/product constraint. A custom build by itself cannot make this API gap pass.

Verification: one focused read of pinned public headers and corresponding implementations, plus the existing runtime ledger. No build, app launch, source clone, or runtime mutation was performed for this report.
