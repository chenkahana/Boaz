#!/usr/bin/env python3
"""Stage and development-sign the CEF spike without modifying its build output."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile

BUNDLE_ID = "com.chenkahana.boaz.cef-spike"
HELPERS = ("", " (Alerts)", " (GPU)", " (Plugin)", " (Renderer)")
FULL_OPTIONS = "restrict,kill,library,runtime"


def validate_links(root):
    for path in root.rglob("*"):
        if path.is_symlink():
            resolved = path.resolve(strict=True)
            if root not in resolved.parents:
                raise ValueError(f"Symlink escapes staged bundle: {path}")


def macho_type(path):
    with path.open("rb") as stream:
        header = stream.read(32)
        magic = header[:4]
        if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            offset_size = 8 if magic[-1] == 0xbf else 4
            stream.seek(16)
            offset = int.from_bytes(stream.read(offset_size), "big")
            stream.seek(offset)
            header = stream.read(32)
            magic = header[:4]
        endian = {b"\xcf\xfa\xed\xfe": "<", b"\xce\xfa\xed\xfe": "<",
                  b"\xfe\xed\xfa\xcf": ">", b"\xfe\xed\xfa\xce": ">"}.get(magic)
        return struct.unpack(endian + "I", header[12:16])[0] if endian else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--identity", required=True, help="Apple Development certificate SHA1")
    args = parser.parse_args()
    source = args.app.resolve(strict=True)
    output = args.output.absolute()
    if not re.fullmatch(r"[0-9a-fA-F]{40}", args.identity):
        parser.error("--identity must be a 40-character certificate SHA1")
    if os.path.lexists(output):
        parser.error("--output already exists; choose a new staging path")
    output = output.parent.resolve(strict=True) / output.name
    if source == output or source in output.parents:
        parser.error("--output must be outside the input app")
    if output.suffix != ".app":
        parser.error("--output must end in .app")
    with (source / "Contents/Info.plist").open("rb") as stream:
        if plistlib.load(stream).get("CFBundleIdentifier") != BUNDLE_ID:
            parser.error("Input is not the Boaz CEF spike")
    report = {"source": str(source), "output": str(output), "commands": [], "status": "staging"}
    report_path = output.with_name(output.name + ".signing.json")
    if os.path.lexists(report_path):
        parser.error("Signing report already exists")

    def run(command):
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        report["commands"].append({"argv": command, "exit_code": result.returncode, "output": result.stdout})
        if result.returncode:
            raise RuntimeError(f"Command failed: {command[0]} {command[-1]}\n{result.stdout}")

    def sign(path, options=None, entitlements=None):
        command = ["/usr/bin/codesign", "--force", "--sign", args.identity, "--timestamp=none"]
        if options:
            command += ["--options", options]
        if entitlements:
            command += ["--entitlements", str(entitlements)]
        run(command + [str(path)])

    def ignore(directory, names):
        return ["BoazCEFSpike.d"] if Path(directory) == source / "Contents/MacOS" else []

    try:
        shutil.copytree(source, output, symlinks=True, ignore=ignore)
        validate_links(output)
        framework = output / "Contents/Frameworks/Chromium Embedded Framework.framework"
        if not framework.is_dir():
            raise ValueError("Missing CEF framework")
        helpers = [output / f"Contents/Frameworks/BoazCEFSpike Helper{suffix}.app" for suffix in HELPERS]
        for helper in helpers:
            with (helper / "Contents/Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            executable = helper / "Contents/MacOS" / info["CFBundleExecutable"]
            if not executable.is_file() or macho_type(executable) != 2:
                raise ValueError(f"Missing Mach-O helper executable: {helper}")
        plists = [output / "Contents/Info.plist", framework / "Resources/Info.plist"]
        plists += [helper / "Contents/Info.plist" for helper in helpers]
        for info_plist in plists:
            run(["/usr/bin/plutil", "-convert", "xml1", str(info_plist)])
        leaves = [(path, macho_type(path)) for path in sorted(framework.rglob("*"))
                  if path.is_file() and not path.is_symlink()]
        leaves = [(path, kind) for path, kind in leaves if kind is not None]
        if not leaves:
            raise ValueError("CEF framework contains no Mach-O files")
        report["framework_macho"] = [{"path": str(p.relative_to(output)), "type": k} for p, k in leaves]
        for path, kind in leaves:
            sign(path, FULL_OPTIONS if kind == 2 else None)
        sign(framework)
        with tempfile.TemporaryDirectory(prefix="boaz-spike-sign-") as temporary:
            jit = Path(temporary) / "jit.plist"
            jit.write_bytes(plistlib.dumps({"com.apple.security.cs.allow-jit": True}))
            for helper, suffix in zip(helpers, HELPERS):
                needs_jit = suffix in (" (GPU)", " (Renderer)")
                sign(helper, "restrict,kill,runtime" if needs_jit else FULL_OPTIONS, jit if needs_jit else None)
        sign(output, FULL_OPTIONS)
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(output)])
        run(["/usr/bin/codesign", "-d", "-r-", "--verbose=2", str(output)])
        report["status"] = "verified"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        with report_path.open("x") as stream:
            json.dump(report, stream, indent=2)
            stream.write("\n")
        print(f"Signing report: {report_path}")
    print(f"Verified development-signed spike: {output}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Signing failed; staging output preserved: {error}", file=sys.stderr)
        sys.exit(1)
