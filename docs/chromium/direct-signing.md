# Direct-host development signing

Use Chromium 157's generated packaging driver, not the CEF spike signer. The helper layout is different. The pinned sources are `chrome/installer/mac/signing/README.md`, `parts.py`, `driver.py` and `modification.py`. This procedure is preparation; no direct-host signing or launch has passed yet.

`Tools/chromium/build.py --build` now builds `chrome` and `chrome/installer/mac` in the non-component arm64 configuration. The resumed ABI 4 build includes both targets. The latter generates `Chromium Packaging/sign_chrome.py` and `signing/build_props_config.py`. Calling the source-tree driver without generated configuration is insufficient. The current build output is `/Volumes/BoazBuild/cef/direct/chromium/src/out/BoazDevelopment`.

Run signing through `Tools/cef/run-build.py` after compilation ends. Use a new output directory under `/Volumes/BoazBuild/cef/direct/artifacts` and the same verified Apple Development identity across rebuilds. Do not overwrite a previous signed candidate or mutate the build output. Supply the certificate SHA-1 as `--identity`; confirm it is still a valid local signing identity before use.

```sh
/opt/homebrew/bin/python3.12 "$OUT/Chromium Packaging/sign_chrome.py" \
  --input "$OUT" --output "$NEW_SIGNED_DIRECTORY" \
  --identity "$SIGNING_IDENTITY" \
  --development --disable-packaging --notarize none
```

The driver signs nested tools/libraries/helpers, then the framework and outer application. It handles standard, Renderer, GPU and Alerts helpers, plus Aperitif variants and other configured tools. Renderer/GPU helper entitlements enable JIT. The normal browser retains library validation; the native Swift/AppKit dylib requires the same signing team, not a library-validation bypass. No `--deep` signing.

Sign `/Volumes/BoazBuild/cef/direct/ui/libBoazNativeUI.dylib` with the same identity using `codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none`. Close the prototype before rebuilding or re-signing its loaded code. The UI build refuses an in-use library and preserves the previous library when promoting a new build.

Verify the dylib with `codesign --verify --strict --verbose=2` and the staged app with `codesign --verify --deep --strict --verbose=2`. Inspect their TeamIdentifiers and designated requirements with `codesign -d -r- --verbose=4`. Inspect nested entitlements against the generated helper list, not a hardcoded CEF count.

Development mode injects `get-task-allow`, skips release Gatekeeper assessment and omits provisioning profiles by default. It does not pass Developer ID, notarization or clean-account distribution acceptance. Final release signing is a separate gate.

## Isolated launch

The bootstrap requires `--boaz-native-host`, `--no-startup-window`, `--no-first-run`, `--profile-directory=Default` and an explicit existing canonical `--user-data-dir` strictly below `/Volumes/BoazBuild/cef/direct/profiles`. It refuses symlinked/noncanonical paths and unexpected initial profiles. Keep one stable development profile and signing identity across relaunches. The Swift UI loads only from its fixed direct-workspace path.

Never reset Keychain items, widen access rules or use mock-keychain behavior to pass acceptance. A Keychain prompt or profile stall remains diagnostic evidence. Do not reuse the earlier ad-hoc CEF profile for this distinct host. Verify the actual running executable/profile before recording a result.

Required runtime results include retained tabs, real extension IDs, address edit retention, native/page accessibility, input, permission cancellation, pending-callback close, renderer failure and clean quit with no helpers. The initial permission sheet supports only camera, microphone and notifications; other requests remain explicit parity work. Successful compilation is not evidence for these results.
