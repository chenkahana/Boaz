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

The build is not a distribution release: Developer ID signing, notarization, Gatekeeper acceptance, IME, VoiceOver, scrolling and resize verification are separate S1 gates. A successful compile does not satisfy them. The simple address field supports navigation, Back and Reload for manual inspection. Lifecycle callbacks are written to the process log.

The pump follows the pinned distribution's `tests/shared/browser/main_message_loop_external_pump.cc`: immediate scheduled work, reentrancy protection, and a maximum 33 ms one-shot idle fallback. Two event-only variants stalled during actual native UI inspection, so the upstream fallback is retained for this spike. Shutdown performs the sample's bounded ten-iteration work drain after all browser close callbacks and before `CefShutdown`. Its energy cost must be measured before production acceptance.

An earlier build stalled HTTPS and hit the shutdown watchdog. A native stack captured its worker blocked in `SecItemCopyMatching` and Keychain decryption while the main thread waited in Chromium shutdown. Explicit spike-only Keychain names and a fresh profile directory resolved both behaviors without disabling encryption, sandboxing, or certificate validation. Do not reuse the old spike cache with the new Keychain identity.
