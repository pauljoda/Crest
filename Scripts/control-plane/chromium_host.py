#!/usr/bin/env python3
"""The machine Crest's Chromium is prepared and built on.

A host is the operating system and CPU the engine's toolchains run on, which
for now is also the engine it builds: `mac-arm64` builds the Mac engine and
`win-x64` the Windows one. The Mac host's preparation lives in the source lock
itself, which predates hosts; every other host has a profile in
`CrestEngines/Chromium/Hosts`, naming the toolchains DEPS pins for it, the
dependencies a Linux-exported source archive lacks for it, and its build
arguments.
"""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[2]
ENGINE = REPO / "CrestEngines/Chromium"
HOSTS = ENGINE / "Hosts"
MAC = "mac-arm64"
WINDOWS = "win-x64"

# A tarball build: what gclient sets for a checkout that is not a Git tree.
MAC_DEPS_VARIABLES = {"host_os": "mac", "host_cpu": "arm64", "checkout_mac": True, "checkout_arm64": True,
                      "non_git_source": True}


def detected() -> str:
    """The host this machine is."""
    system, machine = platform.system(), platform.machine().lower()
    if system == "Darwin" and machine == "arm64":
        return MAC
    if system == "Windows" and machine in ("amd64", "x86_64"):
        return WINDOWS
    raise SystemExit(f"Crest's Chromium has no host profile for {system} {machine}")


def is_windows(host: str) -> bool:
    return host.startswith("win-")


def profile(host: str, lock: dict) -> dict:
    """What preparing and building on `host` needs, in one shape for every host."""
    if host == MAC:
        return {
            "depsVariables": MAC_DEPS_VARIABLES,
            "dependencies": lock["dependencies"],
            "gitDependencies": [],
            "cipd": lock["cipd"],
            "developmentBuildArguments": lock["developmentBuildArguments"],
            "performanceBuildArguments": lock["performanceBuildArguments"],
        }
    path = HOSTS / f"{host}.json"
    if not path.is_file():
        raise SystemExit(f"No host profile at {path.relative_to(REPO)}")
    return json.loads(path.read_text(encoding="utf-8"))


def executable(name: str, host: str) -> str:
    """A program's file name on `host`."""
    return f"{name}.exe" if is_windows(host) else name


def gn(source: Path, host: str) -> Path:
    """The GN binary preparation puts beside the build output."""
    return source / "out/CrestBaseline" / executable("gn", host)


def patch_tool() -> str:
    """GNU patch. Windows has none of its own; Git for Windows carries it."""
    found = shutil.which("patch")
    if found:
        return found
    git = shutil.which("git")
    if git:
        for candidate in (Path(git).resolve().parents[1] / "usr/bin/patch.exe",
                          Path(git).resolve().parents[2] / "usr/bin/patch.exe"):
            if candidate.is_file():
                return str(candidate)
    raise SystemExit("GNU patch is required; on Windows install Git for Windows, which carries it")


def visual_studio() -> Path:
    """The newest Visual Studio with the C++ tools, which Chromium's Windows
    build locates its compiler libraries and SDK through."""
    installer = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not installer.is_file():
        raise SystemExit("Visual Studio is not installed; Chromium's Windows build needs Visual Studio 2026 with C++")
    found = subprocess.run([str(installer), "-latest", "-prerelease", "-products", "*", "-requires",
                            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
                           capture_output=True, text=True, check=True).stdout.strip()
    if not found:
        raise SystemExit("No Visual Studio installation has the C++ tools Chromium needs")
    return Path(found)


def build_environment(host: str, source: Path) -> dict:
    """The environment GN and the build run in. On Windows, Chromium uses the
    installed Visual Studio rather than Google's internal toolchain package,
    and its build steps that run `python3` by name, which depot_tools would
    provide, find the build's own Python that DEPS pins."""
    environment = dict(os.environ)
    if is_windows(host):
        studio = visual_studio()
        environment["DEPOT_TOOLS_WIN_TOOLCHAIN"] = "0"
        environment["vs2026_install"] = str(studio)
        environment["PYTHONUTF8"] = "1"
        python = source / "third_party/cpython3/host/bin"
        environment["PATH"] = f"{python}{os.pathsep}{environment.get('PATH', '')}"
    return environment


def gn_arguments(host: str) -> list:
    """What every `gn gen` adds for `host`. Chromium's `.gn` runs scripts with
    `python3`, which depot_tools provides on Windows; a tarball build has no
    depot_tools, so GN takes the Python running these scripts."""
    import sys
    return [f"--script-executable={sys.executable}"] if is_windows(host) else []
