#!/usr/bin/env python3
"""Tools/perf/perf.py — docs/qa.md §4 baselines (PLAN-04).

Re-measures every §4 row against the *published* Boaz DMG, on an isolated copy re-branded as the development
identity (com.chenkahana.boaz.chromium.dev) and ad-hoc re-signed with no entitlements, run under a throwaway HOME.
Never touches the installed Boaz or Chen's real library (must-have #13): see `run_precheck_guards` /
`run_postcheck_guards` below, which abort the whole run rather than risk it.

Every row that drives the UI (newtab, typing, archive) needs an Accessibility grant for the process running this
script, and every row launches a real GUI window — never start a session while Chen is screen-sharing, and only on
the orchestrator's go. See docs/qa.md §4 for the one-command invocation and what each flag means operationally.

Stdlib only. Subcommands: prepare, guard-check, launch, newtab, typing, tabs, archive, memory, all.
"""
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
import plistlib
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PERF_DIR = Path(__file__).resolve().parent
SEED_PACKAGE = PERF_DIR / "seed"
WINDOW_WAIT = PERF_DIR / "window-wait.swift"
PAGE_TEMPLATE_PATH = PERF_DIR / "pages" / "template.html"
AUTOMATION_CLIENT_DIR = REPO_ROOT / "Tools" / "chromium"

# Isolation (revised 2026-11-26, architect-04): on this host cfprefsd ignores CFFIXED_USER_HOME/HOME for an
# unsandboxed client (dev-04 found this; sandbox-exec doesn't fix it either — see the item file's Approach). The
# fix is identity, not environment: the perf copy is re-branded as the development identity launch.mm already
# accepts (the 3 Info.plist keys Tools/chromium/stage-application.py writes for a dev build), so any prefs write
# that escapes HOME redirection still lands in `com.chenkahana.boaz.chromium.dev`'s own domain, never Chen's real
# `com.chenkahana.boaz`. In-process path resolution (FileManager, NSHomeDirectory) does honor the fixed HOME, so
# the store and the Chromium profile stay isolated under the throwaway home as before.
PROD_BUNDLE_ID = "com.chenkahana.boaz"
DEV_BUNDLE_ID = "com.chenkahana.boaz.chromium.dev"
DEV_CHANNEL = "development"
DEV_PRODUCT_DIR = "Boaz Chromium Development"  # CrProductDirName for the dev identity; no "/" (single path component)
DEFAULT_RUN_ROOT = Path.home() / "tmp" / "codex" / "boaz-perf"
REAL_WATCHED_DIRS = [
    Path.home() / "Library" / "Application Support" / "Boaz",
    Path.home() / "Library" / "Containers" / PROD_BUNDLE_ID,
]
REAL_SITES = [
    "https://en.wikipedia.org/wiki/Special:Random",
    "https://www.apple.com",
    "https://news.ycombinator.com",
    "https://github.com",
    "https://www.nytimes.com",
]


def log(message: str) -> None:
    print(f"[perf] {message}", flush=True)


class Abort(SystemExit):
    """A guard failed, or a step the harness depends on didn't behave as expected. Always stop, never guess."""

    def __init__(self, reason: str):
        super().__init__(f"ABORT: {reason}")


# ---------------------------------------------------------------------------------------------------------------
# Guards (must-have #13). Each one can run on its own with nothing launched yet — `guard-check` exercises exactly
# that, so the safety net itself can be proven without a GUI session. precheck/postcheck bracket every row.
# ---------------------------------------------------------------------------------------------------------------

def bundle_identifier_of(app_root: Path) -> str | None:
    info = app_root / "Contents" / "Info.plist"
    if not info.is_file():
        return None
    try:
        with info.open("rb") as handle:
            return plistlib.load(handle).get("CFBundleIdentifier")
    except (OSError, ValueError):
        return None


def _enclosing_app_bundle(executable_path: str) -> Path | None:
    for parent in Path(executable_path).parents:
        if parent.suffix == ".app":
            return parent
    return None


def guard_no_other_dev_instance_running() -> None:
    """Aborts if any process anywhere is running the dev identity (`com.chenkahana.boaz.chromium.dev`) — Chen's
    own dev-16 testing build included. Guards don't run while our own copy is up (every row quits it and waits
    before checking), so any match here means someone else's dev build, or a leftover from a previous session.

    Matched by reading each candidate process's own Info.plist, not by path or executable name: the published
    DMG's CFBundleExecutable is "Chromium" (confirmed live while writing this — not "Boaz"; Tools/acceptance/
    upgrade.sh's `Contents/MacOS/Boaz` assumption is for a different, older build), so neither the binary name nor
    a fixed path can identify "the dev build" on its own. Chen's real production Boaz may keep running: the
    bundle id differs, so `open -a <dev copy>` can never reach it (that's the whole point of the revised isolation)."""
    out = subprocess.run(["ps", "-A", "-o", "pid=,comm="], capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        pid, comm = parts
        app_root = _enclosing_app_bundle(comm)
        if app_root is None:
            continue
        if bundle_identifier_of(app_root) == DEV_BUNDLE_ID:
            raise Abort(f"a {DEV_BUNDLE_ID} process is already running (pid {pid}, {comm}) — "
                        "quit it before a perf session (this also covers a leftover from a previous run)")


def guard_identity_is_dev(app_path: Path) -> None:
    """Guard #1 (revised): the staged copy must actually be the dev identity, not production — the thing that
    keeps every prefs write, wherever cfprefsd actually puts it, out of Chen's real `com.chenkahana.boaz` domain."""
    identity = bundle_identifier_of(app_path)
    if identity != DEV_BUNDLE_ID:
        raise Abort(f"{app_path}'s bundle id is {identity!r}, not {DEV_BUNDLE_ID!r} — refusing to launch it")


def guard_entitlements_empty(app_path: Path) -> None:
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", str(app_path)],
                             capture_output=True, text=True)
    if "<key>" in result.stdout or "<key>" in result.stderr:
        raise Abort(f"{app_path} still carries entitlements — the perf copy must be re-signed with none")


