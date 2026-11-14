# Chromium application signing and candidates

Use Chromium 157's generated packaging driver, not the CEF spike signer. The helper layout is different. The pinned sources are `chrome/installer/mac/signing/README.md`, `parts.py`, `driver.py` and `modification.py`. Development-signed real-application launch and inspector-only close have passed. Normal browsing, whole-application quit, production signing and clean-account acceptance remain open.


## Current application commands

`build-application.py --build` emits an immutable receipt with the native UI, CLI, Boaz icon and resolved distribution metadata. `stage-application.py --native-launch` produces a development candidate by default. Development candidates disable automatic production updates and retain separate Chromium storage.

Production assembly additionally requires explicit `--production-version VERSION --production-build BUILD`, with output ending in `Boaz.app`. It preserves the internal Chromium executable/framework layout, sets Boaz branding and Sparkle configuration, and uses `Boaz/Chromium` below Application Support. It does not alter the existing WebKit store. Resolve the published version before selecting these arguments; none is hardcoded.

Use `sign-production-application.py --input ASSEMBLY_DIRECTORY --output NEW_DIRECTORY --identity DEVELOPER_ID_IDENTITY --notary-profile STORED_PROFILE_NAME` only for a production assembly. The script copies its input and packaging tools, applies the recorded secure-timestamp correction only to that copy, preserves Sparkle service entitlements, signs nested components, submits with the named notarytool credential profile, requires Apple acceptance, and validates stapling/Gatekeeper. No password or API secret belongs in its arguments. This workflow has not yet been executed: the current local identity check found no Developer ID identity, and no notarytool credential-profile name has been supplied.

`Tools/release-mac.sh VERSION --chromium-app SIGNED_BOAZ_APP --output NEW_DIRECTORY --sparkle-bin SPARKLE_BIN --no-publish` verifies the actual production app and creates a local candidate DMG/appcast. Chromium mode requires `--no-publish`, refuses existing output, checks nested debugging entitlements, and enforces a 160,000,000-byte compressed DMG limit. Development signatures cannot pass this route. Existing WebKit release commands remain available.

`prepare-deltas.py --candidate SIGNED_BOAZ_APP --previous OLD_APP_1 --previous OLD_APP_2 --previous OLD_APP_3 --output NEW_DIRECTORY --sparkle-bin SPARKLE_BIN --no-publish` builds format-4 deltas, enforces 40,000,000 bytes each, reconstructs each candidate, compares file/type/mode/link inventories, and verifies signatures. Historical apps must be the three approved supported releases. The tool conservatively requires their Sparkle version to be at least 2.10.1. It does not establish approval history or run actual Sparkle installation. No production feed is changed.

All artifact commands use the SSD guard and preserve failed outputs. A prepared/signed artifact is not release acceptance. Protected playback, migration, performance, clean-account installation, Sparkle upgrade/deltas, a higher-version WebKit rollback and dogfooding still must pass.

## Retained prototype procedure

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

## Browser passkey capability

See [native website passkeys](passkeys.md) before enabling browser-passkey entitlements. The approval-required template is inactive. The current unbranded browser does not inherit Google's managed browser entitlement. Inspect the finished signed executable and authorized provisioning configuration before claiming Apple Passwords support.

## Cloud-managed Developer ID recovery

When the Developer ID key is cloud-managed, `export-cloud-application.py --input ASSEMBLY_DIRECTORY --output NEW_SUBMISSION_DIRECTORY --identity APPLE_DEVELOPMENT_SHA1` prepares and uploads an archive through the existing Xcode account. Submission success alone does not establish notarization.

After Apple processes the submission, run `export-cloud-application.py --finish --input SUBMISSION_DIRECTORY --output NEW_VERIFICATION_DIRECTORY`. This preserves the submitted archive, exports its notarized app, and checks signatures, production provisioning, stapling and Gatekeeper. A pending or rejected submission fails visibly; retry with a new output directory after resolving it. Package the returned `export/Boaz.app` through `package-candidate.py --no-publish` to enforce nested entitlement and Sparkle checks. Runtime acceptance is separate.

On 2026-11-14, the existing cloud archive exported successfully and its notarized app passed Gatekeeper and strict signature verification. The previous statement that no production signing route had run is superseded by this result.
