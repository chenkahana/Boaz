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

The Developer ID private key must be available to `codesign`. An Apple Development identity is insufficient. The provisioning profile must authorize team `DPF8459C2J`, application `com.chenkahana.boaz`, production CloudKit container `iCloud.com.chenkahana.boaz`, and push notifications. The signer checks and embeds those grants, retaining Chromium helper entitlements and library validation. For a cloud-managed Developer ID key, add `--cloud-signing`, pass the local Apple Development certificate SHA-1 as `--identity`, and omit the notary/provisioning arguments. Xcode supplies distribution signing and provisioning. See [cloud export recovery](chromium/direct-signing.md#cloud-managed-developer-id-recovery) if notarization is still pending. Store notarytool credentials in the Keychain; never put passwords or private keys in command arguments or the repository.

Sparkle's existing EdDSA key stays in the login Keychain. The packager verifies its public key against the application. Preserve that key so existing installations can authenticate upgrades. The candidate appcast uses a local file URL and must not replace the production appcast. Publishing remains a separate reviewed release action.

## Automatic releases on GitHub

`.github/workflows/release.yml` publishes a release for every master commit that touches the Mac app (the app and
shared sources, BoazKit, `Tools/chromium`, the XcodeGen specs). It builds the interface on a GitHub-hosted Mac,
cloud-signs and notarizes it, packages the DMG, and creates `vX.Y.Z` with `Boaz.dmg`, its checksum and the
`appcast.xml` that installed copies read from `releases/latest`. Nothing runs on the build Mac except refreshing
the Chromium base.

**Version.** CHANGELOG's newest `## [X.Y.Z]` when it is newer than every `v*` tag, with that section as the notes.
Otherwise the next patch after the newest tag, with the commit subject as the notes; CI doesn't edit CHANGELOG.md.
Run the workflow by hand with `dry_run` (the default) to build, sign and notarize without publishing; the DMG is
kept as a workflow artifact for three days.

**Secrets** (Settings › Secrets and variables › Actions):

- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`: an App Store Connect team API key with the **Admin** role, which
  cloud-managed Developer ID signing requires. Create it in App Store Connect › Users and Access › Integrations ›
  App Store Connect API › Team Keys; `ASC_KEY_P8` is the downloaded `.p8` file's text.
- `SPARKLE_ED_PRIVATE_KEY`: the file written by `generate_keys -x sparkle.key` (in the Sparkle `bin` directory of a
  UI build run, `/Volumes/BoazBuild/cef/direct/app/runs/RUN/SourcePackages/artifacts/sparkle/Sparkle/bin`) on the
  Mac whose login keychain holds the key. It must be the key behind `SUPublicEDKey`; packaging checks.
- `APPLE_DEVELOPMENT_P12`, `APPLE_DEVELOPMENT_P12_PASSWORD`: an Apple Development certificate with its private key,
  exported from Keychain Access as `.p12`, then `base64 -i cert.p12 | pbcopy`. `export-cloud-application.py`
  signs the archive with it before Xcode re-signs it with the cloud Developer ID certificate.

The workflow stops with the list of missing secrets before building.

**Chromium base.** Hosted runners can't build Chromium, so the workflow downloads it from the prerelease
`chromium-base-KEY`, where KEY digests the committed Chromium inputs (`Tools/chromium/host`, `patches`, `adblock`,
the source, patch and toolchain locks, `development.json`, `build.py`, `build-adblock.py`). The archive holds
`Chromium.app`, its signing scripts (`Chromium Packaging`), the content-blocking library and assets, and
`native-built.json`. When a commit changes those inputs, the release fails with "Chromium changed — base KEY not
uploaded". Then, on the build Mac, in a clean checkout of that commit:

```sh
python3 Tools/chromium/apply-patches.py --apply
python3 Tools/chromium/install-host.py --install
python3 Tools/chromium/build.py --build --jobs 10
Tools/chromium/chromium-base.py pack --upload   # checks the build matches the checkout, then publishes the prerelease
```

and re-run the failed workflow. `Tools/chromium/chromium-base.py key` prints the tag a checkout needs. A
prerelease never becomes `releases/latest`, so Sparkle's feed keeps pointing at the app.

## WebKit preservation

`make mac-webkit-dmg` builds the separate unsigned WebKit configuration. `Tools/release-mac.sh X.Y.Z --webkit --no-publish` preserves the previous Xcode archive/export/notarization workflow as an explicit rollback path. It does not silently replace a failed Chromium build. App Store builds continue to use `project.yml`.

## Upgrade and practical acceptance

Production Chromium keeps the existing sandboxed Boaz library in place when present and imports only missing preferences before restoring windows. It retains source data, refuses ambiguous duplicate libraries, and reports access failures. Cookie/password continuity and actual previous-store access still require upgrade acceptance; source implementation alone is not a pass.

Before marking the PR ready, exercise the actual signed app: HTTP/HTTPS navigation, tab creation/switch/close, same-profile restart/restoration, normal quit, WebKit fallback, and representative existing password, download, extension, permission and media behavior. Verify an essential upgrade without data loss. No development-only artifact substitutes for this pass.

Three-day dogfooding, exhaustive matrices, strict numerical performance/size gates and extended delta/rollback campaigns are deferred. Existing core features, security, data preservation, and a distributable Chromium-default application are not deferred.

## Automatic beta watcher

`Tools/release-watch.sh` retains the existing WebKit beta workflow. For Chromium revisions it stops before creating or pushing a tag: production candidates require explicit verified build/signing inputs and this PR does not enable automatic publication. The installed launchd watcher is a copied script; reinstall the updated watcher before enabling automatic processing of Chromium revisions. Logs remain in `~/Library/Application Support/BoazRelease`.