def backup_dev_prefs() -> Path:
    """Backs up the dev identity's own prefs domain before a run (restored after by `restore_dev_prefs`), so a
    session never leaves the dev identity's defaults looking different than it found them — not a must-have #13
    exposure either way (it's not Chen's production domain), but no reason to let it drift. Aborts if the backup
    itself fails: better to not run than to restore from nothing."""
    with tempfile.NamedTemporaryFile(suffix=".plist", prefix="boaz-perf-dev-prefs-", delete=False) as handle:
        backup_path = Path(handle.name)
    result = subprocess.run(["defaults", "export", DEV_BUNDLE_ID, str(backup_path)], capture_output=True, text=True)
    if result.returncode != 0:
        raise Abort(f"could not back up {DEV_BUNDLE_ID} prefs before the run — stopping rather than risk them: "
                    f"{result.stderr.strip()}")
    return backup_path


def restore_dev_prefs(backup_path: Path) -> None:
    subprocess.run(["defaults", "delete", DEV_BUNDLE_ID], capture_output=True)
    result = subprocess.run(["defaults", "import", DEV_BUNDLE_ID, str(backup_path)], capture_output=True, text=True)
    if result.returncode != 0:
        log(f"warning: could not restore {DEV_BUNDLE_ID} prefs from {backup_path} — not a #13 exposure "
            "(it's the dev domain, not Chen's production one), but the dev identity's defaults may now differ "
            f"from before this run: {result.stderr.strip()}")
    backup_path.unlink(missing_ok=True)


def snapshot_real_library() -> dict:
    """Cheap, read-only fingerprint of Chen's real library: file count / total bytes / latest mtime per watched
    directory (not a full content hash — these can hold gigabytes of Chromium cache), plus the real app's defaults
    domain. Compared before and after every row; any difference aborts the harness immediately. This is now the
    guard that matters for "does a prefs write ever reach production": it should read as unchanged because the
    dev identity's domain is a different file entirely, not because any environment trick isolated it."""
    snapshot: dict = {}
    for path in REAL_WATCHED_DIRS:
        if not path.exists():
            snapshot[str(path)] = None
            continue
        count = total = 0
        latest = 0.0
        for root, _dirs, files in os.walk(path):
            for name in files:
                count += 1
                try:
                    st = os.stat(os.path.join(root, name))
                except OSError:
                    continue
                total += st.st_size
                latest = max(latest, st.st_mtime)
        snapshot[str(path)] = {"files": count, "bytes": total, "latestMtime": latest}
    exported = subprocess.run(["defaults", "export", PROD_BUNDLE_ID, "-"], capture_output=True)
    snapshot["defaults_sha256"] = hashlib.sha256(exported.stdout).hexdigest()
    return snapshot


def guard_library_untouched(before: dict, after: dict) -> None:
    if before != after:
        raise Abort(
            "Chen's real Boaz library or defaults changed during the run (must-have #13) — stopping now.\n"
            f"before={json.dumps(before, sort_keys=True)}\nafter={json.dumps(after, sort_keys=True)}\n"
            "The harness never points at these paths on purpose, so this means isolation broke somewhere. "
            "Inspect ~/Library/Application Support/Boaz and ~/Library/Containers/com.chenkahana.boaz by hand "
            "before trusting them again; nothing here attempts an automatic restore of real user data."
        )


def run_precheck_guards(perf_copy: Path) -> tuple[dict, Path]:
    guard_no_other_dev_instance_running()
    guard_identity_is_dev(perf_copy)
    guard_entitlements_empty(perf_copy)
    dev_prefs_backup = backup_dev_prefs()
    return snapshot_real_library(), dev_prefs_backup


def run_postcheck_guards(before: dict, dev_prefs_backup: Path) -> None:
    guard_no_other_dev_instance_running()
    guard_library_untouched(before, snapshot_real_library())
    restore_dev_prefs(dev_prefs_backup)


# ---------------------------------------------------------------------------------------------------------------
# Isolation: download + verify the published DMG, stage an ad-hoc re-signed, empty-entitlement copy.
# ---------------------------------------------------------------------------------------------------------------

def read_info_plist(app_path: Path) -> dict:
    with (app_path / "Contents" / "Info.plist").open("rb") as handle:
        return plistlib.load(handle)


