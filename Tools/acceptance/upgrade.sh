#!/bin/bash
# Upgrade acceptance (must-have #13): installs a published Boaz DMG, gives it a library, settings and a sign-in,
# replaces it with a newer DMG and checks that all of it survived. Run only on a throwaway Mac (a CI runner):
# it replaces /Applications/Boaz.app and the current user's Boaz data. With a third DMG, it then upgrades once more,
# as someone who had already upgraded to the second one.
#
#   Tools/acceptance/upgrade.sh <from.dmg> <to.dmg> <output dir> [<then.dmg>]
set -uo pipefail

FROM_DMG=$1 TO_DMG=$2 OUT=$3 THEN_DMG=${4:-}
HERE=$(cd "$(dirname "$0")" && pwd)
ID=com.chenkahana.boaz
APP=/Applications/Boaz.app
CONTAINER=$HOME/Library/Containers/$ID/Data
OLD_DB="$CONTAINER/Library/Application Support/Boaz/boaz.sqlite"
# Preferences by path, without .plist: "defaults read com.chenkahana.boaz" reads the old container's while it exists.
OLD_PREFS=$CONTAINER/Library/Preferences/$ID
NEW_PREFS=$HOME/Library/Preferences/$ID
PORT=8765 SITE=http://127.0.0.1:8765
SESSION=s$(uuidgen | tr -d -) PLAIN=p$(uuidgen | tr -d -) COLD=c$(uuidgen | tr -d -)
mkdir -p "$OUT"
RESULTS=$OUT/results.md FAILED=0
: > "$RESULTS"

note() { echo "$*"; echo "- $*" >> "$RESULTS"; }
pass() { note "PASS $*"; }
fail() { note "FAIL $*"; FAILED=1; }
shot() { screencapture -x "$OUT/$1.png" 2>/dev/null || true; }
running() { pgrep -f "$APP/Contents/MacOS/" > /dev/null; }
# Waits up to $1 seconds for the command after it to succeed.
wait_for() {
    local limit=$1; shift
    for _ in $(seq "$limit"); do "$@" && return 0; sleep 1; done
    return 1
}
requested() { grep -q "\"path\": \"$1\"" "$OUT/requests.jsonl" 2>/dev/null; }
# The last request for path $1 carried the fixture's session cookie.
# A page load, told apart by its Fetch Metadata: Boaz's icon fetch (URLSession) requests the page too, without cookies.
page_loads() { grep "\"path\": \"$1\"" "$OUT/requests.jsonl" | grep '"mode": "navigate"' | grep '"dest": "document"'; }
signed_in() { page_loads "$1" | tail -1 | grep -q "boaz_session=$SESSION"; }
# The same, for the sign-in v0.2.18 kept in WebKit's default store (#188).
cold_signed_in() { page_loads "$1" | tail -1 | grep -q "boaz_cold=$COLD"; }
# The installed Boaz is 0.5.0 or later (a candidate is staged as 0.5.0), which fixes #188 and #191; before that
# they are known gaps.
fixed_in_050() { [ "$(printf '%s\n' 0.5.0 "$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)" | sort -V | head -1)" = 0.5.0 ]; }
check_cold() {
    if cold_signed_in "$1"; then pass "$2: the link-launched sign-in came back (#188)"
    elif fixed_in_050; then fail "$2: the link-launched sign-in is gone (#188)"
    else note "$2: the link-launched sign-in is gone: known gap #188 in this version"; fi
}

install() {
    local mount
    mount=$(mktemp -d)
    hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mount" "$1" > /dev/null || return 1
    rm -rf "$APP" && ditto "$mount/Boaz.app" "$APP"
    hdiutil detach -quiet "$mount"
    note "Installed $(defaults read "$APP/Contents/Info" CFBundleShortVersionString) ($(basename "$1"))"
}

