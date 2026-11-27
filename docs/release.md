# Preparing the GitHub Mac DMG

The default release path is Chromium with Boaz's native interface and in-app WebKit fallback. iOS still uses WebKit; the Mac App Store app was retired on 2026-11-27, so the DMG is the only Mac product. PR #70 remains draft until essential production-distribution and existing-feature acceptance passes.

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
signs it with the team's Developer ID certificate through `release-mac.sh` (the non-cloud path), notarizes it with
`notarytool` and the API key, packages the DMG, and creates `vX.Y.Z` with `Boaz.dmg`, its checksum and the
`appcast.xml` that installed copies read from `releases/latest`. Nothing runs on the build Mac except refreshing
the Chromium base.

**Version.** CHANGELOG's newest `## [X.Y.Z]` when it is newer than every `v*` tag, with that section as the notes.
Otherwise the next patch after the newest tag, with the commit subject as the notes; CI doesn't edit CHANGELOG.md.
Run the workflow by hand with `dry_run` (the default) to build, sign and notarize without publishing; the DMG is
kept as a workflow artifact for three days.

**Soak for risky changes.** Five releases shipped on 19 Nov, and Sparkle takes DMG users straight to the latest.
That pace is fine for polish. A commit that touches the engine (`Tools/chromium`, `Apps/macOS/Engine`), sync
(`Packages/BoazKit/Sources/BoazKit/Sync`, CloudKit) or migrations (`BoazStore`) is a risky release and waits for a
soak before the next risky one ships:

1. Release it as usual, but do not merge another engine, sync or migration change until it has run on your own
   Mac and iPhone for a full day, with the Mac updated through Sparkle rather than a fresh install.
2. In that day, check the three things that fail quietly: tabs, spaces and sign-ins survive the update; two devices
   still converge through sync; on the iPhone, Settings ▸ About, "WebKit internals",
   reads "No problems seen".
3. If anything is off, fix forward in the next release and say so in its notes; do not stack more changes on it.

Polish-only commits (copy, spacing, icons, docs) skip the soak. Security updates skip it too (decided 2026-11-27):
they ship as soon as CI and the acceptance harness pass. If you want a real beta channel later, serve a second
appcast from a prerelease and point a few installs at it; that needs a separate feed URL in the app, so it is not
set up here.

**Crash review (release gate: no new crash cluster).** Boaz has no analytics and no crash SDK, so crashes reach
the maintainer only through Apple's opt-in sharing and through reports users attach themselves. Before cutting a
release, review the one that is out:

- **App Store builds** (iPhone): App Store Connect › the app › TestFlight › Crashes, and Xcode ›
  Window › Organizer › Crashes for the current versions. See [the App Store steps](app-store.md#crash-review).
- **DMG:** nothing arrives on its own. Chromium's crash reporter keeps its minidumps on the user's Mac and has no
  upload address in Boaz's build. Look through the GitHub issues opened since the last release for attached crash
  reports (Help › Report a Problem… links users to [SUPPORT.md](../SUPPORT.md#sending-a-crash-report)). Symbolicate
  each one with the dSYMs of the release it names, which the workflow attaches to the GitHub release as
  `Boaz-X.Y.Z-dSYMs.zip`:

  ```sh
  gh release download vX.Y.Z --pattern 'Boaz-*-dSYMs.zip' --dir /tmp/dsyms && ditto -x -k /tmp/dsyms/*.zip /tmp/dsyms
  Tools/symbolicate Chromium-2026-11-26-101500.ips /tmp/dsyms
  ```

A **crash cluster** is two or more reports whose crashed thread stops in the same Boaz function, or any one crash at
launch. The gate: the release being cut ships only if the current release has no cluster that is new since the
previous release or growing; when one exists, its fix is the only thing that ships next. Write the result in the
release notes ("Crash review: none new", or "Crash review: fixes #N"), so a skipped review is visible.

**Secrets** (Settings › Secrets and variables › Actions):

- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`: an App Store Connect team API key with the **Admin** role, which
  creating provisioning profiles requires. Create it in App Store Connect › Users and Access › Integrations ›
  App Store Connect API › Team Keys; `ASC_KEY_P8` is the downloaded `.p8` file's text.
- `SPARKLE_ED_PRIVATE_KEY`: the file written by `generate_keys -x sparkle.key` (in the Sparkle `bin` directory of a
  UI build run, `/Volumes/BoazBuild/cef/direct/app/runs/RUN/SourcePackages/artifacts/sparkle/Sparkle/bin`) on the
  Mac whose login keychain holds the key. It must be the key behind `SUPublicEDKey`; packaging checks.
- `DEVELOPER_ID_KEY`: the unencrypted PEM private key (`-----BEGIN PRIVATE KEY-----`) of the Developer ID
  Application certificate whose App Store Connect ID is `DEVELOPER_ID_CERT_ID` in the workflow.

The workflow stops with the list of missing secrets before building. `Tools/chromium/ci-signing.py install` fetches
that certificate with the API key, checks it matches the key, and imports both into the run's keychain. It also
creates a Developer ID provisioning profile for `com.chenkahana.boaz` (iCloud and push), named
"Boaz release workflow RUN"; the last step deletes it, even after a failure, and the next run deletes any left
behind. Cloud-managed Developer ID signing doesn't work with an API key, so CI doesn't use `--cloud-signing`. When
the certificate is replaced, put the new key in `DEVELOPER_ID_KEY` and its ID in the workflow.

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
python3 Tools/chromium/chromium-base.py pack --upload   # checks the build matches the checkout, then publishes the prerelease
```

and re-run the failed workflow. `Tools/chromium/chromium-base.py key` prints the tag a checkout needs. A
prerelease never becomes `releases/latest`, so Sparkle's feed keeps pointing at the app.

## WebKit preservation

`make mac-webkit-dmg` builds the separate unsigned WebKit configuration. `Tools/release-mac.sh X.Y.Z --webkit --no-publish` preserves the previous Xcode archive/export/notarization workflow as an explicit rollback path. It does not silently replace a failed Chromium build. The App Store build (iPhone) continues to use `project.yml`.

## Upgrade and practical acceptance

Production Chromium keeps the existing sandboxed Boaz library in place when present and imports only missing preferences before restoring windows. It retains source data, refuses ambiguous duplicate libraries, and reports access failures. Cookie/password continuity and actual previous-store access still require upgrade acceptance; source implementation alone is not a pass.

Before marking the PR ready, exercise the actual signed app: HTTP/HTTPS navigation, tab creation/switch/close, same-profile restart/restoration, normal quit, WebKit fallback, and representative existing password, download, extension, permission and media behavior. Verify an essential upgrade without data loss. No development-only artifact substitutes for this pass.

Three-day dogfooding, exhaustive matrices, strict numerical performance/size gates and extended delta/rollback campaigns are deferred. Existing core features, security, data preservation, and a distributable Chromium-default application are not deferred.

## Automatic beta watcher

`Tools/release-watch.sh` retains the existing WebKit beta workflow. For Chromium revisions it stops before creating or pushing a tag: production candidates require explicit verified build/signing inputs and this PR does not enable automatic publication. The installed launchd watcher is a copied script; reinstall the updated watcher before enabling automatic processing of Chromium revisions. Logs remain in `~/Library/Application Support/BoazRelease`.
