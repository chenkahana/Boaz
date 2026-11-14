#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
case "${1:-appstore}" in
  appstore) spec=project-webkit.yml; configuration=webkit-appstore ;;
  dmg) spec=project-webkit-dmg.yml; configuration=webkit-dmg ;;
  *) echo "Usage: $0 [appstore|dmg]" >&2; exit 2 ;;
esac
output="$repo_root/build/$configuration"
mkdir -p "$output"
export BOAZ_REPO_ROOT="$repo_root"
export BOAZ_GENERATED_DIR="$output/Generated"
exec xcodegen generate --spec "$repo_root/$spec" --project "$output"
