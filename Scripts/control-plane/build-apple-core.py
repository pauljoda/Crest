#!/usr/bin/env python3
"""Build the native core for an Xcode target, reusing that build's derived data."""

import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_filter  # noqa: E402
import mac_core  # noqa: E402


def main():
    repo = Path(__file__).resolve().parents[2]
    platform = os.environ["PLATFORM_NAME"]
    architectures = tuple(os.environ.get("ARCHS", "arm64").split())
    # The Mac builds each architecture its build asks for; iOS builds arm64.
    runtimes = {"iphoneos": "ios-arm64", "iphonesimulator": "iossimulator-arm64"}
    if platform == "macosx":
        if not architectures or not set(architectures) <= set(mac_core.RUNTIMES):
            raise RuntimeError(f"The Crest core builds the Mac for {', '.join(mac_core.RUNTIMES)}, "
                               f"not {' '.join(architectures)}")
    elif platform not in runtimes or architectures != ("arm64",):
        raise RuntimeError("The Crest core builds arm64 iOS and arm64 iOS Simulator apps")
    default = Path(os.environ["BUILT_PRODUCTS_DIR"]) / "CrestCore"
    key = "CREST_CORE_LIBRARY_DIR" if platform == "macosx" else "CREST_CORE_FRAMEWORK_DIR"
    output = Path(os.environ[key]).resolve()
    product = output / (mac_core.LIBRARY if platform == "macosx" else "CrestCoreABI.framework/CrestCoreABI")
    if output != default.resolve():
        if not product.is_file():
            raise RuntimeError(f"Explicit {key} has no core library: {product}")
        if platform == "macosx" and not set(architectures) <= mac_core.architectures_of(product):
            raise RuntimeError(f"Explicit {key} lacks {' '.join(architectures)}: {product}")
        print(f"Using explicitly supplied core: {product}")
        return
    dotnet = mac_core.dotnet_path()
    if not dotnet:
        raise RuntimeError("Install the SDK in CrestCore/global.json, or run Scripts/control-plane/install-dotnet.sh")
    core = repo / "CrestCore"
    # MSBuild imports environment names case-insensitively as project properties.
    # Xcode's TARGETNAME otherwise renames every referenced assembly to Crest.
    inherited = {"PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "SHELL", "LANG", "DEVELOPER_DIR",
                 "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy"}
    # The content filter's own settings, and where Rust lives, reach its fetch.
    inherited |= {"CREST_CONTENT_FILTER_FROM_SOURCE", "CREST_CONTENT_FILTER_REPOSITORY", "CARGO_HOME", "RUSTUP_HOME"}
    environment = {k: v for k, v in os.environ.items()
                   if k in inherited or k.startswith(("DOTNET_", "NUGET_", "LC_"))}
    environment["SDKROOT"] = subprocess.check_output(
        ["xcrun", "--sdk", platform, "--show-sdk-path"], text=True).strip()
    version = subprocess.check_output([dotnet, "--version"], cwd=core, env=environment, text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", platform, "--show-sdk-version"], text=True).strip()
    inputs = [p for folder in ("src", "tools") for p in (core / folder).rglob("*") if p.is_file()
              and not {"bin", "obj"}.intersection(p.relative_to(core).parts)]
    inputs += list((repo / "CrestShared/Infrastructure/Core/Generated").glob("*.swift"))
    inputs += list(core.glob("Directory.*")) + [core / "global.json", Path(__file__).resolve(),
                                               repo / "Scripts/control-plane/package-apple-core.py",
                                               repo / "Scripts/control-plane/mac_core.py"]
    # The content filter library the core links: the one its lock names, or
    # its sources compiled while they differ from the lock.
    for name in content_filter.INPUTS + (content_filter.LOCK, "Scripts/control-plane/fetch-content-filter.py"):
        path = repo / name
        inputs += [p for p in path.rglob("*") if p.is_file()] if path.is_dir() else [path]
    digest = hashlib.sha256(f"{version}:{platform}:{sdk}:{os.environ.get('DEVELOPER_DIR', '')}:"
                            f"{os.environ.get('CREST_CONTENT_FILTER_FROM_SOURCE', '')}".encode())
    for path in sorted(inputs):
        digest.update(str(path.relative_to(repo)).encode())
        digest.update(path.read_bytes())
    # A Debug app's core runs the core's cross-checks, which Release builds leave out.
    cross_checks = os.environ.get("CONFIGURATION") == "Debug"
    digest.update(f"cross-checks:{cross_checks}".encode())
    digest.update(f"architectures:{' '.join(architectures)}".encode())
    fingerprint = digest.hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    # App and framework targets can request the same core in a parallel build.
    with (output / ".build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = output / ".source-hash"
        if product.is_file() and stamp.exists() and stamp.read_text() == fingerprint:
            built = " ".join(architectures) if platform == "macosx" else runtimes[platform]
            print(f"Crest core is current ({built}, SDK {version})")
            return
        # The Swift models and codecs are generated from the same contract
        # records; a stale copy would misread the core, so refuse to build.
        subprocess.run([dotnet, "run", "--project", "tools/CrestCore.Generator", "--nologo", "--",
                        "--check", "--root", str(repo)], cwd=core, env=environment, check=True)
        if platform == "macosx":
            mac_core.publish(dotnet, output, architectures, environment, cross_checks)
        else:
            publish = output / "publish"
            subprocess.run([dotnet, "publish", "src/CrestCore.Native", "-c", "Release", "-r", runtimes[platform],
                            "--artifacts-path", str(output / "intermediates"), "-o", str(publish), "--nologo",
                            f"-p:CrestCrossChecks={'true' if cross_checks else 'false'}",
                            "-p:PublishAotUsingRuntimePack=true"],
                           cwd=core, env=environment, check=True)
            framework = output / "CrestCoreABI.framework"
            if framework.exists():
                shutil.rmtree(framework)
            subprocess.run([sys.executable, str(repo / "Scripts/control-plane/package-apple-core.py"),
                            "--library", str(publish / "CrestCore.Native.dylib"), "--output", str(framework),
                            "--platform", platform], check=True)
        stamp.write_text(fingerprint)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: Crest core build failed: {error}")