# Quits like the Dock does (an Apple Event from AppKit, so no Automation prompt), then waits for every Boaz process.
# With a second argument, a quit the app refuses is only noted (the old app's first-run welcome sheet refuses it).
quit() {
    "$OUT/quit" "$ID"
    if wait_for 60 bash -c "! pgrep -f '$APP/Contents/MacOS/' > /dev/null"; then
        pass "$1: quit cleanly"
    else
        shot "quit-stuck-$1"
        for pid in $(pgrep -f "$APP/Contents/MacOS/Boaz$"); do sample "$pid" 3 -file "$OUT/quit-sample-$1.txt" > /dev/null 2>&1; done
        if [ -n "${2:-}" ]; then note "$1: still running 60 s after quit; killed"; else fail "$1: still running 60 s after quit; killed"; fi
        pkill -9 -f "$APP/Contents/MacOS/"
        sleep 2
    fi
}

# Opens $2 in Boaz and waits for the fixture site to see it.
visit() {
    open -a "$APP" "$SITE$2"
    if wait_for 90 requested "$2"; then
        sleep 5   # lets the page's cookies and storage settle before anything quits
        return 0
    fi
    shot "no-request-$1"
    pid=$(pgrep -f "$APP/Contents/MacOS/Boaz$" | head -1)
    if [ -n "$pid" ]; then
        sample "$pid" 3 -file "$OUT/sample-$1.txt" > /dev/null 2>&1
        grep -q SecItemCopyMatching "$OUT/sample-$1.txt" && note "$1: main process is waiting on the Keychain"
    fi
    fail "$1: Boaz never requested $2"
    return 1
}

prefs_value() { defaults read "$1" "$2" 2>/dev/null; }

swiftc -O -o "$OUT/quit" - <<'EOF' || exit 1
import AppKit
for app in NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]) { _ = app.terminate() }
EOF
python3 "$HERE/fixture_server.py" "$PORT" "$SESSION" "$PLAIN" "$COLD" "$OUT/requests.jsonl" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT

echo "## Before: the previous version" >> "$RESULTS"
install "$FROM_DMG" || { fail "could not install $FROM_DMG"; exit 1; }
open -a "$APP"
wait_for 60 test -f "$OLD_DB" && pass "first launch created the library" || { shot first-launch; fail "no library after first launch"; }
sleep 5
shot first-launch
quit first-launch soft
# Settings: a real choice from each pane the old app has, a key no Boaz knows, and no update checks mid-test.
defaults write "$OLD_PREFS" onboardingCompleted -bool YES
defaults write "$OLD_PREFS" SUEnableAutomaticChecks -bool NO
defaults write "$OLD_PREFS" searchEngine -string duckDuckGo
defaults write "$OLD_PREFS" archiveAfter -int 604800
defaults write "$OLD_PREFS" sidebarTextSize -string large
defaults write "$OLD_PREFS" BoazAcceptanceFixture -string "$PLAIN"
defaults write "$NEW_PREFS" SUEnableAutomaticChecks -bool NO
python3 "$HERE/library.py" seed "$OLD_DB" && pass "seeded fixture folders, tabs, archive and history" || fail "could not seed the library"
# Signs in from a link that starts the app, before its library loads: v0.2.18 keeps that page's cookies in
# WebKit's default store, which the sandbox keeps in the container's Library/Cookies (#188).
visit cold-sign-in /cold && pass "previous version signed in from a link that started it"
quit cold-sign-in
stores=$(grep -rl "$COLD" "$CONTAINER/Library" 2>/dev/null | sed "s|$CONTAINER/||" | tr '\n' ' ')
note "the old version saved the link-launched sign-in in: ${stores:-nowhere}"
[[ " $stores " == *" Library/Cookies/Cookies.binarycookies "* ]] && pass "that sign-in is in the default store's cookie file" \
    || fail "that sign-in is not in Library/Cookies/Cookies.binarycookies, so this run doesn't test #188"
