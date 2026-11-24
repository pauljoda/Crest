#!/usr/bin/env python3
"""Select a reproducible configuration in an idle Chromium output.

On the Mac, each architecture the engine ships builds in its own output
directory of the same prepared source, as source.lock.json's `architectures`
names it. The arm64 output is the one preparation generates; another
architecture's output is created beside it the first time it is configured.
Every other host, with a profile in CrestEngines/Chromium/Hosts, builds its one
architecture in out/CrestBaseline.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chromium_host  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--configuration", required=True, choices=["development", "performance"])
    parser.add_argument("--sdk", type=Path, help="Compatible macOS SDK; required for performance builds")
    parser.add_argument("--pgo-profile", type=Path,
                        help="The architecture's pinned profile; required for performance builds")
    parser.add_argument("--cpu", default="arm64", help="The Mac architecture to configure, as the lock names it")
    parser.add_argument("--host", help="The host profile to configure for (default: this machine's)")
    args = parser.parse_args()
    source = args.source.resolve()
    if source == REPO or REPO in source.parents:
        parser.error("Chromium sources and products must be outside Crest")
    host = args.host or chromium_host.detected()
    lock = json.loads((REPO / "CrestEngines/Chromium/source.lock.json").read_text(encoding="utf-8"))
    host_profile = chromium_host.profile(host, lock)
    if host == chromium_host.MAC:
        if args.cpu not in lock["architectures"]:
            parser.error(f"The lock builds {', '.join(lock['architectures'])}, not {args.cpu}")
        architecture = lock["architectures"][args.cpu]
        output_name = architecture["output"]
        # Preparation bootstraps GN and installs it where DEPS would.
        gn = source / "buildtools/mac/gn"
        if not gn.is_file() or not (source / "out/CrestBaseline/args.gn").is_file():
            parser.error("Prepare the pinned source before configuring it")
        settings = {"target_cpu": args.cpu, **lock["buildArguments"], **host_profile[f"{args.configuration}BuildArguments"]}
    else:
        # Every other host builds its one architecture in the output preparation made.
        architecture = None
        output_name = "out/CrestBaseline"
        gn = chromium_host.gn(source, host)
        if not (source / output_name / "args.gn").is_file() or not gn.is_file():
            parser.error("Prepare the pinned source before configuring it")
        settings = {**lock["buildArguments"], **host_profile[f"{args.configuration}BuildArguments"]}
    output = source / output_name
    arguments = output / "args.gn"
    if not arguments.is_file():
        output.mkdir(parents=True, exist_ok=True)
        arguments.write_text("", encoding="utf-8")
    if args.configuration == "performance" and host != chromium_host.MAC:
        if args.sdk or args.pgo_profile:
            parser.error("--sdk and --pgo-profile apply to the Mac host")
    elif args.configuration == "performance":
        if args.sdk is None or args.pgo_profile is None:
            parser.error("Performance builds require --sdk and --pgo-profile")
        sdk = args.sdk.resolve()
        profile = args.pgo_profile.resolve()
        sdk_settings = sdk / "SDKSettings.json"
        if not sdk_settings.is_file() or not profile.is_file():
            parser.error("SDK or PGO profile is missing")
        expected = lock["performanceInputs"]
        if json.loads(sdk_settings.read_text())["Version"] != expected["macSDKVersion"]:
            parser.error(f"Use the compatible macOS {expected['macSDKVersion']} SDK")
        profile_name = (source / architecture["pgoProfileFile"]).read_text().strip()
        if profile_name != architecture["pgoProfile"] or profile.name != profile_name:
            parser.error("PGO profile does not match the pinned Chromium source")
        with profile.open("rb") as stream:
            checksum = hashlib.file_digest(stream, "sha256").hexdigest()
        if checksum != architecture["pgoSHA256"]:
            parser.error("PGO profile checksum does not match the lock")
        if not (source / "v8/tools/builtins-pgo/profiles/x64.profile").is_file():
            parser.error("V8 builtin optimization profile is missing")
        # Chromium declares SDK inputs as generated outputs, so its SDK alias
        # must live beneath root_build_dir, just like sdk_info.py's aliases.
        # V8's metagen queries GN from a copy of the build directory that
        # carries only `xcode_links`, so the alias lives there too.
        sdk_link = output / "xcode_links/crest" / sdk.name
        if sdk_link.exists() or sdk_link.is_symlink():
            if not sdk_link.is_symlink() or sdk_link.resolve() != sdk:
                parser.error(f"SDK alias already belongs to another path: {sdk_link}")
        else:
            sdk_link.parent.mkdir(parents=True, exist_ok=True)
            sdk_link.symlink_to(sdk, target_is_directory=True)
        settings.update(mac_sdk_path=f"//{sdk_link.relative_to(source).as_posix()}",
                        pgo_data_path=str(profile))
    elif args.sdk or args.pgo_profile:
        parser.error("--sdk and --pgo-profile apply only to performance builds")

    # Replace only the lock's scalar arguments, including prior duplicates.
    # Keep independent flags a contributor added for a local build.
    owned = set(lock["buildArguments"]) | set(host_profile["developmentBuildArguments"]) | set(host_profile["performanceBuildArguments"])
    owned.update(["mac_sdk_path", "pgo_data_path"])
    if host == chromium_host.MAC:
        owned.add("target_cpu")
    previous = arguments.read_text(encoding="utf-8")
    retained = []
    for line in previous.splitlines():
        assignment = re.match(r"\s*([a-zA-Z_][a-zA-Z_0-9]*)\s*=", line)
        if assignment is None or assignment[1] not in owned:
            retained.append(line)
    configured = "\n".join(retained).rstrip() + "\n\n"
    configured += "\n".join(f"{key}={json.dumps(value)}" for key, value in settings.items()) + "\n"
    arguments.write_text(configured, encoding="utf-8", newline="\n")
    command = [str(gn), "gen", output_name, "--fail-on-unused-args", *chromium_host.gn_arguments(host)]
    environment = chromium_host.build_environment(host, source)
    try:
        subprocess.run(command, cwd=source, check=True, env=environment)
    except subprocess.CalledProcessError:
        arguments.write_text(previous, encoding="utf-8", newline="\n")
        subprocess.run(command, cwd=source, check=True, env=environment)
        raise
    print(f"Configured {args.configuration} {args.cpu if host == chromium_host.MAC else host} in {output_name}; rebuild chrome there.")


if __name__ == "__main__":
    main()