def write_info_plist(app_path: Path, data: dict) -> None:
    with (app_path / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(data, handle)  # always XML on write; CFBundle reads XML or binary plists interchangeably


def read_bundle_id(app_path: Path) -> str:
    return read_info_plist(app_path).get("CFBundleIdentifier", "")


def read_cfbundle_executable(app_path: Path) -> str:
    """The actual running process's name. Confirmed live while building the revised isolation: the published
    DMG's CFBundleExecutable is "Chromium", not "Boaz" — Tools/acceptance/upgrade.sh's `Contents/MacOS/Boaz`
    assumption is for a different, older build, and hardcoding "Boaz" here would make every launch-finding
    function silently never find the process."""
    executable = read_info_plist(app_path).get("CFBundleExecutable")
    if not executable:
        raise Abort(f"{app_path}'s Info.plist has no CFBundleExecutable")
    return executable


def download_dmg(tag: str, cache_root: Path) -> Path:
    cache_dir = cache_root / tag
    cache_dir.mkdir(parents=True, exist_ok=True)
    dmg_path = cache_dir / "Boaz.dmg"
    checksum_path = cache_dir / "Boaz.dmg.sha256"
    if not dmg_path.exists() or not checksum_path.exists():
        log(f"downloading the published {tag} DMG from GitHub releases")
        subprocess.run(["gh", "release", "download", tag, "-R", "chenkahana/Boaz", "-p", "Boaz.dmg*",
                        "-D", str(cache_dir), "--clobber"], check=True)
    if not checksum_path.exists():
        raise Abort(f"{tag} has no Boaz.dmg.sha256 asset published — can't verify the download")
    verify = subprocess.run(["shasum", "-a", "256", "-c", "Boaz.dmg.sha256"],
                             cwd=cache_dir, capture_output=True, text=True)
    if verify.returncode != 0:
        raise Abort(f"Boaz.dmg for {tag} failed shasum -c:\n{verify.stdout}{verify.stderr}")
    log(f"{tag}: {verify.stdout.strip()}")
    return dmg_path


def stage_isolated_copy(dmg_path: Path, destination: Path) -> Path:
    """Ditto's the DMG's app, verifies it's really the production bits, then re-brands it as the development
    identity launch.mm already accepts (the Info.plist keys Tools/chromium/stage-application.py writes for a dev
    build — see the item file's "Isolation (revised)") before ad-hoc signing with no entitlements and no hardened
    runtime. The Chromium and UI binaries are untouched; only the 3 identity keys change. CloudKitEntitlements
    reports this process as unsigned for iCloud regardless of identity, so sync stays idle for the whole session."""
    if destination.exists():
        import shutil
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="boaz-perf-mount-") as mount_point:
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount_point, str(dmg_path)],
                        check=True, capture_output=True)
        try:
            source_app = Path(mount_point) / "Boaz.app"
            if not source_app.exists():
                raise Abort(f"{dmg_path} has no Boaz.app at its root")
            app_path = destination / "Boaz.app"
            subprocess.run(["ditto", str(source_app), str(app_path)], check=True, capture_output=True)
        finally:
            subprocess.run(["hdiutil", "detach", mount_point], capture_output=True)

    info = read_info_plist(app_path)
    if info.get("CFBundleIdentifier") != PROD_BUNDLE_ID or info.get("BoazDistributionChannel") != "production":
        raise Abort(f"{dmg_path} isn't the production Boaz build (got identifier="
                    f"{info.get('CFBundleIdentifier')!r}, channel={info.get('BoazDistributionChannel')!r})")
    info["CFBundleIdentifier"] = DEV_BUNDLE_ID
    info["BoazDistributionChannel"] = DEV_CHANNEL
    info["CrProductDirName"] = DEV_PRODUCT_DIR
    write_info_plist(app_path, info)

    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app_path)], check=True, capture_output=True)
    guard_entitlements_empty(app_path)
    guard_identity_is_dev(app_path)
    log(f"staged isolated copy at {app_path}, re-branded as {DEV_BUNDLE_ID}, ad-hoc signed, no entitlements")
    return app_path


# ---------------------------------------------------------------------------------------------------------------
# Fixtures: build and run Tools/perf/seed (SwiftPM, BoazKit's public API only) into a throwaway HOME.
# ---------------------------------------------------------------------------------------------------------------

def build_seed_tool() -> Path:
    subprocess.run(["swift", "build", "--package-path", str(SEED_PACKAGE)], check=True)
    return SEED_PACKAGE / ".build" / "debug" / "seed"


def seed_home(home: Path, *, visits: int = 0, today_tabs: int = 0, space_title: str = "Perf") -> dict:
    home.mkdir(parents=True, exist_ok=True)
    seed_bin = build_seed_tool()
    args = [str(seed_bin), "--home", str(home), "--bundle-id", DEV_BUNDLE_ID, "--space-title", space_title,
            "--verify"]
    if visits:
        args += ["--visits", str(visits)]
    if today_tabs:
        args += ["--today-tabs", str(today_tabs)]
    result = subprocess.run(args, check=True, capture_output=True, text=True)
    report = json.loads(result.stdout.strip().splitlines()[-1])
    log(f"seeded {home.name}: {report}")
    return report


# ---------------------------------------------------------------------------------------------------------------
# Local pages: a tiny loopback HTTP server rendering Tools/perf/pages/template.html with a unique <title> per
# path, so every row measures local rendering, not a site's own latency. python3 -m http.server can't do this
# (it only serves files that already exist), so this generates them on request instead of pre-materializing
# hundreds of near-identical N.html files on disk.
# ---------------------------------------------------------------------------------------------------------------

_page_template_cache: str | None = None