# Signs in from a running app, after its library has loaded, as a person would.
open -a "$APP"
sleep 15
visit sign-in /set && pass "previous version signed in to the fixture site"
quit sign-in
stores=$(grep -rl "$SESSION" "$CONTAINER/Library" 2>/dev/null | sed "s|$CONTAINER/||" | tr '\n' ' ')
[ -n "$stores" ] && note "the old version saved the sign-in cookie in: $stores" || fail "the old version saved no sign-in cookie"
python3 "$HERE/library.py" snapshot "$OLD_DB" "$OUT/before.json"
cp "$OLD_PREFS.plist" "$OUT/prefs-before.plist"
find "$CONTAINER/Library/WebKit" -type f -exec shasum {} + 2>/dev/null | sort > "$OUT/webkit-before.txt"
PROFILE=$(sqlite3 "$OLD_DB" "SELECT id FROM profile WHERE isDefault = 1 AND deletedAt IS NULL LIMIT 1")

echo "## After: the upgrade" >> "$RESULTS"
install "$TO_DMG" || { fail "could not install $TO_DMG"; exit 1; }
# Every request from here on is the new versions': all of them Chromium (must-have #1, #191).
UPGRADED_FROM=$(wc -l < "$OUT/requests.jsonl")
visit upgrade /whoami
sleep 5
shot after-upgrade
if signed_in /whoami; then pass "still signed in after the upgrade (the session cookie came back)"; else fail "signed out after the upgrade"; fi
check_cold /whoami "after the upgrade"
quit upgrade
python3 "$HERE/library.py" snapshot "$OLD_DB" "$OUT/after.json"
python3 "$HERE/library.py" compare "$OUT/before.json" "$OUT/after.json" > "$OUT/library.txt"
if [ $? -eq 0 ]; then pass "library: every space, tab, folder, archive item, history visit and profile survived"; else fail "library changed: $(grep -c FAIL "$OUT/library.txt") rows"; fi
sed 's/^/  /' "$OUT/library.txt" >> "$RESULTS"
[ ! -e "$HOME/Library/Application Support/Boaz/boaz.sqlite" ] && pass "no second library in Application Support" || fail "a second library appeared in Application Support"
[ "$(prefs_value "$NEW_PREFS" BoazLibraryLocation)" = legacy ] && pass "kept the library in the old container" || fail "BoazLibraryLocation is not legacy"
for key in searchEngine archiveAfter sidebarTextSize BoazAcceptanceFixture onboardingCompleted; do
    old=$(prefs_value "$OLD_PREFS" "$key") new=$(prefs_value "$NEW_PREFS" "$key")
    [ "$old" = "$new" ] && pass "setting $key = $new" || fail "setting $key was '$old', now '$new'"
done
for marker in BoazChromiumLegacyPreferencesImportedV1 BoazChromiumLegacyWebKitDataImportedV1; do
    [ "$(prefs_value "$NEW_PREFS" "$marker")" = 1 ] && pass "$marker set" || fail "$marker not set"
done
cookie_state() {
    if fixed_in_050; then
        for key in "BoazChromiumLegacyCookiesImportV2.$PROFILE" BoazChromiumLegacyDefaultCookiesImportedV1; do
            note "$key: $(python3 -c 'import plistlib, sys; v = plistlib.load(open(sys.argv[1], "rb")).get(sys.argv[2]); print(v.decode() if isinstance(v, bytes) else v)' "$NEW_PREFS.plist" "$key")"
        done
    else
        [ "$(prefs_value "$NEW_PREFS" "BoazChromiumLegacyCookiesImportedV1.$PROFILE")" = 1 ] \
            && pass "BoazChromiumLegacyCookiesImportedV1.$PROFILE set" || fail "BoazChromiumLegacyCookiesImportedV1.$PROFILE not set"
    fi
}
cookie_state
find "$CONTAINER/Library/WebKit" -type f -exec shasum {} + 2>/dev/null | sort > "$OUT/webkit-after.txt"
comm -23 "$OUT/webkit-before.txt" "$OUT/webkit-after.txt" > "$OUT/webkit-changed.txt"
[ ! -s "$OUT/webkit-changed.txt" ] && pass "old website data left untouched" || fail "old website data changed: $(wc -l < "$OUT/webkit-changed.txt") files"
security find-generic-password -s "Boaz Chromium Safe Storage" > /dev/null 2>&1 \
    && note "the Boaz Chromium Safe Storage Keychain item exists" || note "no Boaz Chromium Safe Storage Keychain item"
