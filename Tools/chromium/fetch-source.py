#!/opt/homebrew/bin/python3.12
"""Fetch verified Chromium source through Boaz's existing volume guard."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import urllib.parse
import urllib.request

LOCK = Path(__file__).with_name("source.lock.json")
GUARD = Path(__file__).resolve().parents[1] / "cef/run-build.py"
MAX_ARCHIVE_BYTES = 8 * 1024**3


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        if urllib.parse.urlsplit(url).scheme != "https":
            raise ValueError("Refusing non-HTTPS redirect")
        return super().redirect_request(request, response, code, message, headers, url)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def confined(path):
    if path.resolve() != path:
        raise ValueError(f"Storage path contains a symlink: {path}")


def download(lock, archive):
    if archive.exists():
        if not archive.is_file():
            raise ValueError(f"Archive is not a regular file: {archive}")
    else:
        partial = archive.with_name(archive.name + ".partial")
        with partial.open("xb") as output:
            opener = urllib.request.build_opener(HTTPSOnly())
            with opener.open(lock["archive_url"], timeout=60) as response:
                if int(response.headers.get("Content-Length", "0")) > MAX_ARCHIVE_BYTES:
                    raise ValueError("Archive exceeds 8 GiB download ceiling")
                size = 0
                while block := response.read(1024 * 1024):
                    size += len(block)
                    if size > MAX_ARCHIVE_BYTES:
                        raise ValueError("Archive exceeds 8 GiB download ceiling")
                    output.write(block)
            output.flush()
            os.fsync(output.fileno())
        if digest(partial) != lock["archive_sha256"]:
            raise ValueError(f"SHA256 mismatch; preserving {partial}")
        os.link(partial, archive)
        partial.unlink()
    if digest(archive) != lock["archive_sha256"]:
        raise ValueError(f"SHA256 mismatch; preserving {archive}")


def extract(lock, archive, stage, destination):
    stage.mkdir()
    expected = lock["archive_root"]
    seen = set()
    with tarfile.open(archive, "r|xz") as bundle:
        for member in bundle:
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or not name.parts or name.parts[0] != expected:
                raise ValueError(f"Unexpected archive path: {member.name}")
            if not (member.isdir() or member.isfile() or member.issym() or member.islnk()):
                raise ValueError(f"Unsupported archive entry: {member.name}")
            if str(name) in seen:
                raise ValueError(f"Duplicate archive entry: {member.name}")
            seen.add(str(name))
            if member.issym() or member.islnk():
                target = PurePosixPath(member.linkname)
                if target.is_absolute():
                    raise ValueError(f"Absolute archive link: {member.name}")
                base = stage / name.parent if member.issym() else stage
                resolved = (base / member.linkname).resolve()
                if not resolved.is_relative_to(stage / expected):
                    raise ValueError(f"Escaping archive link: {member.name}")
                if member.islnk() and not resolved.is_file():
                    raise ValueError(f"Hard link target must precede link: {member.name}")
            bundle.extract(member, stage, filter="data")
    source = stage / expected
    if not (source / "chrome/VERSION").is_file():
        raise ValueError("Extracted source lacks chrome/VERSION")
    parts = dict(line.split("=", 1) for line in (source / "chrome/VERSION").read_text().splitlines() if "=" in line)
    version = ".".join(parts[key] for key in ("MAJOR", "MINOR", "BUILD", "PATCH"))
    if version != lock["chromium_version"]:
        raise ValueError(f"Unexpected extracted version: {version}")
    if os.path.lexists(destination):
        raise ValueError(f"Destination appeared during extraction: {destination}")
    source.rename(destination)
    stage.rmdir()


def guarded_fetch(lock, root, archive, destination):
    if Path.cwd() != root.parent or os.environ.get("TMPDIR") != str(root.parent / "tmp"):
        raise ValueError("Internal stage must run through Tools/cef/run-build.py")
    with (root.parent / ".build.lock").open("r") as guard_lock:
        try:
            fcntl.flock(guard_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise ValueError("Volume guard is not holding its build lock")
    stage = destination.with_name("src.extracting")
    for path in (root, archive.parent, archive, destination.parent, destination, stage):
        confined(path)
    if os.path.lexists(destination) or os.path.lexists(stage):
        raise ValueError("Source or extraction stage already exists; preserving it")
    archive.parent.mkdir(parents=True, exist_ok=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"Fetching {lock['archive_url']}", flush=True)
    download(lock, archive)
    print(f"Verified SHA256; extracting into {stage}", flush=True)
    extract(lock, archive, stage, destination)
    print(f"Verified Chromium {lock['chromium_version']} source: {destination}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--dry-run", action="store_true", help="Print paths and guarded command; no changes")
    actions.add_argument("--fetch", action="store_true", help="Run download and extraction under the volume guard")
    actions.add_argument("--guarded", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    root = Path(lock["storage_root"])
    archive = root / "downloads" / lock["archive_name"]
    destination = root / "chromium/src"
    command = [lock["python"], str(GUARD), "--", lock["python"], str(Path(__file__).resolve()), "--guarded"]
    if args.guarded:
        guarded_fetch(lock, root, archive, destination)
    elif args.fetch:
        return subprocess.call(command)
    else:
        print(json.dumps({"version": lock["chromium_version"], "archive": str(archive),
                          "source": str(destination), "sha256": lock["archive_sha256"],
                          "archiveExists": archive.exists(), "sourceExists": destination.exists(),
                          "command": command}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print(f"Source preparation stopped; existing files preserved: {error}", file=sys.stderr)
        sys.exit(1)
