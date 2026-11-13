# Retained-tab native UI prototype

`Tools/chromium/ui/BoazHostUI.swift` exports `BoazNativeUIStart` for the frozen prototype C ABI 2. Compile with `boaz_host.h` as the bridging header after root adds the agreed `BoazHostWindowOptions.address_field` callback. This file consumes that field; it does not modify the shared header.

The entry validates table size/version and required function pointers, copies the table, registers callbacks, and creates one retained NSWindow with two requested pages. Chromium remains responsible for the application run loop. The UI never calls `NSApplication.run` or terminates the process directly.

SwiftUI supplies native controls around stable NSViewRepresentable instances for the page viewport and NSTextField address entry. The address field is retained and attached through window close; its provider performs no engine call. Page updates do not overwrite an actively edited address. The root-owned LocationBar adapter is responsible for per-tab edit save/restore and revert semantics.

All engine commands originating from callbacks or UI actions are queued onto main. Ordinary page callbacks copy borrowed UTF-8 state before returning, then update the UI and retrieve borrowed native views after model mutation unwinds. PAGE_CLOSING and PAGE_VIEW_WILL_CHANGE synchronously detach only; they do not call back into the engine. Native views are weakly referenced and reparented into the stable viewport on actual activation. Switching tabs requests activation; it does not navigate or reload a page.

Window/service context is retained by the session until window_closed. NSWindowDelegate denies automatic close and requests coordinated engine closure. Only window_closed releases the visible window. shutdown_ready releases session state after pending window completion. Before-unload cancellation leaves the window alive and displays a cancellation message. Distinct engine page handles identify tabs.

The prototype exposes address navigation, back/forward/reload, add/activate/close tab, close window, and explicit Quit through request_shutdown. A window-scoped local event monitor implements Command-L/T/W/R/Q while native controls have focus; the service callback handles the same commands when delivered from the engine. All engine work remains queued. Native notices are visible SwiftUI text with accessibility labels. Renderer failure and API errors are explicit UI states.

Verification in this packet is source-contract inspection only. Root owns the compile invocation and subsequent runtime check. No engine launch, profile mutation, build configuration, signing, or tests were added. Acceptance still requires successful compilation against the updated ABI, two-page DOM retention, real tab/window IDs, canceled close, native focus/VoiceOver, borrowed-view replacement, and orderly shutdown. This is an isolated prototype, not product completion or the real Boaz application.