for db in "$HOME/Library/Application Support/Boaz/Chromium"/Boaz-*/Cookies "$HOME/Library/Application Support/Boaz/Chromium"/Boaz-*/Network/Cookies; do
    [ -f "$db" ] || continue
    rows=$(sqlite3 "$db" "SELECT count(*) FROM cookies WHERE host_key = '127.0.0.1' AND name IN ('boaz_session', 'boaz_plain', 'boaz_cold')")
    note "Chromium cookie store ${db#"$HOME"/}: $rows fixture cookies"
done

echo "## Again: a second launch" >> "$RESULTS"
visit relaunch "/whoami?again"
if signed_in "/whoami?again"; then pass "still signed in on the next launch"; else fail "signed out on the next launch"; fi
check_cold "/whoami?again" "on the next launch"
# Probe: does quitting with osascript need an Automation permission on this Mac?
if perl -e 'alarm 20; exec @ARGV' osascript -e "tell application id \"$ID\" to quit" > "$OUT/osascript.txt" 2>&1; then
    note "probe: osascript quit ran without an Automation prompt"
else
    shot osascript-quit
    note "probe: osascript quit failed or timed out: $(tr '\n' ' ' < "$OUT/osascript.txt")"
fi
running && quit relaunch || note "Boaz quit on osascript's request"

if [ -n "$THEN_DMG" ]; then
    echo "## Then: upgrading again, from the version above" >> "$RESULTS"
    install "$THEN_DMG" || { fail "could not install $THEN_DMG"; exit 1; }
    visit second-upgrade "/whoami?then"
    if signed_in "/whoami?then"; then pass "still signed in after the second upgrade"; else fail "signed out after the second upgrade"; fi
    check_cold "/whoami?then" "after the second upgrade"
    quit second-upgrade
    cookie_state
    python3 "$HERE/library.py" snapshot "$OLD_DB" "$OUT/then.json"
    python3 "$HERE/library.py" compare "$OUT/before.json" "$OUT/then.json" > "$OUT/library-then.txt" \
        && pass "library survived the second upgrade" || fail "library changed in the second upgrade"
fi

echo "## Engine" >> "$RESULTS"
# The fixture has no protected video, so no page loads in WebKit, and no request (icon fetches included) may tell
# the site it is Safari.
upgraded=$(tail -n +"$((UPGRADED_FROM + 1))" "$OUT/requests.jsonl")
webkit=$(echo "$upgraded" | grep '"mode": "navigate"' | grep 'AppleWebKit/605' | grep -v 'Chrome/')
safari=$(echo "$upgraded" | grep -E 'Version/[0-9.]+ Safari/')
paths() { echo "$1" | sed -E 's/.*"path": "([^"]*)".*/\1/' | sort -u | tr '\n' ' '; }
# A published version before 0.5.0 has #191, so there it's only noted.
known_191() { if fixed_in_050; then fail "$1 (#191)"; else note "KNOWN #191 (fixed in 0.5.0): $1"; fi; }
if [ -z "$webkit" ]; then pass "every page the upgraded Boaz loaded ran in Chromium"
else known_191 "WebKit loaded $(paths "$webkit")"; fi
if [ -z "$safari" ]; then pass "no request from the upgraded Boaz presented as Safari"
else known_191 "requests for $(paths "$safari")presented as Safari"; fi

log show --last 30m --info --predicate "subsystem == \"$ID\"" > "$OUT/boaz.log" 2>&1
log show --last 30m --predicate 'process == "tccd"' 2>/dev/null | grep -i -E "boaz|AppData" > "$OUT/tccd.log"
grep -E "previous cookies|Two libraries" "$OUT/boaz.log" | sed 's/^/  /' >> "$RESULTS"
[ -s "$OUT/tccd.log" ] && note "probe: tccd logged $(wc -l < "$OUT/tccd.log") Boaz or App Data lines (tccd.log)" || note "probe: tccd logged nothing about Boaz or App Data"
exit $FAILED
