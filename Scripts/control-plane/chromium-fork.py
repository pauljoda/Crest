#!/usr/bin/env python3
"""Manage Crest's Chromium fork without relying on an agent's temporary directory."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import shutil

from chromium_fork import (ENGINE, REPO, Workspace, exclusive_workspace, prepare_update,
                           read_json, release_version, run, select_update, sha256,
                           upstream_releases, write_json)
import chromium_engine


def adopt(workspace, source):
    """Move an existing prepared source and build on the same volume into the workspace."""
    source = source.expanduser().resolve()
    if source == workspace.source:
        raise ValueError("This source is already in the managed workspace")
    processes = run("ps", "-axo", "comm=,args=", capture=True)
    for line in processes.splitlines():
        command = line.split()[0] if line.split() else ""
        if Path(command).name in ("ninja", "autoninja", "clang", "clang++", "rustc"):
            raise ValueError("Wait for active Chromium/compiler processes to finish before adopting the build")
    workspace.script("prepare-chromium.py", "--source", source, "--verify-only")
    validation = workspace.script("apply-chromium-host.py", "--source", source, capture=True)
    if "(after)" not in validation:
        raise ValueError("Adoption requires the current Crest host to be installed")
    for path in (REPO / ENGINE / "Overlay").rglob("*"):
        if path.is_file() and sha256(source / path.relative_to(REPO / ENGINE / "Overlay")) != sha256(path):
            raise ValueError(f"Source overlay differs from Crest: {path}")
    if workspace.directory.exists():
        raise ValueError(f"Destination already exists: {workspace.directory}")
    workspace.directory.mkdir(parents=True)
    # rename on the same volume preserves all output files without a second copy.
    source.rename(workspace.source)
    try:
        source.symlink_to(workspace.source, target_is_directory=True)
    except BaseException:
        workspace.source.rename(source)
        raise
    write_json(workspace.directory / "prepared.json", {"preparationKey": workspace.key})
    host = REPO / ENGINE
    overlay = {p.relative_to(host / "Overlay").as_posix(): sha256(p)
               for p in (host / "Overlay").rglob("*") if p.is_file()}
    write_json(workspace.directory / "host.json", {
        "patch": chromium_engine.host_patch(REPO),
        "inputs": read_json(host / "host-inputs.json"), "overlay": overlay,
    })
    write_json(workspace.root / "adoption.json", {"previousPath": str(source), "source": str(workspace.source)})
    print(f"Moved build to {workspace.source}; retained compatibility link at {source}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path,
                        default=Path(os.environ.get("CREST_CHROMIUM_WORKSPACE") or Path.home() / "Dev/CrestChromium"))
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    check = commands.add_parser("check-upstream")
    check.add_argument("--allow-major", action="store_true")
    adoption = commands.add_parser("adopt")
    adoption.add_argument("--source", type=Path, required=True)
    for name in ("build", "update"):
        build = commands.add_parser(name)
        build.add_argument("--sdk", type=Path, required=True)
        build.add_argument("--ninja", type=Path, default=Path(shutil.which("ninja") or "ninja"))
        build.add_argument("--jobs", type=int, default=4)
        build.add_argument("--min-free-gib", type=int, default=15)
        if name == "update":
            build.add_argument("--version", required=True, help="A Chrome release on the fork's channel")
            build.add_argument("--allow-major", action="store_true")
    args = parser.parse_args()
    workspace = Workspace(args.workspace)
    policy = read_json(REPO / ENGINE / "fork.json")
    if args.command == "status":
        key = chromium_engine.engine_key(REPO)
        print(json.dumps({"workspace": str(workspace.root), "source": str(workspace.source),
                          "prepared": (workspace.directory / "prepared.json").exists(),
                          "chromium": workspace.lock["chromium"]["version"],
                          "engineKey": key, "engineTag": chromium_engine.release_tag(key),
                          "policy": policy}, indent=2))
        return
    if args.command == "check-upstream":
        result = select_update(workspace.lock["chromium"]["version"], upstream_releases(policy), args.allow_major)
        print(json.dumps(result, indent=2))
        return
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("Engine preparation and builds require an Apple Silicon Mac")
    with exclusive_workspace(workspace.root):
        if args.command == "adopt":
            adopt(workspace, args.source)
            return
        if args.command == "update":
            current = workspace.lock["chromium"]["version"]
            if args.version not in upstream_releases(policy):
                parser.error(f"{args.version} is not a {policy['upstream']['channel']} release")
            if not args.allow_major and release_version(args.version)[0] != release_version(current)[0]:
                parser.error("Select a release on the current milestone, or explicitly pass --allow-major")
            if run("git", "-C", REPO, "status", "--porcelain", capture=True).strip():
                parser.error("Start an upstream update from a clean Crest checkout")
            workspace = prepare_update(REPO, workspace.root, args.version)
        workspace.build(args.sdk, args.ninja.resolve(), args.jobs, args.min_free_gib)
        key = chromium_engine.engine_key(REPO)
        receipt = {"engineKey": key, "chromium": workspace.lock["chromium"]["version"],
                   "source": str(workspace.source), "configuration": "performance",
                   "argsSHA256": sha256(workspace.source / "out/CrestBaseline/args.gn"),
                   "commit": run("git", "-C", REPO, "rev-parse", "HEAD", capture=True).strip()}
        write_json(workspace.root / "last-build.json", receipt)
        print(json.dumps(receipt, indent=2))
        if output := os.environ.get("GITHUB_OUTPUT"):
            with Path(output).open("a") as stream:
                stream.write(f"source={workspace.source}\nengine_tag={chromium_engine.release_tag(key)}\n")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
