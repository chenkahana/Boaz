#!/opt/homebrew/bin/python3.12
"""Move Boaz's Chromium to a new upstream version on the build Mac: bump, fetch, rebase, build, pack.

Runs the build-Mac steps of docs/chromium/security-update.md in order and stops at the first failure. Each run
writes a timing receipt to build/security-update/. After fixing a failure, continue with --from STEP.
"""
import argparse
import datetime
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SOURCE_LOCK = HERE / "source.lock.json"
ARCHIVES = "https://commondatastorage.googleapis.com/chromium-browser-official/"
# Committed with the bump so chromium-base.py can key and pack the build.
PINS = ["Tools/chromium/source.lock.json", "Tools/chromium/patches.lock.json", "Tools/chromium/patches"]


def version_key(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,10}(?:\.[0-9]{1,10}){3}", value):
        raise ValueError(f"Not a four-part Chromium version: {value!r}")
    return tuple(map(int, value.split(".")))


def bumped(lock, version, sha256):
    """The source lock pinned to another official lite archive."""
    if version_key(version) <= version_key(lock["chromium_version"]):
        # Chromium profiles don't downgrade (must-have 13), so never pin an older Chromium than users have.
        raise ValueError(f"{version} is not newer than the pinned {lock['chromium_version']}")
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise ValueError("Invalid archive SHA-256")
    name = f"chromium-{version}-lite.tar.xz"
    return {**lock, "chromium_version": version, "archive_url": ARCHIVES + name, "archive_name": name,
            "archive_sha256": sha256, "archive_root": f"chromium-{version}"}


def parse_hashes(text, name):
    """The SHA-256 line for NAME in Google's published .hashes file."""
    for line in text.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0] == "sha256" and fields[2] == name:
            return fields[1].lower()
    raise ValueError(f"No SHA-256 for {name} in the published hashes")


def published_sha256(version):
    name = f"chromium-{version}-lite.tar.xz"
    url = ARCHIVES + name + ".hashes"
    with urllib.request.urlopen(url, timeout=20) as response:
        parsed = urllib.parse.urlsplit(response.url)
        if parsed.scheme != "https" or parsed.hostname != "commondatastorage.googleapis.com":
            raise ValueError("Hashes redirected off Google's archive host")
        return parse_hashes(response.read(65536).decode(), name)


def bump(args):
    lock = json.loads(SOURCE_LOCK.read_text())
    if lock["chromium_version"] == args.version:
        print(f"Source lock already pins {args.version}")
        return
    sha256 = args.sha256 or published_sha256(args.version)
    SOURCE_LOCK.write_text(json.dumps(bumped(lock, args.version, sha256), indent=2) + "\n")
    print(f"Pinned {args.version} ({sha256})")


def git(*arguments, capture=False):
    result = subprocess.run(["git", "-C", str(REPO), *arguments], check=True, text=True,
                            capture_output=capture)
    return result.stdout if capture else None


def commit(args):
    branch = git("branch", "--show-current", capture=True).strip()
    if branch in ("", "master", "main"):
        raise ValueError(f"Commit the pins on a working branch, not {branch or 'a detached HEAD'}")
    git("add", "--", *PINS)
    if git("diff", "--cached", "--name-only", "--", *PINS, capture=True).strip():
        git("commit", "-m", f"Chromium {args.version}: source and patch pins", "--", *PINS)
    spec = importlib.util.spec_from_file_location("chromium_base", HERE / "chromium-base.py")
    base = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(base)
    if git("status", "--porcelain", "--", *base.INPUTS, capture=True):
        raise ValueError("Other Chromium inputs have uncommitted changes; chromium-base.py would refuse to pack")


def plan(python, jobs):
    """(id, runbook step, owner, action): an action is a command or one of this script's functions."""
    tool = lambda name, *rest: [python, str(HERE / name), *rest]
    return [
        ("bump", "B", "dev", bump),
        ("fetch", "F", "build Mac", tool("fetch-source.py", "--fetch")),
        ("toolchains-check", "F", "build Mac", tool("prepare-toolchains.py", "--check-deps")),
        ("rebase", "P", "dev", tool("rebase-patches.py", "--rebase")),
        ("commit", "P", "dev", commit),
        ("apply", "C", "build Mac", tool("apply-patches.py", "--apply")),
        ("toolchains", "C", "build Mac", tool("prepare-toolchains.py", "--prepare")),
        ("objdump", "C", "build Mac", tool("prepare-objdump.py", "--prepare")),
        ("host", "C", "build Mac", tool("install-host.py", "--install")),
        ("build", "C", "build Mac", tool("build.py", "--build", "--jobs", str(jobs))),
        ("pack", "C", "build Mac", tool("chromium-base.py", "pack", "--upload")),
    ]


def describe(action):
    return " ".join(action) if isinstance(action, list) else f"(security-update.py {action.__name__})"


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def run(steps, args, receipt, save, clock=time.monotonic, stamp=now):
    """Run steps in order, saving the receipt after each; stop at the first nonzero exit."""
    for step, letter, owner, action in steps:
        print(f"== {letter} {step}: {describe(action)}", flush=True)
        started, begin = stamp(), clock()
        try:
            code = subprocess.call(action, cwd=REPO) if isinstance(action, list) else action(args) or 0
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
            print(f"{step}: {error}", file=sys.stderr)
            code = 1
        receipt["steps"].append({"id": step, "runbook": letter, "owner": owner, "action": describe(action),
                                 "started": started, "ended": stamp(), "seconds": round(clock() - begin, 1),
                                 "exit": code})
        if code:
            receipt["status"] = "failed"
            break
        save(receipt)
    else:
        receipt["status"] = "ok"
    receipt["ended"] = stamp()
    save(receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("version", help="Upstream Chromium version, for example 159.0.8154.40")
    parser.add_argument("--from", dest="start", help="Skip the steps before this one")
    parser.add_argument("--jobs", type=int, default=6, help="Ninja jobs; memory pressure caps the build Mac at 6-8")
    parser.add_argument("--sha256", help="Archive SHA-256, instead of reading Google's published .hashes")
    parser.add_argument("--dry-run", action="store_true", help="Print the plan and change nothing")
    args = parser.parse_args()
    version_key(args.version)
    lock = json.loads(SOURCE_LOCK.read_text())
    steps = plan(lock["python"], args.jobs)
    ids = [step[0] for step in steps]
    if args.start:
        if args.start not in ids:
            parser.error(f"--from must be one of: {', '.join(ids)}")
        steps = steps[ids.index(args.start):]
    if args.dry_run:
        for step, letter, owner, action in steps:
            print(f"{letter}  {step:<17} {owner:<10} {describe(action)}")
        return 0
    receipt = {"version": args.version, "pinned_before": lock["chromium_version"], "started": now(),
               "ended": None, "status": "running", "steps": []}
    path = REPO / "build/security-update" / f"{args.version}-{receipt['started'].replace(':', '')}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    run(steps, args, receipt, lambda value: path.write_text(json.dumps(value, indent=2) + "\n"))
    print(f"Receipt: {path}")
    if receipt["status"] != "ok":
        failed = receipt["steps"][-1]["id"]
        print(f"Stopped at {failed}. Fix it, then: security-update.py {args.version} --from {failed}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
