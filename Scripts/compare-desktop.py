#!/usr/bin/env python3
"""Run the Svelte Windows interface and native Crest together on macOS."""

import argparse
import contextlib
import hashlib
import os
from pathlib import Path
import platform
import plistlib
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "CrestDesktop/ui"
OUTPUT = (Path.home() / "Library/Caches/Crest/DesktopComparison" /
          hashlib.sha256(os.fsencode(ROOT)).hexdigest()[:12])


def executable(bundle):
    with (bundle / "Contents/Info.plist").open("rb") as info:
        name = plistlib.load(info)["CFBundleExecutable"]
    return bundle / "Contents/MacOS" / name


def build(build_native, optimized, chromium_engine):
    arch = {"arm64": "arm64", "x86_64": "x64"}[platform.machine()]
    subprocess.run(["dotnet", "publish", "src/CrestCore.Native", "-c", "Release", "-r", f"osx-{arch}",
                    "--artifacts-path", OUTPUT / "dotnet", "-o", OUTPUT / "core"], cwd=ROOT / "CrestCore", check=True)
    subprocess.run(["dotnet", "build", ROOT / "CrestDesktop/devhost", "-c", "Release", "-o", OUTPUT / "bridge"],
                   cwd=ROOT / "CrestCore", check=True)
    subprocess.run(["npm", "ci", "--no-audit", "--no-fund"], cwd=UI, check=True)
    if optimized:
        subprocess.run([UI / "node_modules/.bin/vite", "build", "--mode", "comparison",
                        "--outDir", OUTPUT / "ui", "--emptyOutDir"], cwd=UI / "app", check=True)
    if build_native:
        scheme = "CrestChromiumUI" if chromium_engine else "Crest"
        conditions = ["$(inherited)"]
        if optimized:
            conditions.append("CREST_TEST_FIXTURES")
        if chromium_engine:
            conditions.extend(["CREST_CHROMIUM_HOST", "CREST_REVIEW_BUILD"])
        subprocess.run(["xcodebuild", "-quiet", "-project", "Crest.xcodeproj", "-scheme", scheme,
                        "-configuration", "Release" if optimized else "Debug", "-destination", f"platform=macOS,arch={platform.machine()}",
                        "-derivedDataPath", OUTPUT / "native", "CREST_MAC_BUNDLE_IDENTIFIER=com.pauldavis.crest.parity",
                        f"CREST_CORE_LIBRARY_DIR={OUTPUT / 'core'}", "ONLY_ACTIVE_ARCH=YES",
                        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=" + " ".join(conditions),
                        "ENABLE_HARDENED_RUNTIME=NO", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "CODE_SIGN_ENTITLEMENTS=",
                        "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER=", "build"], cwd=ROOT, check=True)


@contextlib.contextmanager
def running(command, **kwargs):
    proc = subprocess.Popen(command, start_new_session=True, **kwargs)
    try:
        yield proc
    finally:
        # npm, Vite and both Chromium processes can have children.
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()


def ready(process, url):
    deadline = time.monotonic() + 45
    while process.poll() is None and time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except OSError:
            pass
        time.sleep(0.1)
    raise RuntimeError(f"Could not start {url} (exit {process.poll()})")


def ports():
    with socket.socket() as bridge, socket.socket() as ui:
        bridge.bind(("127.0.0.1", 0))
        ui.bind(("127.0.0.1", 0))
        return bridge.getsockname()[1], ui.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    reference = parser.add_mutually_exclusive_group()
    reference.add_argument("--native-app", type=Path,
                        help="The native reference build")
    reference.add_argument("--chromium-engine", type=Path,
                           help="Build the native Chromium UI with an existing Crest-overlaid Chromium.app")
    parser.add_argument("--signing-identity", default="Apple Development",
                        help="Local code-signing identity for the isolated Chromium reference")
    parser.add_argument("--browser", type=Path, default=Path("/Applications/Google Chrome.app"),
                        help="Chromium browser bundle for the Svelte interface")
    parser.add_argument("--no-build", action="store_true", help="Reuse this checkout's core, bridge and npm install")
    parser.add_argument("--optimized", action="store_true",
                        help="Pair an isolated Release build with the compiled Svelte bundle for timing comparisons")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This comparison runs on macOS")
    browser = executable(args.browser)
    if not args.no_build:
        build(args.native_app is None, args.optimized, args.chromium_engine)
    configuration = "Release" if args.optimized else "Debug"
    products = OUTPUT / "native/Build/Products" / configuration
    bridge_port, ui_port = ports()
    origin = f"http://127.0.0.1:{ui_port}"
    url = f"{origin}/?compare&bridge=ws://127.0.0.1:{bridge_port}/core"
    env = {**os.environ, "CREST_ISOLATED_SESSION": "1", "CREST_USE_IN_MEMORY_CREDENTIALS": "1",
           "CREST_DESKTOP_COMPARISON": "1"}
    # A comparison always starts fresh, even from a shell used for other fixtures.
    for key in ("CREST_ISOLATED_PERSISTENCE_ID", "CREST_ISOLATED_CLOUD_SYNC_ID"):
        env.pop(key, None)
    with tempfile.TemporaryDirectory(prefix="crest-desktop-parity-") as temporary, contextlib.ExitStack() as stack:
        native_app = args.native_app or products / "Crest.app"
        if args.chromium_engine:
            native_app = Path(temporary) / "Crest Comparison.app"
            subprocess.run([sys.executable, ROOT / "Scripts/control-plane/package-chromium-host.py",
                            "--browser", args.chromium_engine, "--ui", products / "CrestChromiumUI.framework",
                            "--core", OUTPUT / "core/CrestCore.Native.dylib", "--output", native_app,
                            "--signing-identity", args.signing_identity], check=True)
            # Launch Services remembers the app even after its temporary directory is gone.
            register = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
                            "LaunchServices.framework/Support/lsregister")
            stack.callback(subprocess.run, [register, "-u", native_app], check=False)
        native = executable(native_app)

        def start(command, **kwargs):
            return stack.enter_context(running(command, env=env, **kwargs))

        bridge = start(["dotnet", OUTPUT / "bridge/CrestDesktop.DevHost.dll", "--core",
                        OUTPUT / "core/CrestCore.Native.dylib", "--port", str(bridge_port), "--origin", origin])
        ready(bridge, f"http://127.0.0.1:{bridge_port}/health")
        vite = start([UI / "node_modules/.bin/vite", *(["preview", "--outDir", OUTPUT / "ui"] if args.optimized else []),
                      "--host", "127.0.0.1", "--port", str(ui_port), "--strictPort"], cwd=UI / "app")
        ready(vite, origin)
        common = ["--no-first-run", "--no-default-browser-check", "--use-mock-keychain"]
        reference = start([native, *common, "--crest-control-plane", f"--user-data-dir={temporary}/native"])
        desktop = start([browser, *common, "--disable-sync", "--disable-background-mode", "--disable-default-apps", f"--user-data-dir={temporary}/desktop", f"--app={url}"])
        # Without Accessibility access the windows can still be arranged by hand.
        subprocess.run(["swift", ROOT / "Scripts/desktop-parity.swift", "arrange",
                        str(reference.pid), str(desktop.pid)], check=False)
        print(f"Native PID {reference.pid}, Svelte PID {desktop.pid}. Ctrl-C ends this comparison.", flush=True)
        while all(p.poll() is None for p in (bridge, vite, reference, desktop)):
            time.sleep(0.25)
        for process in (bridge, vite, reference, desktop):
            if process.poll() not in (None, 0):
                raise RuntimeError(f"{process.args[0]} exited with {process.returncode}")


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
