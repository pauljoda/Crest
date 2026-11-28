#!/usr/bin/env python3
"""Build an externally prepared Chromium baseline without exhausting the host disk."""

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chromium_host  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--ninja", help="Ninja to build with (default: the one preparation installed, else PATH's)")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--target", default="chrome", help="Ninja target; defaults to the complete browser")
    parser.add_argument("--output", default="out/CrestBaseline",
                        help="Build directory inside the source, one per architecture (source.lock.json)")
    parser.add_argument("--min-free-gib", type=int, default=15)
    args = parser.parse_args()
    root = args.source.resolve()
    repo = Path(__file__).resolve().parents[2]
    if root == repo or repo in root.parents:
        parser.error("Chromium source and products must be outside the Crest checkout")
    if not (root / args.output / "build.ninja").is_file():
        parser.error(f"Prepare the pinned source and generate {args.output} first")
    if args.jobs < 1 or args.min_free_gib < 1:
        parser.error("Job count and disk reserve must be positive")
    reserve = args.min_free_gib * 1024**3
    if shutil.disk_usage(root).free < reserve:
        parser.error("Free disk space is below the requested reserve")
    host = chromium_host.detected()
    installed = root / "third_party/ninja" / chromium_host.executable("ninja", host)
    ninja = args.ninja or (str(installed) if installed.is_file() else "ninja")

    command = [ninja, "-C", args.output, f"-j{args.jobs}", args.target]
    if os.name == "nt":
        # Ninja and its compilers form one console process group the wrapper can stop together.
        process = subprocess.Popen(command, cwd=root, env=chromium_host.build_environment(host, root),
                                   creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    else:
        process = subprocess.Popen(command, cwd=root, start_new_session=True)

    def stop(signum=signal.SIGTERM, _frame=None):
        if process.poll() is not None:
            return
        if os.name == "nt":
            process.send_signal(signal.CTRL_BREAK_EVENT)
        else:
            os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)], check=False)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()

    for name in ("SIGTERM", "SIGINT", "SIGHUP", "SIGBREAK"):
        if hasattr(signal, name):
            signal.signal(getattr(signal, name), stop)
    try:
        while process.poll() is None:
            if shutil.disk_usage(root).free < reserve:
                print(f"Stopped Chromium build to preserve {args.min_free_gib} GiB free disk space.", flush=True)
                stop()
                return 75
            time.sleep(2)
        return process.returncode
    finally:
        stop()


if __name__ == "__main__":
    raise SystemExit(main())
