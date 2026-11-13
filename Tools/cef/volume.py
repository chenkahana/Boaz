#!/usr/bin/env python3
"""Manage only Boaz's build image; never erase or repair the backing drive."""

import json
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys


DRIVE = Path("/Volumes/Chen's SSD")
IMAGE = DRIVE / "BoazBuild.sparsebundle"
MOUNT = Path("/Volumes/BoazBuild")
GIB = 1024 ** 3


def fail(message):
    raise RuntimeError(message)


def run(*args):
    subprocess.run(args, check=True)


def plist(*args):
    return plistlib.loads(subprocess.check_output(args, timeout=15))


def drive_info():
    if not DRIVE.is_mount() or DRIVE.is_symlink():
        fail(f"External drive is not mounted at {DRIVE}; refusing internal-disk fallback.")
    info = plist("diskutil", "info", "-plist", str(DRIVE))
    if info.get("MountPoint") != str(DRIVE) or info.get("Internal", True):
        fail("Expected an external volume at the configured drive path.")
    if not os.access(DRIVE, os.W_OK):
        fail("External volume is not writable.")
    if IMAGE.is_symlink():
        fail("Build image path is a symlink; refusing to follow it.")
    return info


def attached_image():
    images = plist("hdiutil", "info", "-plist").get("images", [])
    matches = [item for item in images
               if os.path.realpath(item.get("image-path", "")) == str(IMAGE)]
    if len(matches) > 1:
        fail("Build image has multiple attachments; inspect them before proceeding.")
    return matches[0] if matches else None


def mounted_info():
    attachment = attached_image()
    entities = attachment.get("system-entities", []) if attachment else []
    entity = next((item for item in entities if item.get("mount-point") == str(MOUNT)), None)
    if not entity:
        fail("Expected build image is not attached at /Volumes/BoazBuild.")
    info = plist("diskutil", "info", "-plist", str(MOUNT))
    if info.get("MountPoint") != str(MOUNT) or info.get("DeviceNode") != entity.get("dev-entry"):
        fail("Build mount does not match the disk-image attachment.")
    if info.get("FilesystemType", "").lower() != "apfs":
        fail("Build volume is not APFS.")
    if not info.get("GlobalPermissionsEnabled", False):
        fail("Build volume ownership is disabled.")
    return info


def report():
    drive = drive_info()
    result = {"drive": str(DRIVE), "drive_uuid": drive.get("VolumeUUID"),
              "external_free_bytes": shutil.disk_usage(DRIVE).free,
              "image": str(IMAGE), "image_exists": IMAGE.exists(),
              "attached": attached_image() is not None}
    if result["attached"]:
        info = mounted_info()
        result.update(mount=str(MOUNT), filesystem=info["FilesystemType"],
                      ownership_enabled=info["GlobalPermissionsEnabled"],
                      image_free_bytes=shutil.disk_usage(MOUNT).free)
    print(json.dumps(result, indent=2))


def require_idle():
    lock = MOUNT / "cef" / ".build.lock"
    if lock.exists():
        with lock.open("r") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                fail("A guarded build is active; stop it before detaching.")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"create", "attach", "status", "detach", "compact"}:
        fail("Usage: volume.sh create|attach|status|detach|compact")
    action = sys.argv[1]
    drive_info()
    if action == "create":
        if IMAGE.exists():
            fail("Build image already exists; refusing to overwrite it. Use attach or status.")
        if shutil.disk_usage(DRIVE).free < 520 * GIB:
            fail("Creating the build image requires at least 520 GiB free on the external drive.")
        run("hdiutil", "create", "-size", "500g", "-type", "SPARSEBUNDLE",
            "-fs", "APFS", "-volname", "BoazBuild", "-imagekey",
            "sparse-band-size=262144", str(IMAGE))
    elif action == "attach":
        if not IMAGE.is_dir():
            fail("Build image does not exist. Run create first.")
        if attached_image():
            mounted_info()
        else:
            if MOUNT.exists() or MOUNT.is_symlink():
                fail("/Volumes/BoazBuild already exists; refusing a conflicting mount.")
            run("hdiutil", "attach", "-nobrowse", "-owners", "on", "-mountpoint", str(MOUNT), str(IMAGE))
            mounted_info()
        (MOUNT / ".metadata_never_index").touch(exist_ok=True)
    elif action == "detach":
        if attached_image():
            mounted_info()
            require_idle()
            # No force: open files or a running build must make this fail safely.
            run("hdiutil", "detach", str(MOUNT))
        elif MOUNT.exists():
            fail("Unexpected build mount exists; refusing to detach an unrelated volume.")
    elif action == "compact":
        if attached_image() or MOUNT.exists():
            fail("Detach the build image and stop all builds before compacting.")
        if not IMAGE.is_dir():
            fail("Build image does not exist.")
        run("hdiutil", "compact", str(IMAGE))
    report()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError, plistlib.InvalidFileException) as error:
        print(f"Build volume: {error}", file=sys.stderr)
        sys.exit(1)