def page_template() -> str:
    global _page_template_cache
    if _page_template_cache is None:
        _page_template_cache = PAGE_TEMPLATE_PATH.read_text()
    return _page_template_cache


class PageHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 (BaseHTTPRequestHandler's naming)
        label = self.path.strip("/") or "0"
        body = page_template().replace("{{TITLE}}", f"Perf {label}").replace("{{LABEL}}", label).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args) -> None:  # quiet; perf.py logs what matters
        pass


@dataclass
class PageServer:
    httpd: http.server.ThreadingHTTPServer
    thread: threading.Thread

    @property
    def port(self) -> int:
        return self.httpd.server_address[1]

    def url(self, label) -> str:
        return f"http://127.0.0.1:{self.port}/{label}"

    def stop(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)


def start_page_server() -> PageServer:
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), PageHandler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    return PageServer(httpd, thread)


# ---------------------------------------------------------------------------------------------------------------
# Automation client (Tools/chromium/automation_client.py), for rows that need to know what the browser is
# showing (newtab, tabs) without screen-scraping.
# ---------------------------------------------------------------------------------------------------------------

def _automation_client():
    if str(AUTOMATION_CLIENT_DIR) not in sys.path:
        sys.path.insert(0, str(AUTOMATION_CLIENT_DIR))
    import automation_client  # type: ignore
    return automation_client


def automation_record_dir(home: Path) -> Path:
    """Matches `PackagedApplicationUserDataPath()` in Tools/chromium/host/launch.mm: for the dev identity,
    `CrProductDirName` ("Boaz Chromium Development") is a single path component (no "/"), appended directly to
    the plain NSApplicationSupportDirectory — unlike production's "Boaz/Chromium", which splits into two. This is
    a different, independent namespacing scheme than BoazKit's own store path (see `seed_home`), which the
    development branch of `ChromiumLegacyStore.applicationSupportDirectory()` namespaces by bundle id instead."""
    return home / "Library" / "Application Support" / DEV_PRODUCT_DIR / "Automation"


def page_titles(home: Path) -> list[str]:
    client = _automation_client()
    port, token = client.connection(str(automation_record_dir(home)))
    request = urllib.request.Request(f"http://127.0.0.1:{port}/json/list",
                                      headers={"Authorization": f"Bearer {token}"})
    pages = json.load(urllib.request.urlopen(request, timeout=10))
    return [p["title"] for p in pages if p.get("type") == "page"]


# ---------------------------------------------------------------------------------------------------------------
# Launching / quitting the perf copy.
# ---------------------------------------------------------------------------------------------------------------

def launch_app(app_path: Path, home: Path, *, automation: bool = False) -> int:
    """Everything here goes in as a launch argument (NSArgumentDomain: in-memory for this process only, never
    persisted to a plist) rather than a `defaults write` — belt-and-suspenders on top of the dev identity itself:
    even if `defaults write` doesn't go where HOME says it should (confirmed live: it doesn't, for an unsandboxed
    process — see the item file's "Isolation (revised)"), nothing here deliberately writes to any domain at all."""
    home.mkdir(parents=True, exist_ok=True)
    args = ["--use-mock-keychain", "-onboardingCompleted", "YES", "-ApplePersistenceIgnoreState", "YES",
            "-SUEnableAutomaticChecks", "NO"]
    if automation:
        args.append("--boaz-automation")
    subprocess.run(["open", "-n", "-a", str(app_path),
                    "--env", f"HOME={home}", "--env", f"CFFIXED_USER_HOME={home}",
                    "--args", *args], check=True)
    return wait_for_pid(app_path)


def wait_for_pid(app_path: Path, timeout: float = 15.0) -> int:
    exe = app_path / "Contents" / "MacOS" / read_cfbundle_executable(app_path)
    exe_name = exe.name
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for pid in subprocess.run(["pgrep", "-x", exe_name], capture_output=True, text=True).stdout.split():
            comm = subprocess.run(["ps", "-o", "comm=", "-p", pid], capture_output=True, text=True).stdout.strip()
            try:
                if exe.exists() and Path(comm).resolve() == exe.resolve():
                    return int(pid)
            except OSError:
                continue
        time.sleep(0.05)
    raise Abort(f"{app_path} never appeared as a running process within {timeout}s")


def quit_app(app_path: Path, pid: int, timeout: float = 20.0) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not subprocess.run(["pgrep", "-f", str(app_path)], capture_output=True, text=True).stdout.split():
            return
        time.sleep(0.1)
    log(f"{app_path} (or a helper) didn't quit within {timeout}s; sending SIGKILL")
    for leftover in subprocess.run(["pgrep", "-f", str(app_path)], capture_output=True, text=True).stdout.split():
        try:
            os.kill(int(leftover), signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)


def keystroke(pid: int, script: str) -> None:
    """Drives `pid` through System Events, targeted by unix id (not bundle id, not "frontmost") so it can never
    reach a different Boaz process even if one existed. Needs an Accessibility grant for this script's host."""
    wrapped = f'tell application "System Events" to tell (first process whose unix id is {pid})\n{script}\nend tell'
    result = subprocess.run(["osascript", "-e", wrapped], capture_output=True, text=True)
    if result.returncode != 0:
        raise Abort(f"System Events couldn't drive pid {pid} (Accessibility grant missing?): {result.stderr.strip()}")


