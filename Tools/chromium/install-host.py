#!/opt/homebrew/bin/python3.12
"""Stage Boaz-authored host sources without changing upstream files."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


def inventory(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"Host source must not contain symlinks: {path}")
        if path.is_file():
            result[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--guarded", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    scripts = Path(__file__).resolve().parent
    lock = json.loads((scripts / "source.lock.json").read_text())
    root = Path(lock["storage_root"])
    destination = root / "chromium/src/boaz"
    contents = inventory(scripts / "host")
    required = {"BUILD.gn", "boaz_host.h", "bootstrap.h", "bootstrap.mm", "native_view.mm", "native_window.h",
                "native_window.mm", "native_location_bar.h", "native_location_bar.mm",
                "native_permission_prompt.h", "native_permission_prompt.mm",
                "extension_actions.h", "extension_actions.mm",
                "extension_popup.h", "extension_popup.mm",
                "password_submission.h", "password_submission.cc",
                "trusted_script_channel.h", "trusted_script_channel.cc",
                "tab_registry.h", "tab_registry.cc", "trusted_execution.h", "trusted_execution.cc"}
    if not required.issubset(contents):
        raise RuntimeError("Host packet is incomplete; integrate its implementation first.")
    if not args.install:
        print(json.dumps({"destination": str(destination), "files": contents}, indent=2))
        return 0
    if not args.guarded:
        return subprocess.call([lock["python"], str(scripts.parent / "cef/run-build.py"),
                                "--", lock["python"], str(Path(__file__).resolve()),
                                "--install", "--guarded"])
    if Path.cwd() != root.parent or os.environ.get("TMPDIR") != str(root.parent / "tmp"):
        raise RuntimeError("Host installation requires the verified SSD guard.")
    with (root.parent / ".build.lock").open("r") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError("Build guard lock is not held.")
    history = root / "host-history"
    for path in (root, destination, history):
        if path.resolve() != path:
            raise RuntimeError(f"Host storage is redirected: {path}")
    version = dict(line.split("=", 1) for line in
                   (destination.parent / "chrome/VERSION").read_text().splitlines())
    if ".".join(version[key] for key in ("MAJOR", "MINOR", "BUILD", "PATCH")) != lock["chromium_version"]:
        raise RuntimeError("Host source version differs from the pinned archive.")
    receipt = root / "host-installed.json"
    if destination.exists():
        prior = json.loads(receipt.read_text()) if receipt.exists() else None
        if prior is None or inventory(destination) != prior["files"]:
            raise RuntimeError("Existing host source differs from its receipt; preserved.")
        if prior["files"] == contents:
            print("Host sources already match the repository.")
            return 0
    history.mkdir(exist_ok=True)
    token = uuid.uuid4().hex
    stage = history / (token + ".staged")
    shutil.copytree(scripts / "host", stage)
    if inventory(stage) != contents:
        raise RuntimeError("Staged host source failed integrity verification.")
    if destination.exists():
        backup = history / (token + ".previous")
        destination.rename(backup)
        print(f"Preserved previous host source: {backup}")
    stage.rename(destination)
    record = {"chromium_version": lock["chromium_version"], "files": contents}
    temporary = history / (token + ".receipt.json")
    with temporary.open("x") as stream:
        json.dump(record, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(receipt)
    print(f"Installed {len(contents)} Boaz host source files.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Host installation stopped; source preserved: {error}", file=sys.stderr)
        sys.exit(1)
