# S2b native-parent feasibility


**Superseded scope constraint:** the user subsequently authorized a broader maintainable CEF/Chromium adapter, including public interfaces. References below to a 300-line limit or pending scope approval describe the earlier assessment only. See the current [architecture decision](../feasibility.md#architecture-decision-after-native-accessibility-comparison). Runtime failures and product acceptance requirements still apply.
Decision: no supported implementation within the current contract has been established. Do not treat a successful custom CEF build as passing this gate. This is a source-based NO-GO for proceeding with the proposed small patch, not proof that a larger browser integration is impossible.

## Deterministic evidence

The build-owned checkout at `/Volumes/BoazBuild/cef/chromium_git/cef` resolves to `57389f04a61ab0e9603d9f96602843d0e08bb11c`. It was inspected without modification.

1. [`CefBrowserCreateParams::MaybeSetWindowInfo`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/browser_host_create.cc#L222-L268) explicitly disables Chrome style for a Mac native parent and resets the selected style to Alloy. Removing this check changes admission only.
2. [`chrome_child_window::GetParentWidget`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/chrome/views/chrome_child_window.cc#L25-L40) returns the native parent widget on Windows/Linux, but returns null on Mac. `GetParentHandle` separately recognizes Mac `parent_view`; recognizing the handle does not implement hosting.
3. The Windows/Linux route creates a CEF Views browser and child window through `ChildWindowDelegate::Create` and `MaybeCreateChildBrowser` in that same file. [`CefWindowView::CreateWidget`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/views/window_view.cc#L507-L542) sets `params.parent_widget`, child/control flags, and frameless state. The comments describe native Windows child-window styles. This is not evidence that an NSView can be substituted on Mac.
4. [`CefNativeWidgetMac::CreateNSWindow`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/views/native_widget_mac.mm#L82-L108) creates a `CefNSWindow`. [`ChromeBrowserWidget::Init`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/chrome/views/chrome_browser_widget.cc#L34-L69) binds BrowserView state and Mac native-widget state to that window. Moving its content view alone does not transfer those contracts.
5. Official [issue3294](https://github.com/chromiumembedded/cef/issues/3294) remains open. Its [Mac discussion](https://github.com/chromiumembedded/cef/issues/3294#issuecomment-1465030769) identifies the NSView-versus-NSWindow mismatch and warns that content-view reparenting can produce undefined behavior. It proposes an overlaid child NSWindow as a hypothesis. That proposal is not a verified native-NSView implementation and does not meet this task's prohibition on substituting a window overlay.
6. [`ChromeBrowserHostImpl::GetBrowserForBrowser`](https://github.com/chromiumembedded/cef/blob/57389f04a61ab0e9603d9f96602843d0e08bb11c/libcef/browser/chrome/chrome_browser_host_impl.cc#L99-L109) documents one host per Views-hosted Browser, versus one host per tab for other Chrome browsers. Parenting independent Views windows under one Boaz window does not establish a shared Chrome tab/window model.
7. The independently recorded [action-host assessment](S2-actions.md) still applies. The public API supplies a whole Chrome toolbar, not native extension controls or an action invocation/anchor contract. Native parenting does not change that gap.

## Patch boundary and judgment

Two small edits could remove the admission check and stop returning null for the parent. They would not supply a valid Mac widget host. Treating those edits as the implementation would skip native-window ownership, focus, modal dialogs, popups, coordinate conversion, accessibility, and destruction behavior.

A complete design would need all of these, within one total 300-changed-line ceiling under `libcef/`:

- A Mac native-host implementation that consumes the existing NSView parent while maintaining Chrome's native-widget/window bridge. Candidate review sites are `browser_host_create.cc`, `chrome/views/chrome_child_window.cc`, `views/window_view.cc`, `views/native_widget_mac.mm`, and `chrome/views/chrome_browser_widget.cc`. The inspected code provides no complete adapter to reuse.
- Explicit mapping of Boaz tabs and split panes to Chromium browser/window IDs, including active-tab selection and popup opener relationships. Separate child Browser instances do not prove the required semantics.
- An extension action model, change notifications, real invocation with active-tab grants, and popup anchoring to native Boaz controls. Existing public interfaces do not express those operations. An ordinary supported API addition requires changes under `include/` and generated bindings, outside the stated scope. An internal export or message bridge would be a new security-sensitive contract, not an already supported loophole.

No defensible total line estimate is available because the native-host and action interfaces remain undesigned. In particular, there is no evidence that all three requirements fit within 300 lines. A hidden toolbar, clipped Chrome UI, direct popup URL, or unverified content-view reparenting is excluded rather than counted as a solution.

Proceeding requires an approved change to scope or a concrete design resolving these contracts before production work. The ongoing custom build can independently prove build/storage/media feasibility; it does not settle S2b. No source patch, build, launch, or runtime test was performed for this assessment.
