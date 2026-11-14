#!/usr/bin/env python3
"""Fetch the pinned prebuilt CEF distribution for feasibility experiments."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[2]


def verify(archive, lock):
    sha1, sha256 = hashlib.sha1(), hashlib.sha256()
    size = 0
    with archive.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            size += len(block)
            sha1.update(block)
            sha256.update(block)
    if (size != lock["size_bytes"] or sha1.hexdigest() != lock["published_sha1"]
            or sha256.hexdigest() != lock["sha256"]):
        raise ValueError("CEF archive does not match the pinned size and checksums: " + str(archive))


def inside(path, root):
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("Archive entry escapes its distribution directory: " + str(path))


def extract(archive, staging, directory):
    destination = staging / directory
    seen = set()
    with tarfile.open(archive, "r|bz2") as source:
        for member in source:
            name = PurePosixPath(member.name)
            if (name.is_absolute() or ".." in name.parts or not name.parts
                    or name.parts[0] != directory or member.name in seen):
                raise ValueError("Unsafe or duplicate archive path: " + member.name)
            seen.add(member.name)
            target = staging.joinpath(*name.parts)
            inside(target, destination)
            if not (member.isdir() or member.isfile() or member.issym() or member.islnk()):
                raise ValueError("Unsupported archive entry: " + member.name)
            if member.issym() or member.islnk():
                link = PurePosixPath(member.linkname)
                if link.is_absolute():
                    raise ValueError("Absolute archive link: " + member.name)
                link_target = (target.parent if member.issym() else staging).joinpath(*link.parts)
                inside(link_target, destination)
                if member.islnk() and (not link_target.is_file() or link_target.is_symlink()):
                    raise ValueError("Hard link must reference an extracted regular file: " + member.name)
            member.mode &= 0o777
            source.extract(member, path=staging)
    if not (destination / "include/cef_app.h").is_file():
        raise ValueError("Archive is missing the expected CEF headers")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use an existing archive without downloading or modifying it")
    parser.add_argument("--verify-only", action="store_true", help="Validate archive size/checksums without extracting")
    args = parser.parse_args()
    lock = json.loads((ROOT / "Vendor/CEF.lock").read_text())
    directory = lock["directory"]
    if Path(directory).name != directory or directory in (".", ".."):
        raise ValueError("Invalid distribution directory in CEF.lock")
    cache = ROOT / "build/cef-download" / directory
    cache.mkdir(parents=True, exist_ok=True)
    guard = cache / ".fetch-lock"
    try:
        guard.mkdir()
    except FileExistsError:
        raise ValueError("CEF fetch is already active, or left a lock after interruption: " + str(guard))
    try:
        archive = args.archive.resolve() if args.archive else cache / lock["archive_name"]
        if args.archive and not archive.is_file():
            raise ValueError("Archive does not exist: " + str(archive))
        if not archive.exists():
            if urllib.parse.urlparse(lock["url"]).scheme != "https":
                raise ValueError("CEF download URL must use HTTPS")
            with tempfile.NamedTemporaryFile(dir=cache, suffix=".partial", delete=False) as output:
                partial = Path(output.name)
                try:
                    with urllib.request.urlopen(lock["url"], timeout=60) as response:
                        if urllib.parse.urlparse(response.url).scheme != "https":
                            raise ValueError("CEF download redirected away from HTTPS")
                        downloaded = 0
                        for block in iter(lambda: response.read(1024 * 1024), b""):
                            downloaded += len(block)
                            if downloaded > lock["size_bytes"]:
                                raise ValueError("CEF download exceeds the pinned archive size")
                            output.write(block)
                    output.flush()
                    os.fsync(output.fileno())
                    verify(partial, lock)
                    partial.rename(archive)
                finally:
                    partial.unlink(missing_ok=True)
        verify(archive, lock)
        if args.verify_only:
            print("Verified CEF archive:", archive)
            return
        destination = cache / directory
        receipt = cache / ".extracted-sha256"
        if destination.exists() or destination.is_symlink():
            if (not destination.is_symlink() and (destination / "include/cef_app.h").is_file()
                    and receipt.is_file() and receipt.read_text().strip() == lock["sha256"]):
                print(destination)
                return
            raise ValueError("Refusing to overwrite an unrecognized extraction: " + str(destination))
        with tempfile.TemporaryDirectory(prefix="extract-", dir=cache) as temporary:
            extracted = extract(archive, Path(temporary), directory)
            extracted.rename(destination)
        receipt.write_text(lock["sha256"] + "\n")
        print(destination)
    finally:
        guard.rmdir()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, tarfile.TarError, RuntimeError) as error:
        print("CEF fetch failed:", error, file=sys.stderr)
        sys.exit(1)
