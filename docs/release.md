# Releasing the Mac app outside the App Store

Besides the App Store (see [app-store.md](app-store.md)), each release puts a notarized `Boaz.dmg` on
[GitHub Releases](https://github.com/chenkahana/Boaz/releases). The README's **Download for Mac** button links to
`releases/latest/download/Boaz.dmg`, so it always points at the newest release.

Pushing a tag `vX.Y.Z` runs [`.github/workflows/release.yml`](../.github/workflows/release.yml). It waits for a
maintainer to approve the run, then:

1. Builds the Mac app (Release) with version `X.Y.Z`, and uses the workflow's run number as the build number.
2. Signs it with Developer ID, puts it in a DMG, and has Apple notarize it.
3. Publishes a GitHub release with `Boaz.dmg`, `Boaz.dmg.sha256` and the version's section of `CHANGELOG.md` as the
   notes.

The same steps run locally with `make dmg VERSION=X.Y.Z` (script: [`Tools/release-mac.sh`](../Tools/release-mac.sh)).

## One-time setup

The Account Holder of team `DPF8459C2J` does this once.

1. **Developer ID certificate.** Go to developer.apple.com › Certificates › **+** › Developer ID Application, then
   install it in your keychain. To get the `.p12`, open Keychain Access › My Certificates, select it, choose Export
   and set a password.
2. **Developer ID provisioning profile.** Go to Profiles › **+** › Developer ID, choose App ID `com.chenkahana.boaz`
   and the certificate from step 1, and name the profile exactly `Boaz Developer ID`. The App ID already has iCloud
   (CloudKit) and Push Notifications, which the profile needs for sync. Download the profile.
3. **Notary API key.** Go to App Store Connect › Users and Access › Integrations › App Store Connect API › **+** and
   give the key the Developer role. Download the `.p8` (you can download it only once), and note the Key ID and
   Issuer ID.
4. **GitHub environment.** Go to the repo's Settings › Environments › New environment, name it `release`, and add
   yourself as a required reviewer. Then add these environment secrets:

   | Secret | Value |
   |---|---|
   | `MACOS_CERTIFICATE_P12` | `base64 -i DeveloperID.p12 \| pbcopy` |
   | `MACOS_CERTIFICATE_PASSWORD` | the `.p12` password |
   | `MACOS_PROVISIONING_PROFILE` | `base64 -i Boaz_Developer_ID.provisionprofile \| pbcopy` |
   | `NOTARY_API_KEY` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
   | `NOTARY_API_KEY_ID` | the Key ID |
   | `NOTARY_API_ISSUER_ID` | the Issuer ID |

5. **Protect release tags.** Go to Settings › Rules › Rulesets › New tag ruleset, target `v*`, and restrict creation,
   update and deletion to admins. That way only a maintainer can start a release, on top of the approval in step 4.

To build locally, keep the certificate and profile installed, and store the notary key once:
`xcrun notarytool store-credentials boaz-notary --key AuthKey_XXXX.p8 --key-id … --issuer …`. Then run
`NOTARY_PROFILE=boaz-notary make dmg VERSION=X.Y.Z`.

## Each release

1. Move the `[Unreleased]` notes in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`, update the links at the bottom,
   and merge.
2. Tag the merge commit and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. Approve the **Release** run under Actions. It takes about 15 minutes, most of it notarization.
4. Check the release page. Open the DMG on a Mac that hasn't run Boaz before: Gatekeeper should open it without a
   warning.

The App Store build for the same version is separate: `make archive`, then upload it (app-store.md).

## Notes

- The DMG build and the App Store build share the bundle ID, the iCloud container and the library. Install one
  copy at a time in `/Applications`.
- Sync works in the DMG build because the Developer ID profile includes iCloud, and it uses the production CloudKit
  environment. Deploy schema changes to Production before releasing (app-store.md, step 1).
- The DMG build doesn't update itself. People get new versions from the Releases page.
