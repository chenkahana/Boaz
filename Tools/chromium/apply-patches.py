#!/usr/bin/env python3
"""Check pinned Chromium patches; --apply writes only through the SSD build guard."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
GIT = "/opt/homebrew/bin/git"


def fail(message):
    raise RuntimeError(message)


def canonical(path):
    if path.resolve() != path:
        fail(f"Redirected path: {path}")
    return path


def confined(root, relative):
    p = PurePosixPath(relative)
    if not relative or p.is_absolute() or str(p) != relative or any(
            part in (".", "..") for part in p.parts):
        fail(f"Noncanonical relative path: {relative!r}")
    return canonical(root / relative)


def regular(path):
    canonical(path)
    if not stat.S_ISREG(path.lstat().st_mode):
        fail(f"Not a regular file: {path}")
    return path


def digest(path):
    return hashlib.sha256(regular(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(regular(path).read_text())


def atomic(path, data, mode=0o600):
    canonical(path)
    temporary = path.with_name(path.name + ".transaction-" + uuid.uuid4().hex)
    with temporary.open("xb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, mode)
    os.replace(temporary, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def save(path, receipt):
    atomic(path, (json.dumps(receipt, indent=2) + "\n").encode())


def git_apply(stage, patch, check=False):
    args = [GIT, "apply", "--no-index", "--whitespace=error"]
    if check:
        args.append("--check")
    subprocess.run(args + [str(patch)], cwd=stage, check=True,
                   env={**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"})


def prepare(stage, source, patch, entry):
    stage.mkdir()
    for f in entry["files"]:
        original = confined(source, f["path"])
        if digest(original) != f["before"]:
            fail(f"Unexpected patch input: {original}")
        target = confined(stage, f["path"])
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
    git_apply(stage, patch, True)
    git_apply(stage, patch)
    expected = {f["path"] for f in entry["files"]}
    actual = {str(p.relative_to(stage)) for p in stage.rglob("*") if not p.is_dir()}
    if actual != expected:
        fail("Patch adds, removes, or changes unlisted files")
    for f in entry["files"]:
        if digest(confined(stage, f["path"])) != f["after"]:
            fail(f"Unexpected patch output: {f['path']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--guarded", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    lock = read_json(HERE / "source.lock.json")
    manifest = read_json(HERE / "patches.lock.json")
    if manifest["chromium_version"] != lock["chromium_version"]:
        fail("Patch/source version mismatch")
    root = canonical(Path(lock["storage_root"]))
    source = canonical(root / "chromium/src")
    version = dict(line.split("=", 1) for line in regular(source / "chrome/VERSION").read_text().splitlines())
    if ".".join(version[k] for k in ("MAJOR", "MINOR", "BUILD", "PATCH")) != lock["chromium_version"]:
        fail("Source VERSION differs from pin")
    entries = manifest["patches"]
    seen = set()
    for entry in entries:
        if set(entry) != {"file", "sha256", "files"} or entry["file"] in seen or not entry["files"]:
            fail("Invalid or duplicate patch entry")
        seen.add(entry["file"])
        patch = confined(HERE, entry["file"])
        if digest(patch) != entry["sha256"]:
            fail(f"Patch digest mismatch: {patch}")
        names = set()
        for f in entry["files"]:
            if set(f) != {"path", "before", "after"} or f["path"] in names:
                fail("Invalid or duplicate file entry")
            names.add(f["path"])
            confined(source, f["path"])
            if any(not re.fullmatch(r"[0-9a-f]{64}", f[k]) for k in ("before", "after")):
                fail("Invalid file digest")
        changes = subprocess.check_output([GIT, "apply", "--numstat", "-z", str(patch)])
        paths = set()
        for change in changes.split(b"\0"):
            if change:
                added, removed, name = change.decode().split("\t", 2)
                if not added.isdigit() or not removed.isdigit():
                    fail("Binary/renamed patch unsupported")
                paths.add(name)
        if paths != names or re.search(rb"^(new file mode|deleted file mode|rename |copy |old mode|new mode)", patch.read_bytes(), re.M):
            fail("Patch must modify only declared existing regular files")
    if args.apply and not args.guarded:
        return subprocess.call([lock["python"], str(HERE.parent / "cef/run-build.py"), "--",
                                lock["python"], str(Path(__file__).resolve()), "--apply", "--guarded"])
    if args.guarded:
        if not args.apply or Path.cwd() != root.parent or os.environ.get("TMPDIR") != str(root.parent / "tmp"):
            fail("Apply requires the verified SSD guard")
        with regular(root.parent / ".build.lock").open("r") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                fail("Build guard lock is not held")
    receipt_path = canonical(root / "patches-applied.json")
    receipt = read_json(receipt_path) if receipt_path.exists() else {
        "chromium_version": lock["chromium_version"], "applied": [], "pending": None}
    applied = receipt["applied"]
    if receipt["chromium_version"] != lock["chromium_version"] or applied != entries[:len(applied)] or len(applied) > len(entries):
        fail("Existing applied patch pins changed")
    pending = receipt["pending"]
    if pending and (len(applied) == len(entries) or pending["patch"] != entries[len(applied)]):
        fail("Pending transaction differs from next pinned patch")
    expected = {}
    for entry in applied:
        expected.update({f["path"]: {f["after"]} for f in entry["files"]})
    if pending:
        for f in pending["patch"]["files"]:
            expected[f["path"]] = {f["before"], f["after"]}
    for name, hashes in expected.items():
        if digest(confined(source, name)) not in hashes:
            fail(f"Previously applied source changed: {name}")
    if not args.apply:
        print(json.dumps({"applied": len(applied), "pending": pending is not None,
                          "remaining": len(entries) - len(applied), "source": str(source)}))
        if pending:
            print("Pending transaction needs guarded --apply; no files changed.")
            return 0
        # Internal temporary staging only; never writes into SSD source/history.
        with tempfile.TemporaryDirectory(prefix="boaz-patch-check-", dir="/tmp") as tmp:
            staged = Path(tmp) / "source"
            staged.mkdir()
            for entry in entries[len(applied):]:
                for f in entry["files"]:
                    target = confined(staged, f["path"])
                    if not target.exists():
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(regular(confined(source, f["path"])), target)
                output = Path(tmp) / uuid.uuid4().hex
                prepare(output, staged, confined(HERE, entry["file"]), entry)
                for f in entry["files"]:
                    shutil.copy2(output / f["path"], staged / f["path"])
        return 0
    history = canonical(root / "patch-history")
    history.mkdir(exist_ok=True)
    for entry in entries[len(applied):]:
        if pending is None:
            transaction = uuid.uuid4().hex
            directory = history / transaction
            directory.mkdir()
            prepare(directory / "staged", source, confined(HERE, entry["file"]), entry)
            for f in entry["files"]:
                backup = directory / "originals" / f["path"]
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(confined(source, f["path"]), backup)
            for saved in directory.rglob("*"):
                fd = os.open(saved, os.O_RDONLY)
                try:
                    os.fsync(fd)
                finally:
                    os.close(fd)
            for saved in (directory, history):
                fd = os.open(saved, os.O_RDONLY)
                try:
                    os.fsync(fd)
                finally:
                    os.close(fd)
            pending = {"id": transaction, "patch": entry}
            receipt["pending"] = pending
            save(receipt_path, receipt)
        if not re.fullmatch(r"[0-9a-f]{32}", pending["id"]):
            fail("Invalid transaction ID")
        directory = canonical(history / pending["id"])
        for f in entry["files"]:
            target = confined(source, f["path"])
            staged = confined(directory / "staged", f["path"])
            if digest(staged) != f["after"] or digest(confined(directory / "originals", f["path"])) != f["before"]:
                fail("Transaction history changed")
            current = digest(target)
            if current not in (f["before"], f["after"]):
                fail(f"Interrupted transaction source changed: {target}")
        # Check the complete transaction before replacing any source file.
        for f in entry["files"]:
            target = confined(source, f["path"])
            staged = confined(directory / "staged", f["path"])
            if digest(target) == f["before"]:
                atomic(target, staged.read_bytes(), stat.S_IMODE(target.stat().st_mode))
        receipt["applied"].append(entry)
        receipt["pending"] = None
        save(receipt_path, receipt)
        pending = None
    print(f"Verified {len(receipt['applied'])} applied patches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