# ---------------------------------------------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------------------------------------------

def summarize(samples: list[float]) -> dict:
    """One discarded warm-up (the Approach's N=7-after-warm-up rule), median + min/max over the rest."""
    kept = samples[1:] if len(samples) > 1 else samples
    return {"n": len(kept), "median": round(statistics.median(kept), 4),
            "min": round(min(kept), 4), "max": round(max(kept), 4), "samples": [round(s, 4) for s in samples]}


def machine_context() -> dict:
    """sw_vers, Mac model, and power state — recorded alongside every row per the Approach's statistics section,
    since any of these can explain a number that looks "worse than the previous cycle" without being a regression."""
    sw_vers = subprocess.run(["sw_vers"], capture_output=True, text=True).stdout.strip()
    model = subprocess.run(["sysctl", "-n", "hw.model"], capture_output=True, text=True).stdout.strip()
    battery = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True).stdout
    power_settings = subprocess.run(["pmset", "-g"], capture_output=True, text=True).stdout
    low_power = any(line.strip().startswith("lowpowermode") and line.strip().endswith("1")
                    for line in power_settings.splitlines())
    return {
        "sw_vers": sw_vers,
        "model": model,
        "on_battery": "Battery Power" in battery,
        "low_power_mode": low_power,
    }


# ---------------------------------------------------------------------------------------------------------------
# Rows
# ---------------------------------------------------------------------------------------------------------------

def measure_launch(app_path: Path, run_root: Path, n: int) -> dict:
    home = run_root / "homes" / "launch"
    seed_home(home, today_tabs=10)
    samples = []
    for i in range(n + 1):
        before, dev_prefs_backup = run_precheck_guards(app_path)
        t0 = time.monotonic()
        pid = launch_app(app_path, home)
        result = subprocess.run(["swift", str(WINDOW_WAIT), str(pid), "30"], capture_output=True, text=True)
        elapsed = time.monotonic() - t0
        if result.returncode != 0:
            raise Abort(f"launch sample {i}: {result.stderr.strip()}")
        samples.append(elapsed)
        quit_app(app_path, pid)
        run_postcheck_guards(before, dev_prefs_backup)
        log(f"launch sample {i}: {elapsed:.3f}s")
    return summarize(samples)


def measure_newtab(app_path: Path, run_root: Path, n: int, *, include_real_sites: bool) -> dict:
    home = run_root / "homes" / "newtab"
    seed_home(home, today_tabs=10)
    before, dev_prefs_backup = run_precheck_guards(app_path)
    pages = start_page_server()
    pid = launch_app(app_path, home, automation=True)
    local_samples, real_samples = [], []
    try:
        for i in range(n + 1):
            url = pages.url(i)
            expected_title = f"Perf {i}"
            t0 = time.monotonic()
            keystroke(pid, 'keystroke "t" using command down\n'
                           f'keystroke "{url}"\nkey code 36')  # 36 = Return
            local_samples.append(_wait_for_title(home, expected_title, t0))
            log(f"newtab (local) sample {i}: {local_samples[-1]:.3f}s")
        if include_real_sites:
            for i, url in enumerate(REAL_SITES):
                before_titles = set(page_titles(home))  # snapshot BEFORE the keystroke, so "new" means new
                t0 = time.monotonic()
                keystroke(pid, f'keystroke "t" using command down\nkeystroke "{url}"\nkey code 36')
                real_samples.append(_wait_for_new_title(home, before_titles, t0))
                log(f"newtab (real site {url}) sample {i}: {real_samples[-1]:.3f}s")
    finally:
        quit_app(app_path, pid)
        pages.stop()
        run_postcheck_guards(before, dev_prefs_backup)
    result = {"local": summarize(local_samples)}
    if include_real_sites:
        result["real_sites"] = summarize(real_samples) if real_samples else None
    return result


def _wait_for_title(home: Path, expected_title: str, t0: float, timeout: float = 20.0) -> float:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if expected_title in page_titles(home):
            return time.monotonic() - t0
        time.sleep(0.02)
    raise Abort(f"new tab never showed title {expected_title!r} within {timeout}s")


def _wait_for_new_title(home: Path, before_titles: set[str], t0: float, timeout: float = 20.0) -> float:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        titles = set(page_titles(home))
        if titles - before_titles:
            return time.monotonic() - t0
        time.sleep(0.05)
    raise Abort(f"new tab never produced a new title within {timeout}s")


