#!/usr/bin/env python3
"""Tools/perf/perf.py — docs/qa.md §4 baselines (PLAN-04).

Re-measures every §4 row against the *published* Boaz DMG, on an isolated, ad-hoc re-signed copy with no
entitlements, run under a throwaway HOME. Never touches the installed Boaz or Chen's real library (must-have #13):
see `run_precheck_guards` / `run_postcheck_guards` below, which abort the whole run rather than risk it.

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

BUNDLE_ID = "com.chenkahana.boaz"
PROBE_DOMAIN = "com.chenkahana.perfprobe"
DEFAULT_RUN_ROOT = Path.home() / "tmp" / "codex" / "boaz-perf"
REAL_WATCHED_DIRS = [
    Path.home() / "Library" / "Application Support" / "Boaz",
    Path.home() / "Library" / "Containers" / BUNDLE_ID,
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

def guard_app_not_running(perf_copy: Path | None) -> None:
    """Aborts if any *macOS* process other than our own perf copy is running the real executable. Matched by
    resolved executable path, never by bundle id (the copy keeps the real bundle id on purpose; see the Approach).

    `pgrep -x Boaz` also matches an iOS Simulator build of Boaz (confirmed live while writing this guard: a
    Simulator app bundle is flat, `Boaz.app/Boaz`, with no `Contents/MacOS`) — that process can't reach
    ~/Library/Application Support/Boaz at all, so it isn't the thing must-have #13 cares about. Only a path ending
    in `.app/Contents/MacOS/Boaz` — an actual macOS bundle — counts as a candidate "real Boaz" here."""
    own_exe = None
    if perf_copy is not None:
        candidate = perf_copy / "Contents" / "MacOS" / "Boaz"
        if candidate.exists():
            own_exe = str(candidate.resolve())
    pids = subprocess.run(["pgrep", "-x", "Boaz"], capture_output=True, text=True).stdout.split()
    for pid in pids:
        exe = subprocess.run(["ps", "-o", "comm=", "-p", pid], capture_output=True, text=True).stdout.strip()
        try:
            resolved = str(Path(exe).resolve())
        except OSError:
            resolved = exe
        if not resolved.endswith(".app/Contents/MacOS/Boaz"):
            continue  # not a macOS app bundle executable (e.g. an iOS Simulator build) — not our concern here
        if own_exe is not None and resolved == own_exe:
            continue
        raise Abort(f"a Mac Boaz process is already running (pid {pid}, {resolved}) — "
                    "quit Chen's Boaz before a perf session; same bundle id means `open` could reach his copy")


def guard_entitlements_empty(app_path: Path) -> None:
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", str(app_path)],
                             capture_output=True, text=True)
    if "<key>" in result.stdout or "<key>" in result.stderr:
        raise Abort(f"{app_path} still carries entitlements — the perf copy must be re-signed with none")


def cfprefsd_probe() -> None:
    """Guard #1 from the Approach: writes a throwaway domain under a fixed HOME and checks cfprefsd actually
    confined it there, using a domain ('com.chenkahana.perfprobe') nothing else reads.

    Confirmed live on this host (2026-11-26, macOS 26) while writing this guard: a plain `defaults write` with
    both HOME and CFFIXED_USER_HOME set to a throwaway directory still landed in the REAL
    ~/Library/Preferences — cfprefsd resolves an unsandboxed client's home from its real UID, not from its
    environment. So this guard currently ABORTS every run on this host, which is correct: it means
    `defaults write`/NSUserDefaults is not isolated by HOME alone, and nothing in this harness may write to the
    real `com.chenkahana.boaz` defaults domain (see `launch_app`, which passes everything as launch arguments —
    NSArgumentDomain, never persisted — instead of pre-writing with `defaults write`). Don't weaken this guard to
    make a run proceed; it is the thing standing between a perf session and Chen's real Boaz preferences. Fixing
    it for real needs either re-verifying on the actual run host, or confining the launched copy with
    `sandbox-exec` run directly on its executable (bypassing LaunchServices) — out of scope for this change; flag
    it to the architect/orchestrator before a live session.

    Cleans up both the fixed-home and (if it leaked) the real-home copies by deleting the files directly: a
    `defaults delete` immediately after a `defaults write` raced against cfprefsd's own cache while writing this
    (it reported the domain as already gone while the plist was still on disk), so direct unlink is the only
    cleanup actually confirmed to leave no trace.
    """
    probe_home = DEFAULT_RUN_ROOT / ".probe"
    probe_home.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, HOME=str(probe_home), CFFIXED_USER_HOME=str(probe_home))
    probed = probe_home / "Library" / "Preferences" / f"{PROBE_DOMAIN}.plist"
    leaked = Path.home() / "Library" / "Preferences" / f"{PROBE_DOMAIN}.plist"
    try:
        subprocess.run(["defaults", "write", PROBE_DOMAIN, "k", "-bool", "true"],
                        env=env, check=True, capture_output=True)
        if not probed.exists():
            raise Abort("cfprefsd did not honor CFFIXED_USER_HOME — the probe default never landed under the fixed home")
        if leaked.exists():
            raise Abort("cfprefsd wrote the probe default into the real HOME too — isolation is unsound")
    finally:
        probed.unlink(missing_ok=True)
        leaked.unlink(missing_ok=True)


def snapshot_real_library() -> dict:
    """Cheap, read-only fingerprint of Chen's real library: file count / total bytes / latest mtime per watched
    directory (not a full content hash — these can hold gigabytes of Chromium cache), plus the real app's defaults
    domain. Compared before and after every row; any difference aborts the harness immediately."""
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
    exported = subprocess.run(["defaults", "export", BUNDLE_ID, "-"], capture_output=True)
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


def run_precheck_guards(perf_copy: Path | None) -> dict:
    guard_app_not_running(perf_copy)
    if perf_copy is not None:
        guard_entitlements_empty(perf_copy)
    cfprefsd_probe()
    return snapshot_real_library()


def run_postcheck_guards(before: dict) -> None:
    guard_app_not_running(None)
    guard_library_untouched(before, snapshot_real_library())


# ---------------------------------------------------------------------------------------------------------------
# Isolation: download + verify the published DMG, stage an ad-hoc re-signed, empty-entitlement copy.
# ---------------------------------------------------------------------------------------------------------------

def read_bundle_id(app_path: Path) -> str:
    with (app_path / "Contents" / "Info.plist").open("rb") as handle:
        return plistlib.load(handle).get("CFBundleIdentifier", "")


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
    """Ad-hoc re-signs a fresh copy of the DMG's app with no entitlements and no hardened runtime, keeping the
    bundle id (launch.mm's native-host path CHECKs it's com.chenkahana.boaz). CloudKitEntitlements then reports
    this process as unsigned for iCloud, so sync stays idle for the whole session."""
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
    if read_bundle_id(app_path) != BUNDLE_ID:
        raise Abort(f"staged app's bundle id is not {BUNDLE_ID!r}; refusing to sign and launch it")
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app_path)], check=True, capture_output=True)
    guard_entitlements_empty(app_path)
    if read_bundle_id(app_path) != BUNDLE_ID:
        raise Abort("re-signing changed the bundle id — launch.mm's CHECK would abort the app at launch")
    log(f"staged isolated copy at {app_path}, ad-hoc signed, no entitlements")
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
    args = [str(seed_bin), "--home", str(home), "--space-title", space_title, "--verify"]
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
    return home / "Library" / "Application Support" / "Boaz" / "Chromium" / "Automation"


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
    persisted to a plist), never as a `defaults write` against the real `com.chenkahana.boaz` domain — see
    `cfprefsd_probe`'s note on why a prior write landed in Chen's real ~/Library/Preferences regardless of HOME."""
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
    exe = app_path / "Contents" / "MacOS" / "Boaz"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for pid in subprocess.run(["pgrep", "-x", "Boaz"], capture_output=True, text=True).stdout.split():
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
        before = run_precheck_guards(app_path)
        t0 = time.monotonic()
        pid = launch_app(app_path, home)
        result = subprocess.run(["swift", str(WINDOW_WAIT), str(pid), "30"], capture_output=True, text=True)
        elapsed = time.monotonic() - t0
        if result.returncode != 0:
            raise Abort(f"launch sample {i}: {result.stderr.strip()}")
        samples.append(elapsed)
        quit_app(app_path, pid)
        run_postcheck_guards(before)
        log(f"launch sample {i}: {elapsed:.3f}s")
    return summarize(samples)


