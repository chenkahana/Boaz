#!/bin/zsh
# Xcode Cloud: after an App Store archive, fill TestFlight's "What to Test" from the latest commits.
set -euo pipefail

if [[ -n "${CI_APP_STORE_SIGNED_APP_PATH:-}" ]]; then
  notes="$CI_PRIMARY_REPOSITORY_PATH/TestFlight"
  mkdir -p "$notes"
  git -C "$CI_PRIMARY_REPOSITORY_PATH" fetch --deepen 5 >/dev/null 2>&1 || true
  git -C "$CI_PRIMARY_REPOSITORY_PATH" log -5 --pretty=format:'- %s' > "$notes/WhatToTest.en-US.txt"
fi
