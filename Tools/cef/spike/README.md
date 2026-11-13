# Native CEF host feasibility app

This standalone application isolates S1 from Boaz's production targets and profile data. It embeds one Alloy browser in an AppKit view inside a SwiftUI shell. Popups are deliberately blocked; extension hosting belongs to S2a.

Build against the checksum-verified standard arm64 distribution selected in the migration ledger:

```sh
cmake -S Tools/cef/spike -B build/cef-spike -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCEF_ROOT="/absolute/path/to/verified/cef_binary_distribution"
cmake --build build/cef-spike --target BoazCEFSpike -j 6
```

The output is `build/cef-spike/BoazCEFSpike.app`. It includes the official framework and five helper bundles. CEF's sandbox remains enabled. Each helper initializes its sandbox context before loading the CEF library. The native application loop owns event dispatch; CEF requests one-shot main-run-loop work through its external message pump.

The app uses `com.chenkahana.boaz.cef-spike` and stores its disposable browsing data under `~/Library/Caches/com.chenkahana.boaz.cef-spike`. It never opens Boaz's production profile.

Set `BOAZ_CEF_SPIKE_URL` when launching the executable directly to select the initial page, including a local data URL for offline inspection.

The build is not a distribution release: Developer ID signing, notarization, Gatekeeper acceptance, IME, VoiceOver, scrolling and resize verification are separate S1 gates. A successful compile does not satisfy them. The simple address field supports navigation, Back and Reload for manual inspection. Lifecycle callbacks are written to the process log.

The pump follows the pinned distribution's `tests/shared/browser/main_message_loop_external_pump.cc`: immediate scheduled work, reentrancy protection, and a maximum 33 ms one-shot idle fallback. Two event-only variants stalled during actual native UI inspection, so the upstream fallback is retained for this spike. Shutdown performs the sample's bounded ten-iteration work drain after all browser close callbacks and before `CefShutdown`. Its energy cost must be measured before production acceptance.
