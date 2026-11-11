# Releasing the Mac app outside the App Store

Besides the App Store (see [app-store.md](app-store.md)), each release puts a notarized `Boaz.dmg` on
[GitHub Releases](https://github.com/chenkahana/Boaz/releases). The README's **Download for Mac** button links to
`releases/latest/download/Boaz.dmg`, so it always points at the newest release.

A release is built on a maintainer's Mac with `make dmg VERSION=X.Y.Z` ([`Tools/release-mac.sh`](../Tools/release-mac.sh)).
Signing with Developer ID and notarization go through the Apple account signed in to Xcode, and the update signing
key stays in that Mac's login keychain, so the repo and its CI hold no certificates or keys.

## Updates

The DMG build updates itself with [Sparkle 2](https://sparkle-project.org). Once a day, and from Boaz › Check for
Updates…, it reads `appcast.xml` from the newest GitHub release
(`releases/latest/download/appcast.xml`), and installs a newer DMG whose EdDSA signature matches the public key it
carries (`SUPublicEDKey`). The app is sandboxed, so Sparkle's installer runs through its XPC launcher
(`SUEnableInstallerLauncherService`, with the mach-lookup exceptions `<bundle ID>-spks` and `-spki`).

Sparkle is only in the DMG build. [`project-dmg.yml`](../project-dmg.yml) is `project.yml` plus the Sparkle package,
those Info.plist keys and entitlements (generated under `build/dmg/`) and the `SPARKLE` compilation condition that
compiles [`Updates.swift`](../Apps/macOS/Updates/Updates.swift). The App Store build and CI generate from
`project.yml` alone, so they never resolve, link or contain Sparkle, and Xcode Cloud keeps BoazKit's pinned packages.
To build the DMG variant locally: `make mac-dmg`.

Boaz 0.1.0 predates Sparkle, so people on 0.1.0 download 0.2.0 from the Releases page once; from 0.2.0 on, updates
arrive in the app.

## Before the first release on a Mac

- Xcode › Settings › Accounts is signed in to an account with the Account Holder or Admin role on team `DPF8459C2J`.
  The first export creates the team's Developer ID certificate in the cloud.
- `xcodegen` and the GitHub CLI (`gh auth login`, with write access to the repo) are installed.
- Sparkle's EdDSA key is in the login keychain, and its public half is in `project-dmg.yml`. This is done once, on the
  first release with Sparkle (0.2.0), and again only on a new Mac:
  1. Run `make mac-dmg` once, so the Sparkle package (and its tools) is downloaded.
  2. Run `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`. It creates the key in the
     login keychain (or finds the one already there) and prints the public key.
  3. Replace `SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER` in `project-dmg.yml` with that public key, and merge it.

  On another Mac, move the key with `generate_keys -x <file>` and `generate_keys -f <file>` instead of making a new
  one: copies already installed only accept updates signed with the key they carry. Never commit the private key.
  `release-mac.sh` stops if the public key in the app isn't the one in the keychain.

## Each release

1. Move the `[Unreleased]` notes in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`, update the links at the bottom,
   and merge.
2. Tag the merge commit and push: `git tag -a vX.Y.Z -m "Boaz X.Y.Z" && git push origin vX.Y.Z`.
3. Check out the tag (`git checkout vX.Y.Z`) and run `make dmg VERSION=X.Y.Z`. It archives the Mac app with Sparkle,
   signs it with Developer ID, waits for Apple's notarization (a few minutes), builds `Boaz.dmg`, signs it with the
   Sparkle key (`sign_update`, which may ask for keychain access), writes `appcast.xml`, and publishes the GitHub
   release with the DMG, its checksum and the appcast, and the changelog section as its notes. 0.x versions are
   titled "(beta)". Installed copies see the update on their next daily check.

To build the DMG without publishing it, run `Tools/release-mac.sh X.Y.Z --no-publish`. The DMG and appcast go to
`build/release/`.

## Notes

- The DMG build and the App Store build share the bundle ID, the iCloud container and the library. Install one
  copy at a time in `/Applications`.
- The DMG build uses the production CloudKit environment, as the App Store build does. Deploy schema changes to
  Production before releasing (app-store.md, step 1).
- The app inside the DMG is signed, notarized and stapled. The DMG itself isn't code-signed (Xcode keeps the Developer
  ID key in the cloud), which Gatekeeper doesn't require; Sparkle checks its EdDSA signature instead.
- Sparkle compares build numbers (`CFBundleVersion`), which the script sets to the release time, so each release is
  newer than the last.
