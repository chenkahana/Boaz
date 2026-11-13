# Direct native bootstrap

The isolated prototype adds `ChromeBrowserMainExtraParts` and a native BrowserWindow factory. Root owns the upstream hooks and GN wiring. The files do not replace Chromium main, subprocess dispatch, application loop, or sandbox initialization.

Activation requires `--boaz-native-host`, `--no-startup-window`, `--no-first-run`, `--profile-directory=Default`, and an existing canonical `--user-data-dir` strictly below `/Volumes/BoazBuild/cef/direct/profiles`. Canonical path comparison rejects symlink components. An existing Default profile path must also be canonical, and a dangling Default symlink is rejected. Failure stops the prototype with CHECK before normal profile initialization. This restriction depends on the root hook adding these extra parts before early initialization.

PostProfileInit accepts only the expected initial regular profile and acquires its keepalive through TryAcquire. PostBrowserStart posts library loading after startup unwinds. Only the canonical fixed `/Volumes/BoazBuild/cef/direct/ui/libBoazNativeUI.dylib` is loaded, with RTLD_NOW and RTLD_LOCAL. The library is never unloaded. State and the ABI table have process lifetime.

The ABI copies callbacks, guards UI-thread use and callback reentry, and forwards page operations to TabRegistry. Window creation consumes supplied options once, or synchronously asks Swift to prepare an attached native hierarchy. Invalid preparation is fatal; it cannot fall back to Chrome UI. The factory installs a genuine BrowserWindow adapter on Chromium's genuine Browser, with a real TabStripModel. The window-created event is posted before creation returns, but runs after construction unwinds. The initial explicit call returns the same registered handle. Native keyboard delivery excludes synthetic events and skip_if_unhandled events.

Window records hold weak BrowserWindowInterface references. Close requests call UnloadController::OnWindowClosing. Chromium owns browser destruction; the bridge never deletes a Browser. TabRegistry delivers window_closed only after its pages drain, then the bridge removes the record. Quit uses chrome::AttemptExit. BrowserCloseCancelled subscriptions clear the pending-exit state, allowing further requests. Shutdown-ready is emitted only when requested exit has no remaining registered windows; keepalives release on the main dispatch queue after Swift's queued cleanup.

## Source evidence

Inspected the pinned Chromium 157 source, without copying another host implementation:

- `chrome/browser/chrome_browser_main_extra_parts.h:27,41,43`: early initialization, initial profile, browser-start hooks.
- `chrome/browser/ui/browser.cc:270–314`: tab model and browser features exist before the BrowserWindow factory. The custom-window creation parameter is CHECK_IS_TEST-only; this implementation uses the real factory hook.
- `chrome/browser/ui/browser_window/public/create_browser_window.h:39–49`: supported BrowserWindowCreateParams constructors.
- `chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h:39`: TryAcquire may fail if the profile is being deleted.
- `chrome/browser/ui/browser_window/public/browser_window_interface.h:257–262`: close-cancel subscription and status callback.
- `chrome/browser/ui/unload_controller.h:181` and `unload_controller.cc:1122–1163`: close entry and Chromium-owned scheduled browser destruction.
- `components/input/native_web_keyboard_event.h:63–70`: owned native event and IME-sensitive skip flag.
- `base/files/file_util_posix.cc:714`: canonical path resolution.
- Existing `Tools/chromium/host/tab_registry.cc:297–313`: page-drain barrier before window_closed.

## Verification and remaining gates

Source signature/ownership inspection and `git diff --check` only. No tests, compilation, build-source edits, library loading, or runtime launch occurred in this packet. Root must compile and validate startup, two-tab state, Chromium-created popups, before-unload cancellation, failed preparation, and quit ordering.

The ABI has no preparation-canceled event. After successful preparation, a later factory failure deliberately aborts this prototype; recoverable creation failure requires extending that contract. The native factory must be installed for every Browser under this switch. Other profiles are rejected, including private and system windows; they remain future explicit work.

macOS shutdown includes application-level termination machinery. The main-queue cleanup ordering and process keepalive must be verified during actual AttemptExit, including an already-empty registry. This packet does not claim orderly runtime shutdown has passed. Profile/opener-specific popup geometry, permission UI, production packaging, signing, and product integration remain outside this prototype.