def measure_typing(app_path: Path, run_root: Path, n: int) -> dict:
    home = run_root / "homes" / "typing"
    seed_home(home, visits=50_000, today_tabs=10)
    before, dev_prefs_backup = run_precheck_guards(app_path)
    pid = launch_app(app_path, home)
    keys = "github"
    samples = []
    try:
        for i in range(n + 1):
            keystroke(pid, 'keystroke "l" using command down')
            time.sleep(0.2)
            sample_proc = subprocess.Popen(["sample", str(pid), "2", "1", "-file", f"/tmp/boaz-perf-sample-{i}.txt"],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for ch in keys:
                keystroke(pid, f'keystroke "{ch}"')
                time.sleep(0.25)
            sample_proc.wait(timeout=10)
            main_thread_ms = _parse_sample_main_thread_ms(Path(f"/tmp/boaz-perf-sample-{i}.txt"))
            per_keystroke = main_thread_ms / len(keys)
            samples.append(per_keystroke)
            keystroke(pid, 'key code 53')  # Escape, clear the address bar edit
            log(f"typing sample {i}: {per_keystroke:.2f} ms/keystroke")
    finally:
        quit_app(app_path, pid)
        run_postcheck_guards(before, dev_prefs_backup)
    return summarize(samples)


_SAMPLE_THREAD_HEADER = re.compile(r"^(?P<indent>[\s+!:|]*)\d+\s+Thread_")
_SAMPLE_FRAME = re.compile(r"^(?P<indent>[\s+!:|]*)(?P<count>\d+)\s")
_IDLE_LEAVES = ("mach_msg", "__psynch_cvwait", "__semwait_signal", "__select", "__sigsuspend", "start_wqthread",
                "__workq_kernreturn", "kevent")


def _parse_sample_main_thread_ms(sample_path: Path) -> float:
    """Counts non-idle main-thread stack samples from `sample`'s text "Call graph:" section (idle = a leaf under
    a known wait primitive — mach_msg_trap, __sigsuspend and friends — the way CFRunLoop parks a thread with
    nothing to do) and converts to milliseconds at `sample`'s default ~1ms interval.

    `sample` has no machine-readable output mode, so this parses indentation: every top-level thread entry in the
    call graph shares one indentation depth (confirmed against a real single-threaded capture while writing this:
    `    875 Thread_116741679   DispatchQueue_1: com.apple.main-thread  (serial)`, 4 spaces), and a leaf is any
    line whose next sibling-or-shallower line doesn't go deeper. Best-effort by necessity, not exact bytecode-level
    accounting — matches the Approach's own framing of `sample`-based main-thread time.
    """
    if not sample_path.exists():
        raise Abort(f"`sample` produced no output at {sample_path}")
    lines = sample_path.read_text(errors="replace").splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "Call graph:") + 1
    except StopIteration:
        raise Abort(f"{sample_path} has no 'Call graph:' section — unexpected `sample` output")
    end = next((i for i, l in enumerate(lines[start:], start)
               if l.strip().startswith(("Total number in stack", "Sort by top of stack", "Binary Images:"))), len(lines))
    matches = [(l, _SAMPLE_FRAME.match(l)) for l in lines[start:end]]
    frames = [(l, m) for l, m in matches if m]
    if not frames:
        return 0.0
    depths = [len(m.group("indent")) for _l, m in frames]
    thread_depth = min(depths)

    # Each leaf line's own leading number is how many 1ms samples took exactly that path — not 1 sample per line,
    # which is what a plain line count would give (confirmed live: a tight CPU loop's "Call graph:" splits into
    # dozens of leaf lines whose counts sum to the thread's real total, e.g. 852, not the ~20 distinct leaves).
    non_idle = 0
    in_main = False
    for i, (line, match) in enumerate(frames):
        depth = depths[i]
        if depth == thread_depth:
            in_main = "main-thread" in line.lower() or bool(_SAMPLE_THREAD_HEADER.match(line) and "main" in line.lower())
            continue
        if not in_main:
            continue
        is_leaf = i + 1 >= len(frames) or depths[i + 1] <= depth
        if is_leaf and not any(marker in line for marker in _IDLE_LEAVES):
            non_idle += int(match.group("count"))
    # `sample`'s default rate is ~1ms between samples.
    return float(non_idle)


def measure_tabs(app_path: Path, run_root: Path, n: int, *, total_tabs: int = 150) -> dict:
    home = run_root / "homes" / "tabs"
    seed_home(home, today_tabs=10)
    before, dev_prefs_backup = run_precheck_guards(app_path)
    pages = start_page_server()
    pid = launch_app(app_path, home, automation=True)
    opens = []
    try:
        for i in range(total_tabs):
            t0 = time.monotonic()
            subprocess.run(["open", "-a", str(app_path), pages.url(i)], check=True)
            _wait_for_title(home, f"Perf {i}", t0)
            opens.append(time.monotonic() - t0)
    finally:
        quit_app(app_path, pid)
        pages.stop()
        run_postcheck_guards(before, dev_prefs_backup)
    first = opens[:10]
    last = opens[-10:]
    return {
        "first_10_median": round(statistics.median(first), 4),
        "last_10_median": round(statistics.median(last), 4),
        "all_samples": [round(o, 4) for o in opens],
    }


def measure_archive(app_path: Path, run_root: Path, n: int) -> dict:
    home = run_root / "homes" / "archive"
    samples = []
    for i in range(n + 1):
        seed_home(home, today_tabs=150)  # fresh 150 Today tabs each sample; archiving empties the container
        before, dev_prefs_backup = run_precheck_guards(app_path)
        pid = launch_app(app_path, home, automation=True)
        try:
            t0 = time.monotonic()
            # Right-click the "Perf" space row in the sidebar, then its "Archive Today's Tabs" menu item.
            keystroke(pid, 'tell application "System Events"\n'
                           'set spaceRow to (first UI element whose title contains "Perf")\n'
                           'perform action "AXShowMenu" of spaceRow\n'
                           'click menu item "Archive Today\'s Tabs" of menu 1 of spaceRow\n'
                           'end tell')
            elapsed = _wait_for_archive_settled(home, t0)
            samples.append(elapsed)
            log(f"archive sample {i}: {elapsed:.3f}s")
        finally:
            quit_app(app_path, pid)
            run_postcheck_guards(before, dev_prefs_backup)
    return summarize(samples)


