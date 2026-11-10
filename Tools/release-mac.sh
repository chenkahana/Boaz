#!/bin/bash
# Builds the Mac app for download outside the App Store: signed with Developer ID, notarized and stapled, in a DMG.
#
#   Tools/release-mac.sh 1.2.0 [build-number]
#
# Signing uses the "Developer ID Application" certificate in the keychain and the Developer ID provisioning profile
# named by $PROFILE_NAME (default "Boaz Developer ID"). Notarization uses an App Store Connect API key
# ($NOTARY_KEY_PATH, $NOTARY_KEY_ID, $NOTARY_ISSUER_ID) or, locally, a notarytool keychain profile ($NOTARY_PROFILE).
# Output: build/release/Boaz.dmg and Boaz.dmg.sha256. See docs/release.md.
set -euo pipefail

VERSION=${1:?usage: Tools/release-mac.sh VERSION [BUILD]}
BUILD=${2:-$(date +%Y%m%d%H%M)}
TEAM_ID=DPF8459C2J
PROFILE_NAME=${PROFILE_NAME:-Boaz Developer ID}
OUT=build/release
ARCHIVE=$OUT/Boaz-macOS.xcarchive

cd "$(dirname "$0")/.."
rm -rf "$OUT" && mkdir -p "$OUT"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    notary_auth=(--keychain-profile "$NOTARY_PROFILE")
else
    notary_auth=(--key "${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH or NOTARY_PROFILE}" --key-id "${NOTARY_KEY_ID:?}"
                 --issuer "${NOTARY_ISSUER_ID:?}")
fi

echo "==> Archiving Boaz $VERSION ($BUILD)"
xcodegen generate --quiet
# A Developer ID profile carries the production push environment; the checked-in entitlements are for development.
cp Apps/macOS/Boaz.entitlements "$OUT/Boaz.entitlements"
plutil -replace com.apple.developer.aps-environment -string production "$OUT/Boaz.entitlements"
xcodebuild archive -project Boaz.xcodeproj -scheme Boaz-macOS -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -quiet \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_ENTITLEMENTS="$OUT/Boaz.entitlements"

echo "==> Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <key>provisioningProfiles</key>
    <dict><key>com.chenkahana.boaz</key><string>$PROFILE_NAME</string></dict>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet

echo "==> Making the DMG"
staging=$OUT/dmg
mkdir -p "$staging"
cp -R "$OUT/export/Boaz.app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Boaz" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$OUT/Boaz.dmg" -quiet
codesign --sign "Developer ID Application" --timestamp "$OUT/Boaz.dmg"

echo "==> Notarizing"
xcrun notarytool submit "$OUT/Boaz.dmg" "${notary_auth[@]}" --wait
xcrun stapler staple "$OUT/Boaz.dmg"

echo "==> Checking"
spctl --assess --type open --context context:primary-signature --verbose "$OUT/Boaz.dmg"
(cd "$OUT" && shasum -a 256 Boaz.dmg > Boaz.dmg.sha256 && cat Boaz.dmg.sha256)
