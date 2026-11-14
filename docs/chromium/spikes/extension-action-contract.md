# Native extension-action contract proposal

Status: proposed architecture for orchestrator review. The former 300-line/libcef-only constraint no longer applies. Native controls, real extension semantics, performance, and lifecycle acceptance remain mandatory. No source patch or runtime proof accompanies this design.

## Source evidence

Read-only Chromium checkout reported `8954d18543712dc11b97c3aca0a6e714aa2d7dcd`, the checked-out source for the pinned build. References below use Chromium `156.0.8078.88`.

- [`ExtensionActionViewModel`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/ui/extensions/extension_action_view_model.h) deliberately separates platform-neutral business logic from `ExtensionActionDelegate`. It provides title, accessibility name, icon, enabled state, site interaction, command registration, real user invocation, and API popup invocation.
- [`ExecuteUserAction`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/ui/extensions/extension_action_view_model.cc#468) calls `ExtensionActionRunner::RunAction` with tab permission grants enabled. It may open a popup, dispatch an action, or toggle a side panel. `TriggerPopupForAPI` explicitly does not count as user action. `TriggerPopup` creates a real `ExtensionViewHost` through `ExtensionViewHostFactory::CreatePopupHost` before transferring ownership to the delegate.
- [`ToolbarActionsModel`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/ui/toolbar/toolbar_actions_model.h) supplies profile-level action IDs, pinned IDs, initialization/shutdown, add/remove/update notifications, and incognito filtering. [`ExtensionAction`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/extensions/browser/extension_action.h) supplies tab-specific display badge text and colors.
- [`ExtensionsContainer`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/ui/extensions/extensions_container.h) is a browser-associated interface for action lookup, popup closure, API popup requests, and active WebContents. It is a useful integration seam independent of the existing Views toolbar.
- [`ExtensionActionDelegateDesktop`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/ui/views/extensions/extension_action_delegate_desktop.cc#68) depends on the Views container for popup anchors and ownership. Reusing it unchanged would retain that dependency. A CEF delegate should instead reuse the platform-neutral model.
- [`ExtensionPopup`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/ui/views/extensions/extension_popup.h) already owns the extension host and observes WebContents, tab selection, extension unload, widget lifecycle, and security dialogs. Prefer extending its anchoring rather than reimplementing those security/lifecycle rules.
- [`BubbleAnchor`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/ui/views/bubble/bubble_anchor.h) accepts a Views view or tracked element, not an arbitrary NSView/rectangle. A native anchor requires a real adapter or a small explicit popup anchoring API change. A hidden Views toolbar is unnecessary and excluded.
- [`OpenPopupInBrowser`](https://chromium.googlesource.com/chromium/src/+/156.0.8078.88/chrome/browser/extensions/api/extension_action/extension_action_api.cc#137) currently rejects absent Chrome toolbar before consulting `ExtensionsContainer`. A CEF container alone will not make `chrome.action.openPopup()` work.

## Proposed public CEF surface

Add `include/cef_extension_action.h` and `include/cef_extension_action_handler.h`; expose the handler through `CefClient` and the per-browser controller through `CefBrowserHost`. Use CEF translator-generated C API and C++ wrappers, not private symbols or command-line messaging. Shapes below are contracts to refine for translator compatibility, not compiled declarations.

| Type or operation | Contract |
|---|---|
| `CefExtensionActionController` | Browser-scoped refcounted handle. Registry stays scoped to its request context/profile. All operations on CEF UI thread. Closed controller rejects operations. |
| `GetActions()` / `OnActionsChanged(browser, revision, snapshots)` | Ordered immutable snapshots after model initialization; coalesce multiple invalidations per UI turn. First version can publish full snapshots because extension cohorts are small. |
| `CefExtensionActionSnapshot` | Extension ID, display name, accessible name, tooltip, enabled/pinned state, site-interaction enum, display badge text/colors, popup-present flag, immutable `CefImage` rendered at requested scale, and monotonically increasing revision. Icon contract explicitly says whether badge is composited; choose composited icon initially to preserve Chromium rendering and avoid duplicate badges. |
| `SetActivePage(browser, document_generation)` | Bind to the actual foreground WebContents through the accepted browser/tab architecture. Host cannot invent Chromium tab/window IDs. Reject inactive, closed, or wrong-profile page. Split-view focus determines active extension target. |
| `InvokeAction(extension_id, document_generation, anchor, source, callback)` | Native click/keyboard only. Validate enabled extension, profile, target generation, active page/window, and anchor. Then call `ExecuteUserAction`; never manufacture activeTab grants separately. Completion reports dispatched, popup shown, denied, canceled, or unsupported side-panel requirement. |
| `SetActionAnchor(extension_id, anchor)` | Update visible native button position for extension-initiated popup and keyboard invocation; clear when button disappears. Anchor contains the owning native window handle, screen-DIP rectangle, display scale, and host-issued generation. Do not retain an untracked NSView pointer. |
| `ClosePopup(reason)` / `OnPopupChanged(...)` | One popup per browser window. Engine owns popup/ExtensionViewHost. UI receives open/close state and returns focus to the originating button when appropriate. |
| `SetPinned(extension_id, pinned)` | Route through Chromium profile preferences/model; no duplicate Boaz persistence source. |

Action invocation callback success means dispatch or actual popup show, never a promise that an extension performed its desired network operation. Chromium's void dispatch path must be wrapped with explicit completion/cancellation bookkeeping. Normal page actions without popups complete after dispatch. Popup callbacks complete when shown or canceled. Unsupported side-panel behavior is an explicit parity blocker, not silent success.

CEF UI thread owns model, delegate, container, popup, and weak subscriptions. On macOS it must remain the integrated main/UI sequence. Swift copies snapshots into the observable facade on MainActor; no blocking call from CEF to SwiftUI. Icons cache by action/tab-state revision, size, scale, and theme. Invalidate on tab/navigation, action change, permissions, icon update, theme/scale, and profile shutdown. No polling or synchronous script calls.

## Toolbar-free implementation

Create a `CefExtensionActionsHost` implementing `ExtensionsContainer`, attached once to the real `BrowserWindowInterface` only when native actions are explicitly enabled. Retain normal Chromium container behavior for other browsers. Observe `ToolbarActionsModel`; create `ExtensionActionViewModel` instances with a new CEF `ExtensionActionDelegate` implementation. Its `GetActiveWebContents` resolves the actual active Boaz page, while the underlying Chromium tab/window model must agree with that selection. This proposal does not solve the separate multi-tab/window mapping contract.

The CEF delegate handles native accelerator routing, native context-menu presentation via typed menu data, and popup ownership. Reuse `ExtensionPopup` with an explicit native parent plus screen-rectangle anchor overload, ideally isolated to Chromium's extension popup layer. Verify that the underlying bubble supports a parent widget/window and explicit anchor rectangle before coding. If it requires a tracked-element adapter instead, use a real native tracked element associated with the visible SwiftUI button; do not create hidden controls.

Replace the toolbar-presence check in `OpenPopupInBrowser` with a capability query on `ExtensionsContainer`, defaulting to the existing toolbar policy. The CEF implementation advertises capability only when a visible, valid native action anchor exists in the active window. Preserve the API's other active-window/permission checks and call `TriggerPopupForAPI`, which grants no new user gesture permissions. This narrowly scoped upstream patch is preferable to claiming an invisible toolbar is visible.

Keep popup rendering inside Chromium's extension host. Do not navigate an ordinary browser to the popup URL. For permission/site-access context menus, first preserve Chromium commands through its `ExtensionContextMenuModel`; arbitrary native toggles must not bypass policy, incognito eligibility, withheld permissions, or permission prompts.

## Security and lifecycle

The API is privileged browser-process UI plumbing, never renderer-accessible. Calls from scripts, automation, or untrusted extension messages cannot enter the user-invocation path. A CEF embedding application is trusted, so source enums are not cryptographic proof of a gesture; Boaz must restrict this call to native event handlers. Automated popup requests use the non-user API path.

Before dispatch, recheck extension registry state, target profile/incognito eligibility, current WebContents and navigation generation, active window, and anchor ownership. Do not expose cross-profile action snapshots. Incognito configuration comes from Chromium's filtered model; do not copy regular-profile state into private profiles. No passwords/cookies enter this interface.

Use weak pointers and scoped observations. On navigation, target closure, focus transfer to another pane/tab, window close, extension unload/disable/update, profile teardown, or invalid anchor, close/cancel pending popup work and complete callbacks exactly once. Preserve Chromium security-dialog dismissal and Mac deferred-close behavior. Detach delegates before destroying models; stop subscriptions before profile destruction. Never hold a Swift object through an untracked raw pointer.

## Delivery estimate and acceptance

Judgment estimate, excluding generated output and separate native-parent/tab-model work: approximately 1,800–3,200 handwritten lines across 12–18 files. Public API/types/client-browser hooks 300–500; CEF model/container/delegate 800–1,400; popup anchor/capability integration 250–500; Boaz Objective-C++/Swift action facade and controls 450–800. Generated bindings add mechanical changes. These are planning ranges, not a proven patch size.

First bounded implementation should prove one installed action's snapshot, native button invocation, real popup on a visible page, and cancellation on navigation/close. Next cover activeTab grants versus API requests, badges/icons/disabled states, keyboard/VoiceOver, profile/incognito boundaries, popup focus/sizing, extension unload, and split-pane targeting. Finish with real cohort extensions, side-panel needs, permission controls, and performance budgets. User has not requested new tests; inspect upstream assertions/fixtures and use required existing builds and runtime acceptance.

Keep the CEF API addition and the minimal Chromium popup/capability changes in separate reviewed patch files with exact base revisions. Prefer upstreamable generic names and capability contracts. On every CEF security update, verify the model/delegate/container and popup signatures, reapply patches, regenerate bindings with the pinned translator, rebuild, and repeat action/security/lifecycle acceptance. Any changed permission or popup behavior blocks release; report impact on the 72-hour target rather than weakening it.

Known source supports the platform-neutral model/delegate seam and real host reuse. Native anchor bridging, toolbar-free capability integration, callback adaptation, and correct Boaz tab/window mapping remain design assumptions requiring implementation proof. This route is materially more maintainable than extracting toolbar children, but it is not yet accepted architecture.
