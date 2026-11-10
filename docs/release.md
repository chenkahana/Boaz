# Releasing the Mac app outside the App Store

Besides the App Store (see [app-store.md](app-store.md)), each release puts a notarized `Boaz.dmg` on
[GitHub Releases](https://github.com/chenkahana/Boaz/releases). The README's **Download for Mac** button links to
`releases/latest/download/Boaz.dmg`, so it always points at the newest release.

A release is built on a maintainer's Mac with `make dmg VERSION=X.Y.Z` ([`Tools/release-mac.sh`](../Tools/release-mac.sh)).
Signing with Developer ID and notarization go through the Apple account signed in to Xcode, so the repo and its CI
hold no certificates or keys.

## Before the first release on a Mac

- Xcode › Settings › Accounts is signed in to an account with the Account Holder or Admin role on team `DPF8459C2J`.
  The first export creates the team's Developer ID certificate in the cloud.
- `xcodegen` and the GitHub CLI (`gh auth login`, with write access to the repo) are installed.

## Each release

1. Move the `[Unreleased]` notes in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`, update the links at the bottom,
   and merge.
2. Tag the merge commit and push: `git tag -a vX.Y.Z -m "Boaz X.Y.Z" && git push origin vX.Y.Z`.
3. Check out the tag (`git checkout vX.Y.Z`) and run `make dmg VERSION=X.Y.Z`. It archives the Mac app, signs it
   with Developer ID, waits for Apple's notarization (a few minutes), builds `Boaz.dmg`, and publishes the GitHub
   release with the changelog section as its notes. 0.x versions are titled "(beta)".

To build the DMG without publishing it, run `Tools/release-mac.sh X.Y.Z --no-publish`. The DMG goes to
`build/release/`.

## Notes

- The DMG build and the App Store build share the bundle ID, the iCloud container and the library. Install one
  copy at a time in `/Applications`.
- The DMG build uses the production CloudKit environment, as the App Store build does. Deploy schema changes to
  Production before releasing (app-store.md, step 1).
- The app inside the DMG is signed, notarized and stapled. The DMG itself isn't signed (Xcode keeps the Developer ID
  key in the cloud), which Gatekeeper doesn't require.
- The DMG build doesn't update itself. People get new versions from the Releases page.
