#!/usr/bin/env python3
"""Check or apply one pinned CEF patch without racing an owned build."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
import volume


def git(root, *args, check=True):
    return subprocess.run(["git", "-C", str(root), *args], check=check,
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("patch", type=Path)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--apply", action="store_true",
                        help="Apply after verification; default only checks")
    args = parser.parse_args()
    scripts = Path(__file__).resolve().parent
    patch = args.patch.resolve(strict=True)
    if patch.parent != scripts / "patches" or patch.suffix != ".patch":
        raise RuntimeError("Patch must be a checked-in Tools/cef/patches/*.patch file.")
    git(scripts, "ls-files", "--error-unmatch", str(patch))
    data = patch.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != args.sha256:
        raise RuntimeError("Patch checksum mismatch; no source changed.")
    volume.drive_info()
    volume.mounted_info()
    root = volume.MOUNT / "cef"
    source = root / "chromium_git/chromium/src/cef"
    config = json.loads((scripts / "custom-build.json").read_text())
    if source.resolve() != source or not (source / ".git").exists():
        raise RuntimeError("CEF source is missing or redirected.")
    revision = git(source, "rev-parse", "HEAD").stdout.strip()
    if revision != config["cef_commit"]:
        raise RuntimeError("CEF revision differs from the pinned patch base.")
    # Check-only reads are safe during compilation. Mutations share its lock.
    with (root / ".build.lock").open("a") as lock:
        if args.apply:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("Build active; patch application refused.")
        receipt = root / "fork.json"
        record = json.loads(receipt.read_text()) if receipt.exists() else {
            "cef_revision": revision, "patches": {}}
        if record["cef_revision"] != revision:
            raise RuntimeError("Existing fork receipt has a different revision.")
        result = git(source, "apply", "--check", str(patch), check=False)
        if result.returncode:
            reverse = git(source, "apply", "--reverse", "--check", str(patch), check=False)
            if reverse.returncode:
                raise RuntimeError("Patch conflicts; source preserved.\n" + result.stderr.strip())
            state = "already-applied"
        elif args.apply:
            git(source, "apply", str(patch))
            state = "applied"
        else:
            state = "applicable"
        if args.apply:
            record["patches"][patch.name] = digest
            temporary = receipt.with_suffix(".partial")
            with temporary.open("w") as output:
                json.dump(record, output, indent=2)
                output.flush()
                os.fsync(output.fileno())
            temporary.replace(receipt)
        print(json.dumps({"patch": patch.name, "sha256": digest,
                          "cef_revision": revision, "state": state}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"CEF patch stopped: {error}", file=sys.stderr)
        sys.exit(1)
