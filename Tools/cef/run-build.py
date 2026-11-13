#!/usr/bin/env python3
"""Run a build stage on the verified image, stopping only its own process group."""

import datetime
import fcntl
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
import volume


def capacity():
    volume.drive_info()
    volume.mounted_info()
    for path, minimum in ((volume.DRIVE, 20), (volume.MOUNT, 30)):
        available = shutil.disk_usage(path).free
        if available < minimum * volume.GIB:
            raise RuntimeError(f"{path}: {available} bytes free; need at least {minimum} GiB.")


def stop(process):
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        print("Owned build did not stop after SIGTERM; terminating its process group.", file=sys.stderr)
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def main():
    args = sys.argv[1:]
    if args[:1] == ["--"]:
        args = args[1:]
    if not args:
        raise RuntimeError("Usage: python3 Tools/cef/run-build.py -- COMMAND [ARGS...]")
    subprocess.run([str(Path(__file__).with_name("volume.sh")), "attach"], check=True)
    capacity()
    root = volume.MOUNT / "cef"
    root.mkdir(exist_ok=True)
    for name in ("logs", "tmp", "cache"):
        (root / name).mkdir(exist_ok=True)
    with (root / ".build.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another guarded build stage is active.")
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        log_path = root / "logs" / f"{stamp}.log"
        env = dict(os.environ, TMPDIR=str(root / "tmp"), XDG_CACHE_HOME=str(root / "cache"))
        with log_path.open("x") as log:
            print(f"Build log: {log_path}", flush=True)
            process = subprocess.Popen(args, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            awake = None
            try:
                awake = subprocess.Popen(["caffeinate", "-dimsu", "-w", str(process.pid)])
                while process.poll() is None:
                    capacity()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        pass
                return process.returncode
            finally:
                stop(process)
                if awake is not None:
                    awake.terminate()
                    awake.wait()


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"CEF build stopped: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("CEF build interrupted; owned processes stopped.", file=sys.stderr)
        sys.exit(130)
