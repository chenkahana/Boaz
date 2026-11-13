#!/usr/bin/env python3
"""Run a build stage on the verified image, stopping only its own process group."""

import datetime
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import volume


def capacity():
    volume.drive_info()
    volume.mounted_info()
    free = {}
    for path, minimum in ((volume.DRIVE, 20), (volume.MOUNT, 30)):
        available = shutil.disk_usage(path).free
        free[str(path)] = available
        if available < minimum * volume.GIB:
            raise RuntimeError(f"{path}: {available} bytes free; need at least {minimum} GiB.")
    return free

def resident_bytes(process):
    rows = subprocess.check_output(["ps", "-axo", "pid=,ppid=,pgid=,rss="], text=True)
    processes = [tuple(map(int, line.split())) for line in rows.splitlines() if line.strip()]
    owned = {pid for pid, parent, group, rss in processes if group == process.pid}
    owned.add(process.pid)
    while True:
        children = {pid for pid, parent, group, rss in processes if parent in owned}
        if children.issubset(owned):
            break
        owned.update(children)
    return sum(rss * 1024 for pid, parent, group, rss in processes if pid in owned)


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
            started = time.monotonic()
            minimum_free = {}
            initial_free = {}
            peak_rss = 0
            sample_count = 0
            try:
                awake = subprocess.Popen(["caffeinate", "-dimsu", "-w", str(process.pid)])
                while process.poll() is None:
                    free = capacity()
                    if not initial_free:
                        initial_free = free.copy()
                    for path, amount in free.items():
                        minimum_free[path] = min(minimum_free.get(path, amount), amount)
                    peak_rss = max(peak_rss, resident_bytes(process))
                    sample_count += 1
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
                metrics = {
                    "process_exit_code": process.returncode,
                    "duration_seconds": round(time.monotonic() - started, 3),
                    "sample_interval_seconds": 10,
                    "samples": sample_count,
                    "initial_free_bytes": initial_free,
                    "minimum_sampled_free_bytes": minimum_free,
                    "peak_sampled_owned_rss_sum_bytes": peak_rss,
                    "memory_note": "Sampled process-tree RSS sum, including shared pages; not physical footprint or an absolute peak.",
                }
                with log_path.with_suffix(".metrics.json").open("x") as output:
                    json.dump(metrics, output, indent=2)
                    output.flush()
                    os.fsync(output.fileno())


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
