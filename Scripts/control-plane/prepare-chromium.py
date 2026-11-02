#!/usr/bin/env python3
"""Verify the pinned Chromium source archive and prepare a new source directory."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

REPO = Path(__file__).resolve().parents[2]
ENGINE = REPO / "CrestEngines/Chromium"
# A tarball build: what gclient sets for a checkout that is not a Git tree.
DEPS_VARIABLES = {"host_os": "mac", "host_cpu": "arm64", "checkout_mac": True, "checkout_arm64": True,
                  "non_git_source": True}


def run(args, cwd):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fetch(url, destination, sha256):
    """Download `url` once into the shared cache and verify it against its pin."""
    if destination.is_file() and digest(destination) == sha256:
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(destination.name + ".partial")
    try:
        with urllib.request.urlopen(url, timeout=300) as response, partial.open("wb") as output:
            shutil.copyfileobj(response, output)
        if digest(partial) != sha256:
            raise SystemExit(f"Downloaded file does not match its pinned digest: {url}")
        partial.replace(destination)
    finally:
        partial.unlink(missing_ok=True)
    return destination


def extract(archive, destination, strip=None):
    """Unpack a tar archive beneath `destination`, refusing members that leave it."""
    root = destination.resolve()
    with tarfile.open(archive) as stream:
        members = []
        for member in stream.getmembers():
            name = Path(member.name)
            if strip is not None:
                if name.parts[:1] != (strip,):
                    raise SystemExit(f"Unexpected archive member outside {strip}: {member.name}")
                name = Path(*name.parts[1:])
                if not name.parts:
                    continue
                member.name = str(name)
            if member.issym() or member.islnk():
                target = (root / name).parent / member.linkname
                if root not in target.resolve().parents and target.resolve() != root:
                    raise SystemExit(f"Archive link leaves its directory: {member.name}")
            if name.is_absolute() or ".." in name.parts:
                raise SystemExit(f"Invalid archive member: {member.name}")
            members.append(member)
        stream.extractall(destination, members=members, filter="tar")


def unzip(archive, destination):
    """Unpack a CIPD package, keeping its file modes and links inside `destination`."""
    root = destination.resolve()
    destination.mkdir(parents=True)
    with zipfile.ZipFile(archive) as stream:
        for item in stream.infolist():
            name = Path(item.filename)
            target = root / name
            if name.is_absolute() or ".." in name.parts or root not in target.parents:
                raise SystemExit(f"Invalid package member: {item.filename}")
            mode = item.external_attr >> 16
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif stat.S_ISLNK(mode):
                link = stream.read(item).decode()
                if root not in (target.parent / link).resolve().parents:
                    raise SystemExit(f"Package link leaves its directory: {item.filename}")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(link)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with stream.open(item) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(stat.S_IMODE(mode) or 0o644)


def deps_dependencies(source):
    """The Google Storage dependencies DEPS pins, evaluated for this host.

    DEPS belongs to the verified source archive, so each object's digest is
    pinned by the archive's own checksum.
    """
    scope = {}
    exec((source / "DEPS").read_text(), {"Var": lambda name: "{" + name + "}", "Str": str}, scope)

    class Variables(dict):
        def __missing__(self, _):
            return False

    def applies(condition):
        return not condition or bool(eval(condition, {"__builtins__": {}}, Variables(DEPS_VARIABLES)))

    dependencies = {}
    for path, dependency in scope["deps"].items():
        if isinstance(dependency, dict) and dependency.get("dep_type") == "gcs" and applies(dependency.get("condition")):
            objects = [item for item in dependency["objects"] if applies(item.get("condition"))]
            dependencies[path] = (dependency["bucket"], objects)
    return dependencies


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="New directory for the expanded source")
    parser.add_argument("--downloads", type=Path, help="Shared download cache; required to prepare")
    parser.add_argument("--verify-only", action="store_true", help="Check the Crest patches the lock pins")
    args = parser.parse_args()
    source = args.source.resolve()
    if source == REPO or REPO in source.parents:
        parser.error("The Chromium source must be outside Crest")
    lock = json.loads((ENGINE / "source.lock.json").read_text())
    for relative, expected in lock["crestPatches"].items():
        if digest(ENGINE / relative) != expected:
            parser.error(f"Crest patch changed: {relative}")
    if args.verify_only:
        version = source / "chrome/VERSION"
        if not version.is_file():
            parser.error("No prepared source at that path")
        parts = dict(line.split("=", 1) for line in version.read_text().split())
        if ".".join(parts[name] for name in ("MAJOR", "MINOR", "BUILD", "PATCH")) != lock["chromium"]["version"]:
            parser.error("The prepared source is a different Chromium version")
        print("The prepared source and Crest build patches match the lock.")
        return
    if source.exists():
        parser.error("Source directory already exists; use --verify-only or a new directory")
    if args.downloads is None:
        parser.error("Preparation requires --downloads")
    downloads = args.downloads.resolve()
    chromium = lock["chromium"]
    archive = fetch(chromium["sourceArchive"], downloads / Path(chromium["sourceArchive"]).name,
                    chromium["sourceArchiveSha256"])
    staging = source.with_name(source.name + ".partial")
    if staging.exists():
        parser.error(f"Inspect the incomplete preparation at {staging} before removing it")
    staging.mkdir(parents=True)
    extract(archive, staging, strip=f"chromium-{chromium['version']}")

    # The archive is exported on Linux: it carries Linux copies of a few
    # toolchain dependencies and none of the Mac toolchains.
    available = deps_dependencies(staging)
    for path in lock["dependencies"]:
        if path not in available or not available[path][1]:
            parser.error(f"DEPS no longer pins {path} for this host")
        bucket, objects = available[path]
        destination = staging / path.removeprefix("src/")
        if destination.exists():
            shutil.rmtree(destination)
        destination.mkdir(parents=True)
        for item in objects:
            name = item.get("output_file") or Path(item["object_name"]).name
            cached = fetch(f"https://storage.googleapis.com/{bucket}/{item['object_name']}",
                           downloads / bucket / item["sha256sum"] / name, item["sha256sum"])
            if tarfile.is_tarfile(cached):
                extract(cached, destination)
            else:
                shutil.copyfile(cached, destination / name)

    # DEPS names these host tools only by CIPD version tag, so the lock pins
    # each package's instance digest: the build's Python, and the esbuild and
    # TypeScript compilers DevTools and the WebUI use.
    for path, package in lock["cipd"].items():
        # A CIPD instance ID is the package digest, URL-safe Base64 with a
        # suffix naming SHA-256, so the download is addressed by its content.
        instance = base64.urlsafe_b64encode(bytes.fromhex(package["sha256"])).decode().rstrip("=") + "C"
        url = f"https://chrome-infra-packages.appspot.com/dl/{package['package']}/+/{instance}"
        download = fetch(url, downloads / "cipd" / package["sha256"] / "package.zip", package["sha256"])
        destination = staging / path.removeprefix("src/")
        if destination.exists():
            shutil.rmtree(destination)
        unzip(download, destination)

    for relative in lock["crestPatches"]:
        run(["patch", "-p1", "--forward", "--fuzz=0", "--input", ENGINE / relative], staging)

    # Generated build files name their source directory, so the tree takes
    # its final path before GN runs.
    staging.rename(source)
    output = source / "out/CrestBaseline"
    output.mkdir(parents=True)
    flags = {**lock["buildArguments"], **lock["developmentBuildArguments"]}
    (output / "args.gn").write_text("".join(f"{key}={json.dumps(value)}\n" for key, value in flags.items()))
    run([sys.executable, source / "tools/gn/bootstrap/bootstrap.py", "-o", "out/CrestBaseline/gn",
         "--skip-generate-buildfiles"], source)
    # Build steps such as V8's metagen run gn where DEPS installs it.
    (source / "buildtools/mac").mkdir(exist_ok=True)
    shutil.copy2(output / "gn", source / "buildtools/mac/gn")
    run([output / "gn", "gen", "out/CrestBaseline", "--fail-on-unused-args"], source)
    print("Source prepared. Run build-chromium-baseline.py against it.")


if __name__ == "__main__":
    main()