def _wait_for_archive_settled(home: Path, t0: float, timeout: float = 30.0) -> float:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not page_titles(home):
            return time.monotonic() - t0
        time.sleep(0.05)
    raise Abort(f"archive never cleared Today's tabs within {timeout}s")


_FOOTPRINT_PROCESS_HEADER = re.compile(r"^(?P<name>.+) \[(?P<pid>\d+)\]: ")
_FOOTPRINT_PEAK = re.compile(r"phys_footprint_peak:\s*(?P<bytes>\d+)\s*B")


def footprint_snapshot(pids: list[int]) -> dict:
    """One `footprint -j` call across every pid (confirmed live: positional pids work and the JSON's top-level
    "total footprint" already sums them). `-f bytes` so nothing is pre-rounded to MB. Peak isn't in the JSON
    (checked: only the human-readable "Auxiliary data" text has `phys_footprint_peak`), so this pairs each
    process's peak from stdout by the "<name> [<pid>]:" header that precedes its block."""
    if not pids:
        return {"current_bytes": 0, "peak_bytes": 0, "per_process": []}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as handle:
        json_path = Path(handle.name)
    try:
        result = subprocess.run(["footprint", "-j", str(json_path), "-f", "bytes", *map(str, pids)],
                                capture_output=True, text=True)
        data = json.loads(json_path.read_text()) if json_path.exists() else {"processes": []}
    finally:
        json_path.unlink(missing_ok=True)

    peaks: dict[int, int] = {}
    current_pid = None
    for line in result.stdout.splitlines():
        header = _FOOTPRINT_PROCESS_HEADER.match(line)
        if header:
            current_pid = int(header.group("pid"))
            continue
        peak = _FOOTPRINT_PEAK.search(line)
        if peak and current_pid is not None:
            peaks[current_pid] = int(peak.group("bytes"))

    per_process = [{"pid": p["pid"], "name": p["name"], "footprint_bytes": p["footprint"],
                    "peak_bytes": peaks.get(p["pid"])} for p in data.get("processes", [])]
    return {
        "current_bytes": data.get("total footprint", sum(p["footprint_bytes"] for p in per_process)),
        "peak_bytes": sum(p["peak_bytes"] for p in per_process if p["peak_bytes"] is not None) or None,
        "per_process": per_process,
    }


def all_boaz_pids(app_path: Path) -> list[int]:
    out = subprocess.run(["pgrep", "-f", str(app_path)], capture_output=True, text=True).stdout.split()
    return [int(p) for p in out]


def measure_memory(app_path: Path, run_root: Path) -> dict:
    results = {}
    for label, tabs in (("10_tabs", 10), ("150_tabs", 150)):
        home = run_root / "homes" / f"memory_{label}"
        seed_home(home, today_tabs=tabs)
        before, dev_prefs_backup = run_precheck_guards(app_path)
        pid = launch_app(app_path, home)
        try:
            time.sleep(30)  # let the process tree settle before sampling, per the Approach
            pids = all_boaz_pids(app_path)
            snapshot = footprint_snapshot(pids)
            results[label] = {"pid_count": len(pids), **snapshot}
            log(f"memory ({label}): {snapshot['current_bytes'] / 1e6:.1f} MB across {len(pids)} processes")
        finally:
            quit_app(app_path, pid)
            run_postcheck_guards(before, dev_prefs_backup)
    return results


# ---------------------------------------------------------------------------------------------------------------
# Prepare / orchestration
# ---------------------------------------------------------------------------------------------------------------

def cmd_prepare(args: argparse.Namespace) -> None:
    run_root = Path(args.run_dir)
    run_root.mkdir(parents=True, exist_ok=True)
    dmg_path = download_dmg(args.dmg_tag, DEFAULT_RUN_ROOT / ".cache")
    app_path = stage_isolated_copy(dmg_path, run_root)
    build_seed_tool()
    guard_no_other_dev_instance_running()
    guard_identity_is_dev(app_path)
    guard_entitlements_empty(app_path)
    log(f"prepared: {app_path}")
    print(json.dumps({"app": str(app_path), "run_dir": str(run_root)}))


def cmd_guard_check(args: argparse.Namespace) -> None:
    app_path = Path(args.app) if args.app else None
    guard_no_other_dev_instance_running()
    log(f"guard: no {DEV_BUNDLE_ID} process is running — OK")
    if app_path is not None:
        guard_identity_is_dev(app_path)
        log(f"guard: {app_path} is branded as {DEV_BUNDLE_ID} — OK")
        guard_entitlements_empty(app_path)
        log(f"guard: {app_path} carries no entitlements — OK")
    snapshot = snapshot_real_library()
    log(f"guard: real-library snapshot (read-only; defaults_sha256 is {PROD_BUNDLE_ID}'s, must stay unchanged "
        f"across a session) — {json.dumps(snapshot, sort_keys=True)}")
    print(json.dumps(snapshot, sort_keys=True))


def _require_app(run_root: Path) -> Path:
    app_path = run_root / "Boaz.app"
    if not app_path.exists():
        raise Abort(f"{app_path} doesn't exist — run `prepare` first")
    return app_path


