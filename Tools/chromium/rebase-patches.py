#!/opt/homebrew/bin/python3.12
"""Rebase the pinned patch series onto a freshly fetched, unpatched Chromium tree.

Applies the series in order to copies of the files it touches, never to the tree. Every patch that applies cleanly
gets new before/after hashes in patches.lock.json, and each file whose upstream content changed under it is listed
for review. Every patch that doesn't apply is listed and keeps its old entry, so apply-patches.py refuses it until it
is fixed. Fix the listed patches and run again: each run starts from the
unpatched tree. The lite archive has no .git, so there is no three-way merge.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
GIT = "/opt/homebrew/bin/git"
ENV = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def touched(patch, cwd):
    """The existing files a patch modifies; anything else (new, deleted, renamed, binary) is refused."""
    if re.search(rb"^(new file mode|deleted file mode|rename |copy |old mode|new mode)", patch.read_bytes(), re.M):
        raise ValueError(f"{patch.name} must only modify existing regular files")
    # Run outside any repository: inside one, git reports paths relative to its top level.
    output = subprocess.run([GIT, "apply", "--no-index", "--numstat", "-z", str(patch)], cwd=cwd, check=True,
                            env=ENV, capture_output=True).stdout
    paths = []
    for change in filter(None, output.split(b"\0")):
        added, removed, name = change.decode().split("\t", 2)
        if not added.isdigit() or not removed.isdigit():
            raise ValueError(f"{patch.name}: binary or renamed file {name}")
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or str(relative) != name:
            raise ValueError(f"{patch.name}: noncanonical path {name}")
        paths.append(name)
    return list(dict.fromkeys(paths))  # in patch order, as the lock lists them


def rebase(manifest, version, source, scripts, work, git=GIT):
    """Return the rewritten manifest, the conflicts and the files to review, without touching the source tree."""
    current = {}  # path -> contents after the patches applied so far
    entries, conflicts, review = [], [], []
    for index, entry in enumerate(manifest["patches"]):
        patch = scripts / entry["file"]
        stage = work / f"{index:03d}"
        stage.mkdir()
        files, missing = [], []
        for name in touched(patch, stage):
            original = source / name
            if name not in current and not original.is_file():
                missing.append(name)
                continue
            data = current[name] if name in current else original.read_bytes()
            (stage / name).parent.mkdir(parents=True, exist_ok=True)
            (stage / name).write_bytes(data)
            files.append({"path": name, "before": sha(data)})
        if missing:
            conflicts.append({"patch": entry["file"], "error": "missing in the new tree: " + ", ".join(missing)})
            entries.append(entry)
            continue
        result = subprocess.run([git, "apply", "--no-index", "--whitespace=error", str(patch)], cwd=stage, env=ENV,
                                capture_output=True, text=True)
        if result.returncode:
            conflicts.append({"patch": entry["file"], "error": result.stderr.strip()})
            entries.append(entry)
            continue
        for item in files:
            data = (stage / item["path"]).read_bytes()
            item["after"] = sha(data)
            current[item["path"]] = data
        entries.append({"file": entry["file"], "sha256": sha(patch.read_bytes()), "files": files})
        old = {item["path"]: item["before"] for item in entry["files"]}
        review += [{"patch": entry["file"], "path": item["path"]} for item in files
                   if old.get(item["path"]) != item["before"]]
    return {"chromium_version": version, "patches": entries}, conflicts, review


def guarded(lock, root, source):
    if Path.cwd() != root.parent or os.environ.get("TMPDIR") != str(root.parent / "tmp"):
        raise ValueError("Rebase must run through Tools/cef/run-build.py")
    with (root.parent / ".build.lock").open("r") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise ValueError("Volume guard is not holding its build lock")
    if os.path.lexists(root / "patches-applied.json"):
        raise ValueError("The source tree already has patches applied; rebase needs the unpatched tree")
    parts = dict(line.split("=", 1) for line in (source / "chrome/VERSION").read_text().splitlines() if "=" in line)
    if ".".join(parts[key] for key in ("MAJOR", "MINOR", "BUILD", "PATCH")) != lock["chromium_version"]:
        raise ValueError("Source VERSION differs from the source lock")
    path = HERE / "patches.lock.json"
    work_root = root / "tmp/patch-rebase"
    work_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work_root) as work:
        manifest, conflicts, review = rebase(json.loads(path.read_text()), lock["chromium_version"], source, HERE,
                                             Path(work))
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    # Review: patched files that changed upstream; the patch still applied, but check it still means the same thing.
    print(json.dumps({"patches": len(manifest["patches"]), "conflicts": conflicts, "review": review}, indent=2))
    return 1 if conflicts else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--rebase", action="store_true", help="Rebase under the volume guard and rewrite the lock")
    modes.add_argument("--guarded", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    lock = json.loads((HERE / "source.lock.json").read_text())
    root = Path(lock["storage_root"])
    source = root / "chromium/src"
    command = [lock["python"], str(HERE.parent / "cef/run-build.py"), "--",
               lock["python"], str(Path(__file__).resolve()), "--guarded"]
    if args.guarded:
        return guarded(lock, root, source)
    if args.rebase:
        return subprocess.call(command)
    print(json.dumps({"version": lock["chromium_version"], "source": str(source), "command": command}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Patch rebase stopped; the source tree is unchanged: {error}", file=sys.stderr)
        sys.exit(1)
