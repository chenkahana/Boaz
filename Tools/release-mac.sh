#!/bin/bash
# Releases the Mac app outside the App Store: signs it with Developer ID, has Apple notarize it, and publishes Boaz.dmg
# on the GitHub release for tag vVERSION, with the appcast.xml that Sparkle in installed copies reads to update them.
# Signing and notarization go through the Apple account signed in to Xcode (Settings › Accounts), and Sparkle's EdDSA
# key stays in this Mac's login keychain, so no certificates or keys are kept anywhere else. See docs/release.md.
#
#   Tools/release-mac.sh 0.2.0 [--no-publish]
set -euo pipefail

VERSION=${1:?usage: Tools/release-mac.sh VERSION [--no-publish]}
for argument in "$@"; do
    if [ "$argument" = "--chromium-app" ]; then
        exec /opt/homebrew/bin/python3.12 "$(dirname "$0")/chromium/package-candidate.py" "$@"
    fi
done
PUBLISH=${2:-}
TAG=v$VERSION
TEAM_ID=DPF8459C2J
BUILD=$(date +%Y%m%d%H%M)

cd "$(dirname "$0")/.."
# Before an archive that would only fail at the key check.
! grep -q SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER project-dmg.yml || {
    echo "project-dmg.yml still has the placeholder SUPublicEDKey: paste the Sparkle public key first (docs/release.md)."; exit 1; }
if [ "$PUBLISH" != "--no-publish" ]; then
    git fetch -q origin tag "$TAG" 2>/dev/null || { echo "Tag $TAG isn't on GitHub yet: tag the release commit first."; exit 1; }
    # Not checked out here: bash reads this script as it runs, so it can't change underneath itself.
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "$TAG^{commit}")" ] || { echo "Check out $TAG first."; exit 1; }
fi
# Each invocation retains its artifacts, including failed signing or notarization runs.
[ ! -L build ] && [ ! -L build/release ] || {
    echo "Release output directories must not be symbolic links."; exit 1; }
mkdir -p build/release
OUT=$(mktemp -d "$(pwd -P)/build/release/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
ARCHIVE=$OUT/Boaz-macOS.xcarchive
# Where this archive resolves Sparkle's signing tools.
PACKAGES=$OUT/SourcePackages
SPARKLE_BIN=$PACKAGES/artifacts/sparkle/Sparkle/bin
echo "==> Release artifacts: $OUT"

echo "==> Archiving Boaz $VERSION"
# The DMG build: project.yml plus Sparkle (project-dmg.yml). The App Store build never contains Sparkle.
xcodegen generate --quiet --spec project-dmg.yml
# Back to the App Store project however this ends, so a later `make mac` or Xcode build doesn't pick up Sparkle.
trap 'xcodegen generate --quiet' EXIT
# Seeded with BoazKit's pins, so Xcode records Sparkle's here and not in BoazKit's Package.resolved.
mkdir -p Boaz.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Packages/BoazKit/Package.resolved Boaz.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/
xcodebuild archive -project Boaz.xcodeproj -scheme Boaz-macOS -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet \
    -clonedSourcePackagesDirPath "$PACKAGES" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD"

# An update installs only on copies that carry the public half of the key it was signed with.
KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$ARCHIVE/Products/Applications/Boaz.app/Contents/Info.plist")
[ "$KEY" = "$("$SPARKLE_BIN/generate_keys" -p)" ] || {
    echo "SUPublicEDKey in project-dmg.yml isn't the public half of this Mac's Sparkle key (docs/release.md)."; exit 1; }

echo "==> Signing with Developer ID and sending to Apple for notarization"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>upload</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/upload" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet

echo "==> Waiting for notarization"
# Usually minutes; give up after an hour and show why the last attempt failed.
for attempt in $(seq 120); do
    xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/export" -quiet 2> "$OUT/notarize.log" && break
    # Apple turning the app down won't change by waiting.
    grep -qiE "invalid|rejected" "$OUT/notarize.log" && { echo "Notarization failed:"; tail -20 "$OUT/notarize.log"; exit 1; }
    [ "$attempt" = 120 ] && { echo "Notarization didn't finish within an hour:"; tail -20 "$OUT/notarize.log"; exit 1; }
    sleep 30
done
APP=$OUT/export/Boaz.app
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"

echo "==> Making the DMG"
mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname Boaz -srcfolder "$OUT/dmg" -fs HFS+ -format UDZO "$OUT/Boaz.dmg" -quiet
(cd "$OUT" && shasum -a 256 Boaz.dmg > Boaz.dmg.sha256 && cat Boaz.dmg.sha256)

echo "==> Signing the DMG for Sparkle and writing the appcast"
# sign_update reads the EdDSA private key from the login keychain and prints only the signature.
SIGNATURE=$("$SPARKLE_BIN/sign_update" -p "$OUT/Boaz.dmg")
cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Boaz</title>
        <item>
            <title>Boaz $VERSION</title>
            <pubDate>$(LC_ALL=C date -R)</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>https://github.com/chenkahana/Boaz/releases/tag/$TAG</sparkle:releaseNotesLink>
            <enclosure url="https://github.com/chenkahana/Boaz/releases/download/$TAG/Boaz.dmg"
                       length="$(stat -f%z "$OUT/Boaz.dmg")" type="application/octet-stream"
                       sparkle:edSignature="$SIGNATURE"/>
        </item>
    </channel>
</rss>
EOF

[ "$PUBLISH" = "--no-publish" ] && exit 0

echo "==> Publishing $TAG"
title="Boaz $VERSION"
# 0.x versions are betas. Not marked as pre-releases, which "latest" (the README button) would skip.
if [[ $VERSION == 0.* ]]; then title="$title (beta)"; fi
awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {on=1; next} on && /^## \[/ {exit} on' CHANGELOG.md > "$OUT/notes.md"
printf '\n---\nOpen the DMG and drag Boaz to Applications. Requires macOS 26. Signed with Developer ID and notarized by Apple.\n' \
    >> "$OUT/notes.md"
# Installed copies read the newest release's appcast: releases/latest/download/appcast.xml (SUFeedURL).
gh release create "$TAG" "$OUT/Boaz.dmg" "$OUT/Boaz.dmg.sha256" "$OUT/appcast.xml" --title "$title" \
    --notes-file "$OUT/notes.md" --verify-tag