def measure_newtab(app_path: Path, run_root: Path, n: int, *, include_real_sites: bool) -> dict:
    home = run_root / "homes" / "newtab"
    seed_home(home, today_tabs=10)
    before = run_precheck_guards(app_path)
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
        run_postcheck_guards(before)
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
    before = run_precheck_guards(app_path)
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
        run_postcheck_guards(before)
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
    before = run_precheck_guards(app_path)
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
        run_postcheck_guards(before)
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
        before = run_precheck_guards(app_path)
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
            run_postcheck_guards(before)
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
        before = run_precheck_guards(app_path)
        pid = launch_app(app_path, home)
        try:
            time.sleep(30)  # let the process tree settle before sampling, per the Approach
            pids = all_boaz_pids(app_path)
            snapshot = footprint_snapshot(pids)
            results[label] = {"pid_count": len(pids), **snapshot}
            log(f"memory ({label}): {snapshot['current_bytes'] / 1e6:.1f} MB across {len(pids)} processes")
        finally:
            quit_app(app_path, pid)
            run_postcheck_guards(before)
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
    guard_app_not_running(app_path)
    guard_entitlements_empty(app_path)
    log(f"prepared: {app_path}")
    print(json.dumps({"app": str(app_path), "run_dir": str(run_root)}))


def cmd_guard_check(args: argparse.Namespace) -> None:
    app_path = Path(args.app) if args.app else None
    guard_app_not_running(app_path)
    log("guard: no other Boaz process is running — OK")
    if app_path is not None:
        guard_entitlements_empty(app_path)
        log(f"guard: {app_path} carries no entitlements — OK")
    cfprefsd_probe()
    log("guard: cfprefsd honors CFFIXED_USER_HOME and didn't leak to the real HOME — OK")
    snapshot = snapshot_real_library()
    log(f"guard: real-library snapshot (read-only) — {json.dumps(snapshot, sort_keys=True)}")
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
