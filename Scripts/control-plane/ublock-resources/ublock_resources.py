#!/usr/bin/env python3
"""Build and publish the resources Crest's content filter loads for scriptlets.

Scriptlets (`##+js(...)`) and redirect filters (`$redirect=`) name resources
that uBlock Origin ships under GPL-3.0. Crest never compiles them in: the core
downloads one JSON file, in adblock-rust's resource format, from a release of
this repository, the way it downloads filter lists. `build` makes that file
from the uBlock Origin release `resources.lock.json` pins, verified against
the source's digest, with `generate.mjs`, and checks it against the lock's
digest, so a build always produces the published bytes. `publish` releases it
with uBlock Origin's licence and a pointer to its source, once per tag; a
release that holds anything else is never replaced. Node.js runs the
generator.

The core names the release in `FilterLibrary.ResourcesRelease` and pins the
asset's digest in `FilterLibrary.ResourcesSHA256`, refusing any other bytes; a
new uBlock Origin release, or a change to the generator, changes the lock and
both constants in one reviewed commit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[2]
LOCK = HERE / "resources.lock.json"
LIBRARY = REPOSITORY / "CrestCore/src/CrestCore/Application/ContentBlocking/FilterLibrary.cs"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_lock() -> dict:
    return json.loads(LOCK.read_text())


def check_core(lock: dict):
    """The core downloads the release the lock names and loads only the bytes
    the lock records, refusing any other."""
    library = LIBRARY.read_text()
    if f'ResourcesRelease = "{lock["tag"]}"' not in library:
        raise SystemExit(f"FilterLibrary.ResourcesRelease does not name {lock['tag']}; update both together.")
    if f'ResourcesSHA256 = "{lock["assetSHA256"]}"' not in library:
        raise SystemExit("FilterLibrary.ResourcesSHA256 does not pin the lock's asset digest; update both together.")


def fetch_source(lock: dict, folder: Path) -> Path:
    archive = folder / "ublock.tar.gz"
    with urllib.request.urlopen(lock["source"], timeout=120) as response:
        archive.write_bytes(response.read())
    if sha256(archive) != lock["sourceSHA256"]:
        raise SystemExit(f"uBlock Origin {lock['ublock']} does not match the lock's source digest.")
    source = folder / "source"
    source.mkdir()
    with tarfile.open(archive) as bundle:
        for member in bundle.getmembers():
            target = (source / member.name).resolve()
            if not (member.isfile() or member.isdir()) or source.resolve() not in target.parents:
                continue
            bundle.extract(member, source)
    roots = [path for path in source.iterdir() if path.is_dir()]
    if len(roots) != 1:
        raise SystemExit("The uBlock Origin archive has an unexpected layout.")
    return roots[0]


def build(lock: dict, folder: Path, update: bool) -> tuple[Path, Path]:
    """The generated resources and uBlock Origin's licence, in `folder`."""
    source = fetch_source(lock, folder)
    output = folder / lock["asset"]
    subprocess.run(["node", str(HERE / "generate.mjs"), str(source), str(output)], check=True)
    digest = sha256(output)
    if digest != lock["assetSHA256"]:
        if not update:
            raise SystemExit(f"The generated resources hash to {digest}, not the lock's {lock['assetSHA256']}.")
        lock["assetSHA256"] = digest
        LOCK.write_text(json.dumps(lock, indent=2) + "\n")
        print(f"Updated {LOCK.relative_to(REPOSITORY)} to {digest}.")
    return output, source / "LICENSE.txt"


def published(lock: dict, repository: str) -> list[str] | None:
    """The assets of the lock's release, or None when there is no release."""
    result = subprocess.run(["gh", "release", "view", lock["tag"], "--repo", repository, "--json", "assets"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return [asset["name"] for asset in json.loads(result.stdout)["assets"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    build_command = commands.add_parser("build", help="Build the resources and check them against the lock")
    build_command.add_argument("--output", type=Path, help="Copy the built file here")
    build_command.add_argument("--update", action="store_true", help="Record a new digest in the lock")
    publish_command = commands.add_parser("publish", help="Build and release the resources once per tag")
    publish_command.add_argument("--repository", default="pauljoda/Crest")
    publish_command.add_argument("--dry-run", action="store_true", help="Verify without uploading")
    commands.add_parser("url", help="Print the address the core downloads")
    args = parser.parse_args()

    lock = read_lock()
    check_core(lock)
    if args.command == "url":
        print(f"https://github.com/pauljoda/Crest/releases/download/{lock['tag']}/{lock['asset']}")
        return
    with tempfile.TemporaryDirectory(prefix="crest-ublock-") as temporary:
        folder = Path(temporary)
        output, licence = build(lock, folder, getattr(args, "update", False))
        if args.command == "build":
            if args.output:
                args.output.write_bytes(output.read_bytes())
            print(f"Built {lock['asset']} ({lock['assetSHA256'][:16]}) from uBlock Origin {lock['ublock']}.")
            return
        assets = published(lock, args.repository)
        if assets is not None:
            if lock["asset"] not in assets:
                raise SystemExit(f"Release {lock['tag']} exists without {lock['asset']}; fix it by hand.")
            print(f"{lock['tag']} is already released.")
            return
        if args.dry_run:
            print(f"Would release {lock['tag']} with {lock['asset']} and uBlock Origin's licence.")
            return
        licence_copy = folder / "uBlock-Origin-LICENSE.txt"
        licence_copy.write_bytes(licence.read_bytes())
        notes = (f"Scriptlet and redirect resources for Crest's content filter, converted from uBlock Origin "
                 f"{lock['ublock']} ({lock['source']}, SHA-256 {lock['sourceSHA256']}) by "
                 f"Scripts/control-plane/ublock-resources/generate.mjs. uBlock Origin's resources are licensed "
                 f"under the GNU General Public License v3.0; its licence is attached. Crest downloads this file "
                 f"at runtime as data.")
        subprocess.run(["gh", "release", "create", lock["tag"], "--repo", args.repository,
                        "--title", f"uBlock Origin resources {lock['ublock']}", "--notes", notes, "--latest=false",
                        str(output), str(licence_copy)], check=True)
        print(f"Released {lock['tag']}.")


if __name__ == "__main__":
    sys.exit(main())
