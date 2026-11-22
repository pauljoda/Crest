#!/usr/bin/env python3
"""Publish the native core for the Mac: a NativeAOT library for each
architecture, combined into one library that holds them all.

The Xcode build's core phase (build-apple-core.py) publishes the
architectures its build asks for. A release, the local install and the review
targets call this directly for the universal library:

    python3 Scripts/control-plane/mac_core.py [--output DIR] [--architectures arm64 x86_64]
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

REPOSITORY = Path(__file__).resolve().parents[2]
# Each Mac architecture Crest ships, with the .NET runtime that builds it.
RUNTIMES = {"arm64": "osx-arm64", "x86_64": "osx-x64"}
LIBRARY = "CrestCore.Native.dylib"
DEFAULT_OUTPUT = REPOSITORY / "CrestCore/artifacts/mac-core"


def dotnet_path():
    """The .NET SDK the core builds with, or None without one."""
    candidates = [os.environ.get("CREST_DOTNET"), shutil.which("dotnet"),
                  str(Path.home() / ".dotnet/dotnet"), "/usr/local/share/dotnet/dotnet"]
    return next((p for p in candidates if p and Path(p).is_file()), None)


def publish(dotnet, output: Path, architectures=tuple(RUNTIMES), environment=None, cross_checks=False) -> Path:
    """Publishes the core for each of `architectures` under `output`, and
    answers the library there that holds every one of them."""
    unknown = [architecture for architecture in architectures if architecture not in RUNTIMES]
    if unknown or not architectures:
        raise RuntimeError(f"The Mac core builds for {', '.join(RUNTIMES)}, not {' '.join(architectures) or 'nothing'}")
    slices = []
    for architecture in architectures:
        runtime = RUNTIMES[architecture]
        published = output / f"publish-{runtime}"
        subprocess.run([dotnet, "publish", "src/CrestCore.Native", "-c", "Release", "-r", runtime,
                        "--artifacts-path", str(output / "intermediates"), "-o", str(published), "--nologo",
                        f"-p:CrestCrossChecks={'true' if cross_checks else 'false'}"],
                       cwd=REPOSITORY / "CrestCore", env=environment, check=True)
        slices.append(published / LIBRARY)
    library = output / LIBRARY
    pending = library.with_suffix(".pending")
    if len(slices) == 1:
        shutil.copy2(slices[0], pending)
    else:
        subprocess.run(["lipo", "-create", *map(str, slices), "-output", str(pending)], check=True)
    pending.replace(library)
    return library


def architectures_of(library: Path) -> set:
    """The architectures `library` holds."""
    return set(subprocess.check_output(["lipo", "-archs", str(library)], text=True).split())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Where the library goes")
    parser.add_argument("--architectures", nargs="+", default=list(RUNTIMES), choices=list(RUNTIMES))
    args = parser.parse_args()
    dotnet = dotnet_path()
    if dotnet is None:
        sys.exit("Install the SDK in CrestCore/global.json, or run Scripts/control-plane/install-dotnet.sh")
    library = publish(dotnet, args.output.resolve(), tuple(args.architectures))
    print(library)


if __name__ == "__main__":
    main()
