#!/bin/bash
# Prepare an unpublished production Chromium DMG. Each stage verifies its inputs
# and enters the existing SSD build guard; this wrapper never bypasses that guard.
set -euo pipefail
TOOLS=$(cd "$(dirname "$0")" && pwd -P)
PYTHON=/opt/homebrew/bin/python3.12
usage() {
    cat <<'HELP'
Usage: Tools/release-mac.sh VERSION --base-app PATH --ui-receipt PATH \
  --output PATH --identity 'Developer ID Application: ...' \
  --notary-profile NAME --provisioning-profile PATH --sparkle-bin PATH [--build NUMBER] [--no-publish]

Default: assemble verified native/UI builds as production Boaz, sign and notarize,
then package Boaz.dmg and a candidate appcast. Nothing is published.
--output must be a new canonical directory under /Volumes/BoazBuild/cef/direct/artifacts.
--base-app and --ui-receipt must be completed artifacts accepted by the assembly verifier.
Build the UI beforehand with Tools/chromium/build-application.py --build.

Explicit WebKit rollback path:
  Tools/release-mac.sh VERSION --webkit [--no-publish]
This wrapper also keeps WebKit artifacts unpublished.
HELP
}
if [ "$#" -eq 0 ]; then usage >&2; exit 2; fi
if [ "$1" = --help ] || [ "$1" = -h ]; then usage; exit 0; fi
VERSION=$1
shift
BASE_APP= UI_RECEIPT= OUTPUT= IDENTITY= NOTARY_PROFILE= PROVISIONING_PROFILE= SPARKLE_BIN=
BUILD=$(date -u +%Y%m%d%H%M)
WEBKIT=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --webkit) WEBKIT=true; shift ;;
        --no-publish) shift ;;
        --base-app|--ui-receipt|--output|--identity|--notary-profile|--provisioning-profile|--sparkle-bin|--build)
            [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "Missing value for $1" >&2; exit 2; }
            case "$1" in
                --base-app) BASE_APP=$2 ;; --ui-receipt) UI_RECEIPT=$2 ;;
                --output) OUTPUT=$2 ;; --identity) IDENTITY=$2 ;;
                --notary-profile) NOTARY_PROFILE=$2 ;; --provisioning-profile) PROVISIONING_PROFILE=$2 ;; --sparkle-bin) SPARKLE_BIN=$2 ;;
                --build) BUILD=$2 ;;
            esac
            shift 2 ;;
        *) echo "Unknown release argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done
if "$WEBKIT"; then
    [ -z "$BASE_APP$UI_RECEIPT$OUTPUT$IDENTITY$NOTARY_PROFILE$PROVISIONING_PROFILE$SPARKLE_BIN" ] || {
        echo "Chromium options cannot be combined with --webkit." >&2; exit 2; }
    exec "$TOOLS/release-webkit-mac.sh" "$VERSION" --no-publish
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "VERSION must contain two or three numeric components." >&2; exit 2; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "BUILD must be numeric." >&2; exit 2; }
for name in BASE_APP UI_RECEIPT OUTPUT IDENTITY NOTARY_PROFILE PROVISIONING_PROFILE SPARKLE_BIN; do
    [ -n "${!name}" ] || { echo "Missing required Chromium release input: $name" >&2; usage >&2; exit 2; }
done
[ -x "$PYTHON" ] || { echo "Required Python is unavailable: $PYTHON" >&2; exit 1; }
case "$OUTPUT" in
    /Volumes/BoazBuild/cef/direct/artifacts/*) ;;
    *) echo "Release output must be under /Volumes/BoazBuild/cef/direct/artifacts." >&2; exit 2 ;;
esac
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || { echo "Refusing to reuse release output." >&2; exit 1; }
"$PYTHON" "$TOOLS/chromium/stage-application.py" \
    --base-app "$BASE_APP" --ui-receipt "$UI_RECEIPT" \
    --output "$OUTPUT/assembly/Boaz.app" --native-launch \
    --production-version "$VERSION" --production-build "$BUILD"
"$PYTHON" "$TOOLS/chromium/sign-production-application.py" \
    --input "$OUTPUT/assembly" --output "$OUTPUT/signing" \
    --identity "$IDENTITY" --notary-profile "$NOTARY_PROFILE" --provisioning-profile "$PROVISIONING_PROFILE"
"$PYTHON" "$TOOLS/chromium/package-candidate.py" "$VERSION" \
    --chromium-app "$OUTPUT/signing/signed/stable/Boaz.app" \
    --output "$OUTPUT/package" --sparkle-bin "$SPARKLE_BIN" --no-publish
echo "Production Chromium candidate prepared: $OUTPUT/package/Boaz.dmg"
echo "Nothing published; receipts and signing/notarization evidence remain under $OUTPUT."
