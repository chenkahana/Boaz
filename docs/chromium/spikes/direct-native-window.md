# Direct native BrowserWindow adapter

Implemented independently from Chromium 157.0.8103.51 public interfaces. No Crest code copied. Files are integration inputs; root owns their GN inclusion, bootstrap, and tab registry. Compilation and runtime acceptance remain pending.

`CreateNativeBrowserWindow(BrowserWindowInterface*, void* NSWindow, const NativeWindowServices&)` returns Chromium's custom-deleter BrowserWindow pointer. The adapter copies services, requires every callback, retains NSWindow under Objective-C ARC, and borrows the BrowserWindowInterface. All use and destruction must occur on AppKit main. Its `Close()` requests closure only. The registry owner closes the NSWindow after browser/window completion; deleting this adapter does not close the native window.

Service provider requirements:

- `content_view` returns a live borrowed NSView in the retained window, representing the active page viewport. Do not return the complete SwiftUI content view including native controls. Keep that view available until modal observers have received host destruction.
- `focus_address` and `focus_toolbar` move native focus. `handle_key` consumes only keys it actually handled; page keys otherwise return to Chromium. Chromium's Browser handles exclusive-access key policy before forwarding to BrowserWindow.
- `exclusive_access_notice(text, visible)` synchronously shows or hides accessible native security guidance. The adapter reuses upstream `ExclusiveAccessBubble` show/snooze timers and localized instruction text. It reports timeout only after that display interval; replacement/destruction interrupts the callback. Providers must not destroy the adapter synchronously while handling a notice callback.
- `request_close` starts the existing coordinated close path and tolerates repeated close requests.

Implemented behavior includes native show/hide/activation, minimization/zoom/restore, native handle, screen-coordinate conversion using Chromium helpers, bounds/content sizing, active-page focus and title, theme/color providers, address/toolbar focus, keyboard delegation, native modal host geometry and observer notifications, fullscreen enter/exit, and native fullscreen completion forwarding. Notifications are registered independently; the application's NSWindow delegate is never replaced. Observer registrations and attention requests are removed on adapter destruction.

The modal host uses the active content view, constrains dimensions to that viewport, centers dialogs, and notifies on native window geometry and tab changes. Call `ToolbarSizeChanged` when native controls change viewport geometry without resizing the window. Nonactive tabs return no modal host in this initial implementation, pending explicit background-dialog policy.

Source audit covered `browser_window.h`, `ui/base/base_window.h`, `exclusive_access_context.h`, and modal-host interfaces. Every Mac pure-virtual method name is represented; `ToggleMultitaskMenu` is ChromeOS-only. Signature declarations were checked against those headers. This is not compilation evidence. Upstream fullscreen requirements are in `fullscreen_controller.cc:488–498`; Mac completion semantics are documented in `browser_view.cc:5547–5551`. Notice timing comes from `exclusive_access_bubble.h:32` and its implementation, rather than a new timer policy.

Required acceptance still pending:

- Initial content resizing assumes a single viewport. Split-pane ratio-preserving window resize needs the registry/layout contract and runtime validation.
- Fullscreen display targeting currently logs unsupported and uses the current display. Fullscreen transition failure, rapid opposing requests, Spaces, window restoration from zoomed/minimized states, and browser/tab fullscreen layout need runtime completion work before parity.
- Pointer/keyboard lock requires proving existing Browser/ExclusiveAccessManager routing and accessible native notice presentation. No separate lock grant is implemented here.
- Permission/autofill bubbles, native find, downloads UI, bookmark UI, translation, external-app picker, eye dropper, caret browsing, private-data dialogs, native menu accessibility, and background-tab dialogs remain product gates. Native tab UI receives its authoritative state through the root-owned registry; Chrome toolbar update hooks do not create duplicate Chrome controls.
- Missing Chrome-only UI returns explicit unavailable results where supported: translate returns invalid-window, intent-picker callback reports error-before-picker, survey invokes failure, pending-download close callback cancels. Pointer-returning optional facilities return null. Void optional UI requests log unavailability rather than showing Chrome UI. No result claims successful presentation.
- Chrome toolbar/location visibility stays false. Extension actions therefore require the separately planned real native container integration; this adapter does not pretend Chrome controls exist.

No build configuration, build-owned source, or tests changed. Root must compile with ARC, supply services and lifecycle ordering, then run the single-window input/fullscreen/modal/close proof before expanding feature use.

Review correction: native notifications now capture a weak pointer, invalidated before observer removal and UI teardown. Queued main-queue notifications therefore cannot dereference a destroyed adapter. Will-enter-fullscreen only records restore state; it never dismisses the exit notice. Did-enter-fullscreen forwards Chromium state completion and restarts the notice's upstream show interval, so a long native transition does not consume its entire visible interval. Resigning key status still interrupts guidance. Restored state uses live native zoom status outside minimized/fullscreen states and records the previous state before miniaturization/fullscreen, including maximize-then-minimize. These paths were checked in source; native timing and lifecycle remain runtime gates.

The modal-host lookup now returns the shared native host for every WebContents owned by this Browser's TabStripModel, including inactive tabs, and rejects null/unowned contents. Chromium 157's `BrowserWindowModalDialogDelegate::NotifyModalDialogsPositionRequiresUpdate` iterates all tabs and requires a non-null host for each; limiting lookup to the active tab violated that contract. The adapter includes `tab_strip_model.h` for the membership query. Source-contract inspection and diff validation cover this change; inactive-page prompt activation/visibility policy and runtime modal behavior remain pending acceptance.
