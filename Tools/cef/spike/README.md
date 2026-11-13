# Native CEF host feasibility app

This standalone application isolates S1 from Boaz's production targets and profile data. It embeds one Alloy browser in an AppKit view inside a SwiftUI shell. Popups are deliberately blocked; extension hosting belongs to S2a.

Current verdict: **S1 partial**. Local content and HTTPS Example Domain render. Native inspection confirmed text input and window resizing. The latest run reached `OnBeforeClose`, completed `CefShutdown`, and exited with code 0. Signing/notarization, IME, VoiceOver, momentum scrolling, and performance remain acceptance gates.

Build against the checksum-verified standard arm64 distribution selected in the migration ledger:

```sh
cmake -S Tools/cef/spike -B build/cef-spike -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCEF_ROOT="/absolute/path/to/verified/cef_binary_distribution"
cmake --build build/cef-spike --target BoazCEFSpike -j 6
```

The output is `build/cef-spike/BoazCEFSpike.app`. It includes the official framework and five helper bundles. CEF's sandbox remains enabled. Each helper initializes its sandbox context before loading the CEF library. The native application loop owns event dispatch; CEF requests one-shot main-run-loop work through its external message pump.

The app uses `com.chenkahana.boaz.cef-spike` and stores its disposable browsing data under `~/Library/Caches/com.chenkahana.boaz.cef-spike/isolated-keychain-v1`. It never opens Boaz's production profile. `CefSettings.keychain_service_name` and `keychain_account_name` explicitly select the spike's own OSCrypt key; an isolated profile directory alone does not isolate the default Chromium Keychain item.

Set `BOAZ_CEF_SPIKE_URL` when launching the executable directly to select the initial page, including a local data URL for offline inspection.

Set `BOAZ_CEF_SPIKE_HOST=views` to run the S2a single-page Chrome-style experiment. A `CefWindow` owns one `CefBrowserView`, with no Chrome toolbar. CEF's box layout reserves space for SwiftUI toolbar and sidebar views. A plain AppKit content wrapper contains the unchanged CEF native root and the SwiftUI views as siblings. The browser remains in the CEF Views hierarchy. The default mode remains the S1 Alloy host.

This mode does not establish tabs, split view, extensions, or native window-management parity. The selected CEF revision permits only one Chrome-style BrowserView per CefWindow, so those requirements need separate evidence.

The build is not a distribution release: Developer ID signing, notarization, Gatekeeper acceptance, IME, VoiceOver, scrolling and resize verification are separate S1 gates. A successful compile does not satisfy them. The simple address field supports navigation, Back and Reload for manual inspection. Lifecycle callbacks are written to the process log.

The pump follows the pinned distribution's `tests/shared/browser/main_message_loop_external_pump.cc`: immediate scheduled work, reentrancy protection, and a maximum 33 ms one-shot idle fallback. Two event-only variants stalled during actual native UI inspection, so the upstream fallback is retained for this spike. Shutdown performs the sample's bounded ten-iteration work drain after all browser close callbacks and before `CefShutdown`. Its energy cost must be measured before production acceptance.

An earlier build stalled HTTPS and hit the shutdown watchdog. A native stack captured its worker blocked in `SecItemCopyMatching` and Keychain decryption while the main thread waited in Chromium shutdown. Explicit spike-only Keychain names and a fresh profile directory resolved both behaviors without disabling encryption, sandboxing, or certificate validation. Do not reuse the old spike cache with the new Keychain identity.

The first Views embedding put SwiftUI inside Chromium's native content view. It rendered, but native controls were absent from accessibility and clicks did not reach them. In Chromium 156.0.8078.88, `components/remote_cocoa/app_shim/bridged_content_view.mm` routes root hit tests directly to Views (lines 326–331) and exposes only Chromium's accessibility tree (1724–1734). The sibling wrapper avoids those overrides without changing Chromium or moving the browser out of its Views hierarchy. The same source adjusts event coordinates when the CEF root is not the window's content view (549–554). Fullscreen and other window transitions still require acceptance evidence.

S2a single-page evidence (2026-11-13): the arm64 Release build passed. The final native inspection showed the Chrome page at the correct origin, page text input, native controls in the accessibility tree, sidebar navigation to HTTPS Example Domain, and resizing to 1920 pixels wide without moving the page origin or losing its input. Red-window close reached `OnBeforeClose` and `CefShutdown complete`; process exit was 0 (PID 11010, 10:19:51–52 local time). Cmd+Q did not close the earlier wrapper run and remains an unresolved routing gate. Accessibility-tree exposure is not VoiceOver acceptance.

The wrapper must set the CEF root frame **after** adding it: Chromium's `viewDidMoveToWindow` resets its size to zero when it is no longer the content view. A diagnostic launch confirmed a zero root frame inside a 1100×728 wrapper before correcting that ordering. These observations establish only the single-page native-host experiment; extension installation, tab identity, split view, fullscreen, keyboard command routing, Stage Manager, Mission Control, signing, and notarization remain unverified.
