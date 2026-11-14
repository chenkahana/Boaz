# Direct-host tab registry packet

Status: implemented source adapter, **not compiled or runtime accepted**. Independently authored for the Boaz prototype ABI at integration `6730eb7`, plus the orchestrator's approved `active` field and view-replacement events. Read-only API inspection used verified Chromium `157.0.8103.51`, now at `/Volumes/BoazBuild/cef/direct/chromium/src`. No Crest source copied or executed.

## Ownership and behavior

`TabRegistry` owns observers and process-unique, monotonically allocated handles. It does not own Browser, TabStripModel, WebContents, or NSWindow. The native window factory must retain NSWindow until `window_closed`, register each eligible Browser, and keep the registry alive until its windows/pages have finished teardown. All entry points and callbacks run on Chromium UI/AppKit main thread; callback reentry returns unavailable. Root startup exposes the ABI table and validates its version.

A registered Browser's existing tabs and future extension-created tabs are observed. `chrome::AddAndReturnTabAt` creates real retained tabs; navigation uses NavigationController; activation uses the owning TabStripModel. Actual extension IDs come from ExtensionTabUtil, while the ABI `active` field comes from the model's active WebContents. IDs are not indices and are never reused during the process. A transfer to another registered same-profile window preserves the Boaz page handle and updates its window identity; ordinary tab selection retains inactive WebContents. Unregistered destination windows and cross-profile transfers are outside this packet's supported native-window lifecycle.

Callbacks use copied state/string snapshots and are posted to the UI runner after model mutation, except the two expressly approved native-view detach barriers. Invalid handles return errors; failed handle/view outputs are zeroed. The ABI has no load-failure event yet; renderer termination is reported separately rather than treated as page closure. Shutdown orchestration and native window creation remain root-owned prerequisites, not implemented placeholders here.

## Exact lifetime barriers

**Committed close:** Chromium `chrome/browser/ui/tabs/tab_strip_model.cc`, `SendDetachWebContentsNotifications`, calls `OnChange` around line 994 and destroys deleted tabs/WebContents at lines 1000–1004. The registry handles supported `kRemoved` notifications and checks `TabRemoveReasonUtils::WillDeleteWebContents`. Only deletion sends synchronous `PAGE_CLOSING`, while the contents/native view still exist. The callback may detach only; no Chromium or registry reentry. Transfer removal does not send closing. This does not misuse the drag-controller-only `OnTabWillBeRemoved` hook.

**Cancelled close:** `WebContentsObserver::BeforeUnloadFired(false)` and `BeforeUnloadDialogCancelled` reset the pending close and queue `PAGE_CLOSE_CANCELLED`. `OnTabCloseCancelled` covers the separate IsTabClosable rejection. The native view is never detached just because close was requested. Cancellation is reported only for a registry-requested pending close; ordinary navigation cancellation is ignored. Cancellation duplicates from the same turn are coalesced. External close-request notification is not exposed by this packet, so an external cancellation without a registry request does not emit a close-cancelled event. `WebContentsDestroyed` queues exactly one `PAGE_CLOSED`; observer deletion happens after that deferred callback, not within WebContents destruction.

**View replacement:** `TabStripModel::DiscardWebContents`, lines 385–419, owns the old WebContents in a local unique_ptr while it calls `OnChange(kReplaced)` and returns that ownership afterward. The registry sends synchronous `PAGE_VIEW_WILL_CHANGE` there, switches its observer to the replacement, increments document generation, and queues `PAGE_VIEW_CHANGED`. The Boaz handle survives. A separate replacement revision prevents stale replacement events from making an obsolete view available. Native-view access remains unavailable between the barrier and deferred readiness. Committed primary-document changes also increment generation; this is not authoritative password frame/document identity.

Model destruction is a second supported ownership barrier: `TabStripModel::~TabStripModel` (lines 282–286) notifies observers before destroying its tab-collection members. `OnTabStripModelDestroyed` sends closing for any remaining model-owned pages while their views still exist. Window-closed delivery waits until their deferred page-closed callbacks drain. `WebContentsDestroyed` uses only the cached closing snapshot; Chromium's observer header warns that this callback runs halfway through destruction, so the registry never tries to recover native-view access there.

The registry asserts that every observed WebContents destruction has a prior owner barrier and that registry destruction occurs only after pages/windows drain. Transfer to an unregistered model or destruction outside registered model ownership is unsupported and fails that invariant; root must register destination Browsers before allowing eligible transfers or prevent those transfers. This is a required integration constraint, not a claim that arbitrary external ownership is safe.

If a page closes before its queued creation notification, stale nonterminal events are suppressed. `get_native_view` is unavailable until creation/view readiness has been delivered. The terminal event still reports the accepted handle. Consumers must tolerate rapid create/close without a successful mounted page.

## Required integration

Root implements this internal C++ symbol in its Objective-C++ bridge:

```cpp
namespace boaz {
void* NativeViewForContents(content::WebContents* contents);
}
```

It must run on UI/main thread, return the borrowed native NSView (or null), and transfer no ownership. `GetNativeNSView` is guarded by `__OBJC__` in Chromium's native UI header, so ordinary `tab_registry.cc` deliberately does not call it. Root adds GN sources/dependencies, the updated ABI header, native BrowserWindow factory, registered isolated profile, startup/table forwarding, window-close orchestration, and shutdown completion. `CloseWindow` requests model `CloseAllTabs`; native BrowserWindow teardown must occur through Chromium's normal empty-tab/window lifecycle, not by prematurely destroying NSWindow.

## Verification performed and limits

- Crosschecked AddAndReturnTabAt, TabStripModel observer/change structures, close reasons, navigation controller methods, renderer failure callback, actual extension-ID functions, and native-pointer language restriction against the pinned 157 source.
- Read existing `TabStripModelTest.CloseInactiveTabKeepsSelection` and `CloseActiveTabShiftsSelectionRight` assertions (lines 2240–2285), plus model observer close-all cancellation handling. No tests added or run.
- `git diff --check` passed. No full build, generated header assumptions, signing, or runtime claims.

Compile requires the root's Chromium GN integration and generated Chromium headers plus the native-view bridge; this source packet alone is not a runnable application. Runtime acceptance must cover two retained DOM states, extension-created selection/close, real shared extension-window IDs, before-unload cancel/accept, view replacement, rapid close, renderer failure, eligible transfers, native view detachment, and window/application teardown.