def cmd_launch(args): print(json.dumps(measure_launch(_require_app(Path(args.run_dir)), Path(args.run_dir), args.n)))
def cmd_newtab(args): print(json.dumps(measure_newtab(_require_app(Path(args.run_dir)), Path(args.run_dir), args.n,
                                                       include_real_sites=not args.local_only)))
def cmd_typing(args): print(json.dumps(measure_typing(_require_app(Path(args.run_dir)), Path(args.run_dir), args.n)))
def cmd_tabs(args): print(json.dumps(measure_tabs(_require_app(Path(args.run_dir)), Path(args.run_dir), args.n)))
def cmd_archive(args): print(json.dumps(measure_archive(_require_app(Path(args.run_dir)), Path(args.run_dir), args.n)))
def cmd_memory(args): print(json.dumps(measure_memory(_require_app(Path(args.run_dir)), Path(args.run_dir))))


def render_markdown(build_label: str, results: dict) -> str:
    def fmt(row: dict | None, unit: str = "s") -> str:
        if not row:
            return "n/a"
        return f"{row['median']:.2f}{unit} (min {row['min']:.2f}, max {row['max']:.2f}, n={row['n']})"

    def fmt_memory(row: dict | None) -> str:
        if not row:
            return "n/a"
        current = row["current_bytes"] / 1e6
        peak = f"{row['peak_bytes'] / 1e6:.0f}" if row.get("peak_bytes") else "n/a"
        return f"{current:.0f} MB across {row['pid_count']} processes, peak {peak} MB"

    tabs = results.get("tabs", {})
    memory = results.get("memory", {})
    lines = [
        f"| What | How | {build_label} |",
        "|---|---|---|",
        f"| Launch to first window | Time from launch until the window is drawn, warm | {fmt(results.get('launch'))} |",
        f"| New tab to page title | ⌘T, type an address, Return, until the title shows | "
        f"local: {fmt(results.get('newtab', {}).get('local'))}; "
        f"real sites: {fmt(results.get('newtab', {}).get('real_sites'))} |",
        f"| Typing in the command bar with a large history | 50,000 seeded visits, ⌘L then type | "
        f"{fmt(results.get('typing'), unit='ms')} of main-thread time per keystroke |",
        f"| Many tabs | Open 150 tabs | first 10 median {tabs.get('first_10_median', 'n/a')}s, "
        f"last 10 median {tabs.get('last_10_median', 'n/a')}s |",
        f"| Archive Today's Tabs with 150+ tabs | Time until the sidebar settles | {fmt(results.get('archive'))} |",
        f"| Memory | `footprint` with 10 and with 150 tabs | "
        f"10 tabs: {fmt_memory(memory.get('10_tabs'))}; 150 tabs: {fmt_memory(memory.get('150_tabs'))} |",
    ]
    return "\n".join(lines)


def cmd_all(args: argparse.Namespace) -> None:
    run_root = Path(args.run_dir)
    cmd_prepare(args)
    app_path = _require_app(run_root)
    results = {
        "meta": {
            "dmg_tag": args.dmg_tag,
            "run_dir": str(run_root),
            "started_at": datetime.now(timezone.utc).isoformat(),
            "machine": machine_context(),
        },
        "launch": measure_launch(app_path, run_root, args.n),
        "newtab": measure_newtab(app_path, run_root, args.n, include_real_sites=not args.local_only),
        "typing": measure_typing(app_path, run_root, args.n),
        "tabs": measure_tabs(app_path, run_root, args.n),
        "archive": measure_archive(app_path, run_root, args.n),
        "memory": measure_memory(app_path, run_root),
    }
    out_json = run_root / "results.json"
    out_json.write_text(json.dumps(results, indent=2, sort_keys=True))
    build_label = f"Mac, Chromium DMG {args.dmg_tag}, {datetime.now().date().isoformat()}"
    markdown = render_markdown(build_label, results)
    out_md = run_root / "results.md"
    out_md.write_text(markdown + "\n")
    log(f"wrote {out_json} and {out_md}")
    print(markdown)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run-dir", default=str(DEFAULT_RUN_ROOT / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")),
                        help="Run directory (default: a fresh UTC-timestamped dir under ~/tmp/codex/boaz-perf)")
    sub = parser.add_subparsers(dest="command", required=True)

    def add(name: str, func, needs_n: bool = False, extra=None):
        p = sub.add_parser(name)
        if needs_n:
            p.add_argument("-N", "--n", type=int, default=7, help="samples after one discarded warm-up (default 7)")
        if extra:
            extra(p)
        p.set_defaults(func=func)
        return p

    prep = add("prepare", cmd_prepare)
    prep.add_argument("--dmg-tag", default="v0.4.48")

    check = add("guard-check", cmd_guard_check)
    check.add_argument("--app", default=None, help="optional staged .app to also check for empty entitlements")

    add("launch", cmd_launch, needs_n=True)
    newtab = add("newtab", cmd_newtab, needs_n=True)
    newtab.add_argument("--local-only", action="store_true", help="skip the 5-real-site sample")
    add("typing", cmd_typing, needs_n=True)
    add("tabs", cmd_tabs, needs_n=True)
    add("archive", cmd_archive, needs_n=True)
    add("memory", cmd_memory)

    all_p = add("all", cmd_all, needs_n=True)
    all_p.add_argument("--dmg-tag", default="v0.4.48")
    all_p.add_argument("--local-only", action="store_true")

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
