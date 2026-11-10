#!/bin/zsh
# Xcode Cloud: Boaz.xcodeproj isn't checked in, so generate it from project.yml after the clone.
set -euo pipefail
cd "$CI_PRIMARY_REPOSITORY_PATH"

# The same pinned XcodeGen release as GitHub CI, checked against its SHA-256.
VERSION=2.46.0
SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
TOOLS="${TMPDIR:-/tmp}/xcodegen-$VERSION"
mkdir -p "$TOOLS"
curl -fsSL -o "$TOOLS/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
echo "$SHA256  $TOOLS/xcodegen.zip" | shasum -a 256 -c -
unzip -qo "$TOOLS/xcodegen.zip" -d "$TOOLS"

# Every Xcode Cloud build gets its own build number, so archives can always be uploaded.
if [[ -n "${CI_BUILD_NUMBER:-}" ]]; then
  sed -i '' -E "s/^(    CURRENT_PROJECT_VERSION:).*/\1 \"$CI_BUILD_NUMBER\"/" project.yml
fi

"$TOOLS/xcodegen/bin/xcodegen" generate --quiet

# Xcode Cloud never resolves packages on its own: hand it BoazKit's pinned versions.
SWIFTPM=Boaz.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$SWIFTPM"
cp Packages/BoazKit/Package.resolved "$SWIFTPM/Package.resolved"
