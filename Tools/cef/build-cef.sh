#!/bin/bash
set -euo pipefail
exec python3 - "$(cd "$(dirname "$0")" && pwd)" "$@" <<'PY'
import argparse
import json
import multiprocessing
import os
from pathlib import Path
import shlex
import subprocess
import sys

scripts = Path(sys.argv[1])
parser = argparse.ArgumentParser(description="Build pinned arm64 CEF on the verified APFS image.")
parser.add_argument("--dry-run", action="store_true", help="Print configuration without downloads, writes, or mounting")
parser.add_argument("--smoke", action="store_true", help="Build cefsimple only; do not package a distribution")
parser.add_argument("--jobs", type=int, default=12, help="Local Ninja concurrency, from 1 to 12 (default: 12)")
args = parser.parse_args(sys.argv[2:])
if not 1 <= args.jobs <= 12:
    parser.error("--jobs must be an integer from 1 to 12")

config = json.loads((scripts / "custom-build.json").read_text())
root = Path("/Volumes/BoazBuild/cef")
automate = root / "automate-git.py"
gn = " ".join(key + "=" + (str(value).lower() if isinstance(value, bool) else str(value))
              for key, value in config["gn_args"].items())
env = dict(os.environ, GN_DEFINES=gn,
           NINJA_CORE_ADDITION=str(args.jobs - multiprocessing.cpu_count()),
           CIPD_CACHE_DIR=str(root / "cache/cipd"),
           VPYTHON_VIRTUALENV_ROOT=str(root / "cache/vpython"))
command = [sys.executable, str(automate),
           "--download-dir=" + str(root / "chromium_git"),
           "--depot-tools-dir=" + str(root / "depot_tools"),
           "--branch=" + config["cef_branch"],
           "--checkout=" + config["cef_commit"],
           "--chromium-checkout=" + config["chromium_checkout"],
           "--arm64-build", "--no-debug-build", "--force-build", "--build-log-file"]
if args.smoke:
    command += ["--build-target=cefsimple", "--no-distrib"]
else:
    command += ["--build-target=cefclient", "--minimal-distrib-only",
                "--no-distrib-symbols", "--no-distrib-docs"]

if args.dry_run:
    print("Build root:", root)
    print("CEF commit:", config["cef_commit"])
    print("depot_tools commit from CEF compatibility:", config["depot_tools_commit"])
    print("Verified script download:", config["automate_url"])
    print("Script SHA-256:", config["automate_sha256"])
    for key in ("GN_DEFINES", "NINJA_CORE_ADDITION", "CIPD_CACHE_DIR", "VPYTHON_VIRTUALENV_ROOT"):
        print(key + "=" + shlex.quote(env[key]))
    print("Guard:", scripts / "run-build.py")
    print(shlex.join(command))
    sys.exit(0)

runner = scripts / "run-build.py"
if not runner.is_file():
    sys.exit("Missing run-build.py: integrate the verified-volume build runner before building CEF.")

# Preparation runs inside the volume/capacity/process-group guard, before exec.
stage = r'''
import ast
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.parse
import urllib.request

config = json.loads(sys.argv[1])
command = json.loads(sys.argv[2])
root = Path("/Volumes/BoazBuild/cef")
if Path.cwd() != root or root.is_symlink():
    sys.exit("Build stage is not running inside the expected verified volume.")
for relative in ("chromium_git", "depot_tools", "cache", "cache/cipd", "cache/vpython"):
    path = root / relative
    if path.is_symlink():
        sys.exit("Refusing redirected build path: " + str(path))
    if relative.startswith("cache"):
        path.mkdir(parents=True, exist_ok=True)

def download(url):
    if urllib.parse.urlparse(url).scheme != "https":
        raise ValueError("Build source URL must use HTTPS")
    with urllib.request.urlopen(url, timeout=60) as response:
        if urllib.parse.urlparse(response.url).scheme != "https":
            raise ValueError("Build source redirected away from HTTPS")
        data = response.read(2 * 1024 * 1024 + 1)
        if len(data) > 2 * 1024 * 1024:
            raise ValueError("Unexpectedly large build source")
        return data

compatibility = ast.literal_eval(download(config["compatibility_url"]).decode())
if (compatibility["chromium_checkout"] != config["chromium_checkout"]
        or compatibility["depot_tools_checkout"] != config["depot_tools_commit"]):
    sys.exit("Pinned CEF compatibility does not match custom-build.json.")

script = root / "automate-git.py"
if script.is_symlink():
    sys.exit("Refusing a symlink for automate-git.py.")
data = script.read_bytes() if script.exists() else download(config["automate_url"])
if hashlib.sha256(data).hexdigest() != config["automate_sha256"]:
    sys.exit("automate-git.py checksum mismatch; existing file preserved.")
if not script.exists():
    with tempfile.NamedTemporaryFile(dir=root, prefix="automate-", suffix=".partial", delete=False) as output:
        partial = Path(output.name)
        try:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
            # Exclusive creation avoids replacing a file created concurrently.
            os.link(partial, script)
        finally:
            partial.unlink(missing_ok=True)
os.execve(command[0], command, os.environ)
'''
sys.exit(subprocess.call([sys.executable, str(runner), "--", sys.executable, "-c", stage,
                          json.dumps(config), json.dumps(command)], env=env))
PY
