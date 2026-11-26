#!/opt/homebrew/bin/python3.12
"""Prepare pinned direct-Chromium toolchains under the existing volume guard."""
import argparse
import ast
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
# The recipe stays valid across Chromium versions while the DEPS entry that owns each destination still pins the
# exact artifact. Each file lists the dependencies under its directory; root DEPS keys them as src/PATH, the others
# relative to their own directory.
DEPS_FILES = {"DEPS": ("", "src/"), "third_party/devtools-frontend/src/DEPS": ("third_party/devtools-frontend/src/", ""),
              "third_party/dawn/DEPS": ("third_party/dawn/", "")}
CIPD_PLATFORM = {"${{platform}}": "mac-arm64", "${{os}}": "mac", "${{arch}}": "arm64"}
UNKNOWN = object()  # a DEPS expression outside the literal subset; never equal to a pin


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


def source_version(source):
    version = dict(line.split("=", 1) for line in (source / "chrome/VERSION").read_text().splitlines() if "=" in line)
    return ".".join(version[k] for k in ("MAJOR", "MINOR", "BUILD", "PATCH"))


def read_deps(text):
    """The vars and deps of a DEPS file, evaluated as literals with Var() resolved. Never executes the file."""
    scope = {}

    def value(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Dict):
            return {value(k): value(v) for k, v in zip(node.keys, node.values)}
        if isinstance(node, (ast.List, ast.Tuple)):
            return [value(item) for item in node.elts]
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left, right = value(node.left), value(node.right)
            return left + right if isinstance(left, str) and isinstance(right, str) else UNKNOWN
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and len(node.args) == 1
                and not node.keywords):
            argument = value(node.args[0])
            if node.func.id == "Var":
                return scope.get("vars", {}).get(argument, UNKNOWN)
            if node.func.id == "Str":
                return argument
        return UNKNOWN

    for statement in ast.parse(text).body:
        if (isinstance(statement, ast.Assign) and len(statement.targets) == 1
                and isinstance(statement.targets[0], ast.Name) and statement.targets[0].id in ("vars", "deps")):
            scope[statement.targets[0].id] = value(statement.value)
    deps = scope.get("deps")
    return deps if isinstance(deps, dict) else {}


def owner(files, destination):
    """The one DEPS entry for a destination under src, or None if no file or more than one file lists it."""
    found = [deps[key + destination[len(directory):]] for directory, key, deps in files
             if destination.startswith(directory) and key + destination[len(directory):] in deps]
    return found[0] if len(found) == 1 and isinstance(found[0], dict) else None


def pinned(entry, dep):
    """Whether the owning DEPS entry pins exactly this lock entry's artifact."""
    if "bucket" in entry:
        objects = dep.get("objects") if dep.get("dep_type") == "gcs" and dep.get("bucket") == entry["bucket"] else None
        return any(isinstance(item, dict) and item.get("object_name") == entry["object"]
                   and item.get("sha256sum") == entry["sha256"] and item.get("size_bytes") == entry["size_bytes"]
                   for item in objects or [])
    packages = dep.get("packages") if dep.get("dep_type") == "cipd" else None
    for item in packages or []:
        if isinstance(item, dict) and isinstance(item.get("package"), str):
            package = item["package"]
            for token, replacement in CIPD_PLATFORM.items():
                package = package.replace(token, replacement)
            if package == entry["package"]:
                return item.get("version") == entry["version"]
    return False


def deps_drift(lock, source):
    """Lock entries whose owning DEPS entry no longer pins them: moved toolchains that need a re-pin."""
    files = [(directory, key, read_deps((source / name).read_text()))
             for name, (directory, key) in DEPS_FILES.items()]
    drift = []
    for entry in lock["gcs"] + lock["cipd"]:
        dep = owner(files, entry["destination"])
        if dep is None:
            drift.append(f"{entry['id']}: no single DEPS entry owns {entry['destination']}")
        elif not pinned(entry, dep):
            drift.append(f"{entry['id']}: DEPS no longer pins {entry.get('object') or entry['version']}")
    return drift


def check_source(lock, source):
    pinned = json.loads((HERE / "source.lock.json").read_text())["chromium_version"]
    if source_version(source) != pinned:
        raise ValueError("Source version differs from the source lock")
    drift = deps_drift(lock, source)
    if drift:
        raise ValueError("Toolchains moved in DEPS; re-pin toolchains.lock.json: " + ", ".join(drift))


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
    check_source(lock, source)
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
    resolved = json.loads((HERE / "toolchains.resolved.json").read_text())
    if resolved["recipe_sha256"] != recipe_hash:
        raise ValueError("Pinned package instances belong to another recipe")
    if set(resolved["instances"]) != {entry["id"] for entry in lock["cipd"]}:
        raise ValueError("Pinned package instance set differs from the recipe")
    if not all(re.fullmatch(r"[A-Za-z0-9_-]{40,64}", value)
               for value in resolved["instances"].values()):
        raise ValueError("Invalid pinned CIPD instance")
    if resolved_path.exists():
        if json.loads(resolved_path.read_text()) != resolved:
            raise ValueError("Stored package resolution differs from the committed pin")
    else:
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
            expected_tree = dict(saved["tree"])
            supplement = state / "llvmobjdump.installed.json"
            if entry["id"] == "clang" and supplement.exists():
                supplement_lock = HERE / "toolchains.objdump.json"
                pinned = json.loads(supplement_lock.read_text())
                installed = json.loads(supplement.read_text())
                if supplement.is_symlink() or installed != {
                        "lock_sha256": sha(supplement_lock), "tree": pinned["tree"]}:
                    raise ValueError("LLVM supplement receipt differs from pin")
                for name, value in pinned["tree"].items():
                    if name in expected_tree and expected_tree[name] != value:
                        raise ValueError(f"LLVM supplement conflicts with clang: {name}")
                    expected_tree[name] = value
            if saved["recipe_sha256"] != recipe_hash or tree(destination) != expected_tree:
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
                backup = state / (entry["id"] + ".source-backup")
                if os.path.lexists(backup):
                    raise ValueError(f"Existing source backup requires inspection: {backup}")
                write_new(state / (entry["id"] + ".source-backup.json"),
                          {"source": str(destination), "tree": tree(destination)})
                destination.rename(backup)
                stage.rename(destination)
                print(f"Preserved source-provided package: {backup}", flush=True)
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
    group.add_argument("--check-deps", action="store_true", help="Check the source's DEPS still pin this recipe")
    group.add_argument("--guarded", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    if args.check_deps:
        check_source(lock, Path(lock["root"]) / "chromium/src")
        print("Toolchain pins match the source's DEPS")
        return 0
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
