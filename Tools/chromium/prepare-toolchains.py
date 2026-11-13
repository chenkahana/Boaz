#!/opt/homebrew/bin/python3.12
"""Prepare pinned direct-Chromium toolchains under the existing volume guard."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent
LOCK = HERE / "toolchains.lock.json"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_new(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())


def run(command, env):
    subprocess.run(command, env=env, check=True, timeout=1800)


def tree(root):
    result = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        if rel.parts[0] == ".cipd":
            continue
        if path.is_symlink():
            if not path.resolve().is_relative_to(root):
                raise ValueError(f"Escaping installed link: {path}")
            result[str(rel)] = ["link", os.readlink(path)]
        elif path.is_file():
            result[str(rel)] = ["file", sha(path), bool(path.stat().st_mode & 0o111)]
        elif not path.is_dir():
            raise ValueError(f"Special installed file: {path}")
    return result


def extract(archive, stage):
    stage.mkdir()
    seen = set()
    with tarfile.open(archive, "r|*") as bundle:
        for member in bundle:
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts:
                raise ValueError(f"Archive traversal: {member.name}")
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise ValueError(f"Special archive member: {member.name}")
            if str(name) in seen:
                raise ValueError(f"Duplicate archive path: {member.name}")
            seen.add(str(name))
            if member.issym() or member.islnk():
                target = PurePosixPath(member.linkname)
                base = stage / name.parent if member.issym() else stage
                resolved = (base / member.linkname).resolve()
                if target.is_absolute() or not resolved.is_relative_to(stage):
                    raise ValueError(f"Escaping archive link: {member.name}")
                if member.islnk() and not resolved.is_file():
                    raise ValueError(f"Forward or invalid hard link: {member.name}")
            bundle.extract(member, stage, filter="data")


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        if not url.startswith("https://"):
            raise ValueError("Refusing non-HTTPS redirect")
        return super().redirect_request(request, response, code, message, headers, url)


def download(entry, archive):
    if not archive.exists():
        partial = archive.with_suffix(".partial")
        url = f"https://storage.googleapis.com/{entry['bucket']}/{entry['object']}"
        with partial.open("xb") as out, urllib.request.build_opener(HTTPSOnly()).open(url, timeout=60) as response:
            if not response.url.startswith("https://"):
                raise ValueError("Non-HTTPS download redirect")
            size = 0
            while block := response.read(1024 * 1024):
                size += len(block)
                if size > entry["size_bytes"]:
                    raise ValueError("Download exceeded pinned size")
                out.write(block)
            out.flush()
            os.fsync(out.fileno())
        if partial.stat().st_size != entry["size_bytes"] or sha(partial) != entry["sha256"]:
            raise ValueError(f"Download integrity failure: {partial}")
        os.link(partial, archive)
        partial.unlink()
    if archive.stat().st_size != entry["size_bytes"] or sha(archive) != entry["sha256"]:
        raise ValueError(f"Cached archive integrity failure: {archive}")


def prepare(lock):
    root = Path(lock["root"])
    if Path.cwd() != root.parent or os.environ.get("TMPDIR") != str(root.parent / "tmp"):
        raise ValueError("Run preparation through the volume guard")
    with (root.parent / ".build.lock").open() as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise ValueError("Volume guard lock not held")
    depot = Path(lock["depot_tools"])
    revision = subprocess.check_output(["git", "-C", str(depot), "rev-parse", "HEAD"], text=True).strip()
    if revision != lock["depot_tools_commit"]:
        raise ValueError("depot_tools revision differs from pin")
    source = root / "chromium/src"
    if not (source / "chrome/VERSION").is_file():
        raise ValueError("Verified source is missing")
    version = dict(line.split("=", 1) for line in (source / "chrome/VERSION").read_text().splitlines() if "=" in line)
    if ".".join(version[k] for k in ("MAJOR", "MINOR", "BUILD", "PATCH")) != lock["chromium_version"]:
        raise ValueError("Source version differs from toolchain recipe")
    state = root / "toolchains"
    for path in [source, state, root / "downloads", root / "cache/cipd", root / "tmp"]:
        if path.resolve() != path:
            raise ValueError(f"Symlink storage path: {path}")
        path.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, DEPOT_TOOLS_UPDATE="0", CIPD_CACHE_DIR=str(root / "cache/cipd"),
               TMPDIR=str(root / "tmp"), PYTHONDONTWRITEBYTECODE="1")
    cipd = str(depot / ".cipd_client")
    if sha(Path(cipd)) != lock["cipd_client_sha256"]:
        raise ValueError("Installed CIPD binary differs from pin")
    resolved_path = state / "resolved.json"
    recipe_hash = sha(LOCK)
    if resolved_path.exists():
        resolved = json.loads(resolved_path.read_text())
        if resolved["recipe_sha256"] != recipe_hash:
            raise ValueError("Existing resolution belongs to another recipe")
    else:
        resolved = {"recipe_sha256": recipe_hash, "instances": {}}
        for entry in lock["cipd"]:
            output = state / (entry["id"] + ".resolve.json")
            if output.exists():
                raise ValueError(f"Uncommitted resolution exists: {output}")
            run([cipd, "resolve", entry["package"], "-version", entry["version"], "-json-output", str(output)], env)
            result = json.loads(output.read_text())["result"]
            instance = result["instance_id"]
            if result.get("package", result.get("package_name")) != entry["package"] or not re.fullmatch(r"[A-Za-z0-9_-]{40,64}", instance):
                raise ValueError("Unexpected CIPD resolution result")
            resolved["instances"][entry["id"]] = instance
        write_new(resolved_path, resolved)
    for entry in lock["gcs"] + lock["cipd"]:
        rel = PurePosixPath(entry["destination"])
        if rel.is_absolute() or ".." in rel.parts:
            raise ValueError("Invalid package destination")
        destination = source / rel
        if destination.resolve() != destination:
            raise ValueError(f"Symlink package destination: {destination}")
        stage = state / (entry["id"] + ".stage")
        receipt = state / (entry["id"] + ".installed.json")
        if receipt.exists():
            saved = json.loads(receipt.read_text())
            if saved["recipe_sha256"] != recipe_hash or tree(destination) != saved["tree"]:
                raise ValueError(f"Installed package changed: {destination}")
            continue
        if stage.exists():
            raise ValueError(f"Preserved stage requires inspection: {stage}")
        if "bucket" in entry:
            archive = root / "downloads" / (entry["id"] + "-" + entry["sha256"] + ".tar")
            download(entry, archive)
            extract(archive, stage)
        else:
            stage.mkdir()
            ensure = state / (entry["id"] + ".ensure")
            with ensure.open("x") as stream:
                stream.write(f"$ParanoidMode CheckIntegrity\n{entry['package']} {resolved['instances'][entry['id']]}\n")
            run([cipd, "ensure", "-root", str(stage), "-ensure-file", str(ensure)], env)
        contents = tree(stage)
        if not contents:
            raise ValueError("Empty package stage")
        if destination.exists():
            if tree(destination) != contents:
                raise ValueError(f"Existing destination differs; preserving both: {destination}")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            stage.rename(destination)
        write_new(receipt, {"recipe_sha256": recipe_hash, "tree": contents})
        print(f"Verified package: {entry['id']}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--dry-run", action="store_true")
    group.add_argument("--prepare", action="store_true")
    group.add_argument("--guarded", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    command = [lock["python"], str(HERE.parent / "cef/run-build.py"), "--", lock["python"], str(Path(__file__).resolve()), "--guarded"]
    if args.guarded:
        prepare(lock)
    elif args.prepare:
        return subprocess.call(command)
    else:
        print(json.dumps({"command": command, "recipe": lock}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.SubprocessError) as error:
        print(f"Toolchain preparation stopped; artifacts preserved: {error}", file=sys.stderr)
        sys.exit(1)
