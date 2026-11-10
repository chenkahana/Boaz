#!/bin/bash
# Releases the Mac app outside the App Store: signs it with Developer ID, has Apple notarize it, and publishes Boaz.dmg
# on the GitHub release for tag vVERSION. Signing and notarization go through the Apple account signed in to Xcode
# (Settings › Accounts), so no certificates or keys are kept anywhere else. See docs/release.md.
#
#   Tools/release-mac.sh 0.2.0 [--no-publish]
set -euo pipefail

VERSION=${1:?usage: Tools/release-mac.sh VERSION [--no-publish]}
PUBLISH=${2:-}
TAG=v$VERSION
TEAM_ID=DPF8459C2J
OUT=build/release
ARCHIVE=$OUT/Boaz-macOS.xcarchive

cd "$(dirname "$0")/.."
if [ "$PUBLISH" != "--no-publish" ]; then
    git fetch -q origin tag "$TAG" 2>/dev/null || { echo "Tag $TAG isn't on GitHub yet: tag the release commit first."; exit 1; }
    # Not checked out here: bash reads this script as it runs, so it can't change underneath itself.
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "$TAG^{commit}")" ] || { echo "Check out $TAG first."; exit 1; }
fi
rm -rf "$OUT" && mkdir -p "$OUT"

echo "==> Archiving Boaz $VERSION"
xcodegen generate --quiet
xcodebuild archive -project Boaz.xcodeproj -scheme Boaz-macOS -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)"

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
until xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/export" -quiet 2>/dev/null; do
    sleep 30
done
APP=$OUT/export/Boaz.app
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"

echo "==> Making the DMG"
mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname Boaz -srcfolder "$OUT/dmg" -fs HFS+ -format UDZO -ov "$OUT/Boaz.dmg" -quiet
(cd "$OUT" && shasum -a 256 Boaz.dmg > Boaz.dmg.sha256 && cat Boaz.dmg.sha256)

[ "$PUBLISH" = "--no-publish" ] && exit 0

echo "==> Publishing $TAG"
title="Boaz $VERSION"
# 0.x versions are betas. Not marked as pre-releases, which "latest" (the README button) would skip.
if [[ $VERSION == 0.* ]]; then title="$title (beta)"; fi
awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {on=1; next} on && /^## \[/ {exit} on' CHANGELOG.md > "$OUT/notes.md"
printf '\n---\nOpen the DMG and drag Boaz to Applications. Requires macOS 26. Signed with Developer ID and notarized by Apple.\n' \
    >> "$OUT/notes.md"
gh release create "$TAG" "$OUT/Boaz.dmg" "$OUT/Boaz.dmg.sha256" --title "$title" --notes-file "$OUT/notes.md" --verify-tag
