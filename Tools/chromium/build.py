#!/opt/homebrew/bin/python3.12
"""Configure or build the direct Chromium feasibility target under the SSD guard."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid


def verify_host_inputs(scripts, root, source, ui_only=False):
    receipt = json.loads((root / "host-installed.json").read_text())
    expected = receipt["files"]
    paths = ["boaz_host.h"] if ui_only else sorted(expected)
    if not ui_only:
        local = {str(p.relative_to(scripts / "host")) for p in
                 (scripts / "host").rglob("*") if p.is_file()}
        if local != set(expected):
            raise RuntimeError("Host inputs changed; apply pinned patches and install host sources first.")
    for name in paths:
        for path in (scripts / "host" / name, source / "boaz" / name):
            if path.resolve() != path or hashlib.sha256(path.read_bytes()).hexdigest() != expected[name]:
                raise RuntimeError(f"Host input differs from installed receipt: {path}")
    if ui_only:
        return
    manifest = json.loads((scripts / "patches.lock.json").read_text())
    applied = json.loads((root / "patches-applied.json").read_text())
    if applied["pending"] or applied["applied"] != manifest["patches"]:
        raise RuntimeError("Pinned patch series is not fully applied; use apply-patches.py first.")
    files = {}
    for patch in manifest["patches"]:
        if hashlib.sha256((scripts / patch["file"]).read_bytes()).hexdigest() != patch["sha256"]:
            raise RuntimeError("Pinned patch checksum changed.")
        files.update({entry["path"]: entry["after"] for entry in patch["files"]})
    for name, digest in files.items():
        path = source / name
        if path.resolve() != path or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError(f"Patched Chromium input changed: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--dry-run", action="store_true")
    modes.add_argument("--configure", action="store_true")
    modes.add_argument("--build", action="store_true")
    modes.add_argument("--host-objects", action="store_true")
    modes.add_argument("--native-ui", action="store_true")
    parser.add_argument("--jobs", type=int, default=4, choices=range(1, 13))
    parser.add_argument("--guarded", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    scripts = Path(__file__).resolve().parent
    source_lock = json.loads((scripts / "source.lock.json").read_text())
    config = json.loads((scripts / "development.json").read_text())
    root = Path(source_lock["storage_root"])
    source = root / "chromium/src"
    output = source / "out" / config["configuration"]
    gn = source / "buildtools/mac/gn"
    ninja = Path("/opt/homebrew/bin/ninja")
    if not args.configure and not args.build and not args.host_objects and not args.native_ui:
        print(json.dumps({"source": str(source), "output": str(output),
                          "gn_args": config["gn_args"], "jobs": args.jobs,
                          "targets": ["chrome", "chrome/installer/mac"], "purpose": config["purpose"]}, indent=2))
        return 0
    if not args.guarded:
        guard = scripts.parent / "cef/run-build.py"
        return subprocess.call([source_lock["python"], str(guard), "--",
                                source_lock["python"], str(Path(__file__).resolve()),
                                "--guarded", "--build" if args.build else
                                "--host-objects" if args.host_objects else
                                "--native-ui" if args.native_ui else "--configure",
                                "--jobs", str(args.jobs)])
    if Path.cwd() != root.parent or os.environ.get("TMPDIR") != str(root.parent / "tmp"):
        raise RuntimeError("Build stage requires the verified SSD guard.")
    with (root.parent / ".build.lock").open("r") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError("The build guard is not holding its lock.")
    for path in (root, source, output, gn):
        if path.resolve() != path:
            raise RuntimeError(f"Build path is redirected: {path}")
    version = dict(line.split("=", 1) for line in (source / "chrome/VERSION").read_text().splitlines())
    if ".".join(version[key] for key in ("MAJOR", "MINOR", "BUILD", "PATCH")) != source_lock["chromium_version"]:
        raise RuntimeError("Source version differs from the lock.")
    verify_host_inputs(scripts, root, source, ui_only=args.native_ui)
    for tool in (gn, ninja):
        if not tool.is_file():
            raise RuntimeError(f"Required build tool is missing: {tool}")
    env = dict(os.environ, DEPOT_TOOLS_UPDATE="0", PYTHONDONTWRITEBYTECODE="1",
               CIPD_CACHE_DIR=str(root / "cache/cipd"),
               VPYTHON_VIRTUALENV_ROOT=str(root / "cache/vpython"))
    env.pop("LIBRARY_PATH", None)
    developer = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
    env["DEVELOPER_DIR"] = developer
    subprocess.run(["xcrun", "metal", "--version"], check=True, env=env)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                                  text=True, env=env).strip()
    print(f"System SDK: {sdk}", flush=True)
    if args.native_ui:
        ui_output = root / "ui"
        ui_cache = root / "cache/swift"
        for path in (ui_output, ui_cache):
            if path.resolve() != path:
                raise RuntimeError(f"UI build path is redirected: {path}")
            path.mkdir(parents=True, exist_ok=True)
        library = ui_output / "libBoazNativeUI.dylib"
        if library.exists():
            users = subprocess.run(["/usr/sbin/lsof", "-t", "--", str(library)],
                                   text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
            if users.returncode not in (0, 1) or users.stdout.strip():
                raise RuntimeError("Native UI library is in use; close its prototype before rebuilding.")
        staged_library = ui_output / ("libBoazNativeUI.staged-" + uuid.uuid4().hex + ".dylib")
        subprocess.run([
            "xcrun", "swiftc", "-emit-library", "-module-name", "BoazNativeUI",
            "-swift-version", "6", "-target", "arm64-apple-macos14.0",
            "-sdk", sdk, "-module-cache-path", str(ui_cache),
            "-import-objc-header", str(scripts / "host/boaz_host.h"),
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/libBoazNativeUI.dylib",
            "-o", str(staged_library),
            str(scripts / "ui/BoazHostUI.swift")], cwd=scripts, env=env, check=True)
        if library.exists():
            library.rename(ui_output / ("libBoazNativeUI.previous-" + uuid.uuid4().hex + ".dylib"))
        staged_library.rename(library)
        return 0
    values = config["gn_args"]
    contents = "".join(f"{key} = {json.dumps(value)}\n" for key, value in sorted(values.items()))
    output.mkdir(parents=True, exist_ok=True)
    settings = output / "args.gn"
    if settings.exists() and settings.read_text() != contents:
        if not args.configure:
            raise RuntimeError("Existing args.gn differs; run --configure after reviewing the configuration.")
        previous = settings.with_name("args.previous-" + uuid.uuid4().hex + ".gn")
        settings.rename(previous)
        print(f"Preserved previous configuration: {previous}", flush=True)
    if not settings.exists():
        with settings.open("x") as stream:
            stream.write(contents)
    if args.configure or not (output / "build.ninja").exists():
        subprocess.run([str(gn), "gen", str(output), "--fail-on-unused-args"],
                       cwd=source, env=env, check=True)
    if args.build or args.host_objects:
        targets = (["obj/boaz/host/" + name + ".o" for name in
                    ("bootstrap", "native_profiles", "native_downloads", "page_print", "page_pdf", "visible_page_capture", "page_emulation", "native_view", "native_window", "native_location_bar", "native_permission_prompt", "tab_registry", "trusted_execution", "password_submission", "trusted_script_channel", "extension_actions", "extension_popup")]
                   if args.host_objects else ["chrome", "chrome/installer/mac"])
        if args.host_objects:
            targets += [
                "obj/boaz/launch/launch.o",
                "obj/chrome/chrome_dll/chrome_main_delegate.o",
                "obj/chrome/browser/core/chrome_browser_main.o",
                "obj/chrome/browser/ui/core/browser.o",
                "obj/chrome/browser/ui/unload_controller_impl/unload_controller.o",
                "obj/chrome/browser/ui/views/frame/browser_window_factory/browser_window_factory.o",
                "obj/chrome/browser/ui/views/permissions/impl/permission_prompt_factory.o",
                "obj/chrome/browser/component_updater/impl/registration.o",
                "obj/chrome/browser/extensions/extensions/extension_view_host.o",
            ]
        subprocess.run([str(ninja), "-C", str(output), f"-j{args.jobs}", *(["-k", "0"] if args.host_objects else []), *targets],
                       cwd=source, env=env, check=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Direct Chromium build stopped: {error}", file=sys.stderr)
        sys.exit(1)
