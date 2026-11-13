# Preparing the GitHub Mac DMG

The default release path is Chromium with Boaz's native interface and in-app WebKit fallback. Mac App Store and iOS still use WebKit. PR #70 remains draft until essential production-distribution and existing-feature acceptance passes.

Build the pinned native host and matching Release UI with `make mac-dmg`. The guarded build uses `/Volumes/BoazBuild/cef`; keep that image attached. Build receipts identify completed immutable inputs. Do not combine a UI library with a different native ABI.

Prepare an unpublished production candidate using the completed native application and UI receipt:

```sh
Tools/release-mac.sh X.Y.Z \
  --base-app /Volumes/BoazBuild/cef/direct/chromium/src/out/BoazDevelopment/Chromium.app \
  --ui-receipt /Volumes/BoazBuild/cef/direct/app/runs/RUN/artifacts/build.json \
  --output /Volumes/BoazBuild/cef/direct/artifacts/NEW_RELEASE_DIRECTORY \
  --identity 'Developer ID Application: YOUR_AUTHORIZED_IDENTITY' \
  --notary-profile YOUR_NOTARYTOOL_PROFILE \
  --provisioning-profile /ABSOLUTE/PATH/Boaz.provisionprofile \
  --sparkle-bin /ABSOLUTE/PATH/SourcePackages/artifacts/sparkle/Sparkle/bin \
  --no-publish
```

Use a version newer than the published release and a new output directory. The command assembles `Boaz.app`, signs nested components and the browser, requires successful notarization, verifies Gatekeeper/stapling, and creates `package/Boaz.dmg`, its checksum, and a local candidate appcast. It never publishes. `make dmg VERSION=X.Y.Z RELEASE_ARGS='...'` forwards the same options.

The Developer ID private key must be available to `codesign`. An Apple Development identity is insufficient. The provisioning profile must authorize team `DPF8459C2J`, application `com.chenkahana.boaz`, production CloudKit container `iCloud.com.chenkahana.boaz`, and push notifications. The signer checks and embeds those grants, retaining Chromium helper entitlements and library validation. A cloud-managed Xcode signing identity alone is not supported by this nested signing workflow. Store notarytool credentials in the Keychain; never put passwords or private keys in command arguments or the repository.

Sparkle's existing EdDSA key stays in the login Keychain. The packager verifies its public key against the application. Preserve that key so existing installations can authenticate upgrades. The candidate appcast uses a local file URL and must not replace the production appcast. Publishing remains a separate reviewed release action.

## WebKit preservation

`make mac-webkit-dmg` builds the separate unsigned WebKit configuration. `Tools/release-mac.sh X.Y.Z --webkit --no-publish` preserves the previous Xcode archive/export/notarization workflow as an explicit rollback path. It does not silently replace a failed Chromium build. App Store builds continue to use `project.yml`.

## Upgrade and practical acceptance

Production Chromium keeps the existing sandboxed Boaz library in place when present and imports only missing preferences before restoring windows. It retains source data, refuses ambiguous duplicate libraries, and reports access failures. Cookie/password continuity and actual previous-store access still require upgrade acceptance; source implementation alone is not a pass.

Before marking the PR ready, exercise the actual signed app: HTTP/HTTPS navigation, tab creation/switch/close, same-profile restart/restoration, normal quit, WebKit fallback, and representative existing password, download, extension, permission and media behavior. Verify an essential upgrade without data loss. No development-only artifact substitutes for this pass.

Three-day dogfooding, exhaustive matrices, strict numerical performance/size gates and extended delta/rollback campaigns are deferred. Existing core features, security, data preservation, and a distributable Chromium-default application are not deferred.
