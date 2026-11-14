#!/bin/bash
# Publishes a beta for each new commit on master: the next patch version after the newest tag, tagged on that commit
# and released by release-mac.sh. Signing, notarization and the Sparkle key live in a maintainer's keychain, so this
# runs on that Mac, from launchd, every 5 minutes (launchd never starts it again while a release is still running).
# Commits that land together between two checks ship as one release. See docs/release.md.
#
#   Tools/release-watch.sh --install   copy this script out of the repo and start the launchd job
#   Tools/release-watch.sh REPO        release REPO's origin/master unless it's tagged already (what launchd runs)
set -euo pipefail

STATE=$HOME/Library/Application\ Support/BoazRelease
LABEL=com.chenkahana.boaz.release-watch
WORKTREE=$HOME/.worktrees/Boaz/release

notify() { osascript -e "display notification \"$1\" with title \"Boaz release\"" || true; }

install() {
    local repo plist=$HOME/Library/LaunchAgents/$LABEL.plist
    repo=$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)
    mkdir -p "$STATE"
    cp "$0" "$STATE/release-watch.sh"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$STATE/release-watch.sh</string><string>$repo</string></array>
    <key>StartInterval</key><integer>300</integer>
    <key>RunAtLoad</key><true/>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
    <key>StandardOutPath</key><string>$STATE/watch.log</string>
    <key>StandardErrorPath</key><string>$STATE/watch.log</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "Watching $repo's master. Logs: $STATE"
}

release() {
    local repo=$1 head last version major minor patch
    git -C "$repo" fetch -q --tags origin master
    head=$(git -C "$repo" rev-parse origin/master)
    git -C "$repo" tag --points-at "$head" | grep -q '^v' && return
    # A commit whose release failed waits for the next one (or a manual release), instead of retrying every 5 minutes.
    [ "$(cat "$STATE/failed" 2>/dev/null)" = "$head" ] && return
    last=$(git -C "$repo" tag --list 'v*' --sort=-v:refname | head -1)
    IFS=. read -r major minor patch <<< "${last#v}"
    version=$major.$minor.$((patch + 1))

    [ -d "$WORKTREE" ] || git -C "$repo" worktree add -q --detach "$WORKTREE" "$head"
    git -C "$WORKTREE" checkout -q --detach "$head"
    if git -C "$WORKTREE" cat-file -e "$head:Tools/chromium/package-candidate.py" 2>/dev/null; then
        echo "Chromium releases require verified candidate preparation; automatic publication is unavailable."
        echo "$head" > "$STATE/failed"
        return 1
    fi
    git -C "$WORKTREE" tag -a "v$version" -m "Boaz $version" "$head"
    git -C "$WORKTREE" push -q origin "v$version"
    echo "$(date '+%F %T') releasing $version from $head"
    if "$WORKTREE/Tools/release-mac.sh" "$version" > "$STATE/v$version.log" 2>&1; then
        notify "Boaz $version (beta) is out."
    else
        # The tag goes too, so the next release takes this version number.
        git -C "$WORKTREE" push -q origin ":refs/tags/v$version" || true
        git -C "$WORKTREE" tag -d "v$version" > /dev/null
        echo "$head" > "$STATE/failed"
        notify "Boaz $version failed: see $STATE/v$version.log"
        return 1
    fi
}

if [ "${1:-}" = --install ]; then install; else release "${1:?usage: Tools/release-watch.sh --install | REPO}"; fi
