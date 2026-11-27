#!/usr/bin/env python3
"""Verify the pinned Chromium source archive and prepare a new source directory."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import time
import urllib.request
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chromium_host  # noqa: E402

REPO = chromium_host.REPO
ENGINE = chromium_host.ENGINE


def run(args, cwd, environment=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True, env=environment)


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


def copy_links(links, root):
    """Puts a copy of what each link names in its place. Windows makes
    symbolic links only for administrators and in Developer Mode, so a link
    an archive or package carries becomes a copy there. A link to a link waits
    for the one it names."""
    pending = list(links)
    while pending:
        remaining = []
        for place, target in pending:
            if target.is_dir():
                shutil.copytree(target, place, dirs_exist_ok=True)
            elif target.is_file():
                place.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(target, place)
            else:
                remaining.append((place, target))
        if len(remaining) == len(pending):
            for place, target in remaining:
                print(f"Skipped a link to nothing: {place.relative_to(root)} -> {target}", file=sys.stderr)
            return
        pending = remaining


def extract(archive, destination, strip=None):
    """Unpack a tar archive beneath `destination`, refusing members that leave it."""
    root = destination.resolve()
    links = []
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
                member.name = name.as_posix()
            if name.is_absolute() or ".." in name.parts:
                raise SystemExit(f"Invalid archive member: {member.name}")
            if member.issym() or member.islnk():
                linked = member.linkname
                if member.islnk() and strip is not None:
                    linked = linked.removeprefix(f"{strip}/")
                target = (root / name).parent / linked if member.issym() else root / linked
                if root not in target.resolve().parents and target.resolve() != root:
                    raise SystemExit(f"Archive link leaves its directory: {member.name}")
                if os.name == "nt":
                    links.append((root / name, target.resolve()))
                    continue
            members.append(member)
        stream.extractall(destination, members=members, filter="tar")
    copy_links(links, root)


def unzip(archive, destination):
    """Unpack a CIPD package, keeping its file modes and links inside `destination`."""
    root = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    links = []
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
                if os.name == "nt":
                    links.append((target, (target.parent / link).resolve()))
                else:
                    target.symlink_to(link)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with stream.open(item) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(stat.S_IMODE(mode) or 0o644)
    copy_links(links, root)


def deps_scope(source):
    """DEPS, evaluated. DEPS belongs to the verified source archive, so each
    object's digest and each Git revision is pinned by the archive's checksum."""
    scope = {}
    exec((source / "DEPS").read_text(encoding="utf-8"), {"Var": lambda name: "{" + name + "}", "Str": str}, scope)
    return scope


def condition_check(scope, variables):
    class Variables(dict):
        def __missing__(self, key):
            return scope.get("vars", {}).get(key, False)

    return lambda condition: not condition or bool(eval(condition, {"__builtins__": {}}, Variables(variables)))


def deps_dependencies(scope, variables):
    """The Google Storage dependencies DEPS pins, evaluated for this host."""
    applies = condition_check(scope, variables)
    dependencies = {}
    for path, dependency in scope["deps"].items():
        if isinstance(dependency, dict) and dependency.get("dep_type") == "gcs" and applies(dependency.get("condition")):
            objects = [item for item in dependency["objects"] if applies(item.get("condition"))]
            dependencies[path] = (dependency["bucket"], objects)
    return dependencies


def git_dependency(scope, path):
    """The repository and revision DEPS pins at `path`."""
    dependency = scope["deps"].get(path)
    url = dependency.get("url") if isinstance(dependency, dict) else dependency
    if not url or "@" not in url:
        raise SystemExit(f"DEPS no longer pins a Git revision at {path}")
    variables = scope.get("vars", {})
    for _ in range(4):
        for name, value in variables.items():
            url = url.replace("{" + name + "}", str(value))
    repository, revision = url.rsplit("@", 1)
    if len(revision) != 40:
        raise SystemExit(f"DEPS pins {path} by {revision}, not a commit")
    return repository, revision


def fetch_storage_file(tree, downloads, item):
    """Puts the Google Storage object a hook would fetch at its place in
    `tree`. The archive's `.sha1` file names the object and pins its content."""
    sha1 = (tree / item["sha1File"].removeprefix("src/")).read_text(encoding="utf-8").strip()
    cached = downloads / item["bucket"] / sha1
    if not cached.is_file() or hashlib.sha1(cached.read_bytes()).hexdigest() != sha1:
        cached.parent.mkdir(parents=True, exist_ok=True)
        partial = cached.with_name(cached.name + ".partial")
        with urllib.request.urlopen(f"https://storage.googleapis.com/{item['bucket']}/{sha1}", timeout=300) as response, \
                partial.open("wb") as output:
            shutil.copyfileobj(response, output)
        if hashlib.sha1(partial.read_bytes()).hexdigest() != sha1:
            partial.unlink()
            raise SystemExit(f"Downloaded {item['output']} does not match its pinned SHA-1")
        partial.replace(cached)
    destination = tree / item["output"].removeprefix("src/")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(cached, destination)


def fetch_git(repository, revision, destination):
    """Checks out exactly `revision`, whose hash verifies the content, without
    the repository's history or Git's own files."""
    destination.mkdir(parents=True)
    git = ["git", "-c", "core.autocrlf=false", "-c", "advice.detachedHead=false", "-C", destination]
    run([*git[:5], "init", "--quiet", destination], destination.parent)
    run([*git, "fetch", "--quiet", "--depth", "1", repository, revision], destination)
    run([*git, "checkout", "--quiet", "FETCH_HEAD"], destination)
    checked_out = subprocess.run([*map(str, git), "rev-parse", "HEAD"], capture_output=True, text=True,
                                 check=True).stdout.strip()
    if checked_out != revision:
        raise SystemExit(f"{repository} checked out {checked_out}, not the pinned {revision}")
    shutil.rmtree(destination / ".git", onerror=lambda function, path, _: (os.chmod(path, stat.S_IWRITE), function(path)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="New directory for the expanded source")
    parser.add_argument("--downloads", type=Path, help="Shared download cache; required to prepare")
    parser.add_argument("--host", help="The host profile to prepare for (default: this machine's)")
    parser.add_argument("--verify-only", action="store_true", help="Check the Crest patches the lock pins")
    args = parser.parse_args()
    source = args.source.resolve()
    if source == REPO or REPO in source.parents:
        parser.error("The Chromium source must be outside Crest")
    lock = json.loads((ENGINE / "source.lock.json").read_text(encoding="utf-8"))
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
    host = args.host or chromium_host.detected()
    profile = chromium_host.profile(host, lock)
    downloads = args.downloads.resolve()
    chromium = lock["chromium"]
    archive = fetch(chromium["sourceArchive"], downloads / Path(chromium["sourceArchive"]).name,
                    chromium["sourceArchiveSha256"])
    staging = source.with_name(source.name + ".partial")
    if staging.exists():
        parser.error(f"Inspect the incomplete preparation at {staging} before removing it")
    staging.mkdir(parents=True)
    print(f"Unpacking Chromium {chromium['version']} for {host}", flush=True)
    extract(archive, staging, strip=f"chromium-{chromium['version']}")

    # The archive is exported on Linux: it carries Linux copies of a few
    # toolchain dependencies, none of another host's, and none of the Git
    # dependencies only another platform's checkout takes.
    scope = deps_scope(staging)
    available = deps_dependencies(scope, profile["depsVariables"])
    for path in profile["dependencies"]:
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

    # Files DEPS hooks fetch by the SHA-1 the archive records beside them,
    # such as Chromium's resource compiler on Windows.
    for item in profile.get("storageFiles", []):
        fetch_storage_file(staging, downloads, item)

    for path in profile["gitDependencies"]:
        repository, revision = git_dependency(scope, path)
        destination = staging / path.removeprefix("src/")
        if destination.exists():
            shutil.rmtree(destination)
        print(f"Checking out {path} at {revision[:12]}", flush=True)
        fetch_git(repository, revision, destination)

    # DEPS names these host tools only by CIPD version tag, so the lock pins
    # each package's instance digest: the build's Python, and the esbuild and
    # TypeScript compilers DevTools and the WebUI use, and on hosts that take
    # them prebuilt, GN and Ninja.
    for path, package in profile["cipd"].items():
        # A CIPD instance ID is the package digest, URL-safe Base64 with a
        # suffix naming SHA-256, so the download is addressed by its content.
        instance = base64.urlsafe_b64encode(bytes.fromhex(package["sha256"])).decode().rstrip("=") + "C"
        url = f"https://chrome-infra-packages.appspot.com/dl/{package['package']}/+/{instance}"
        download = fetch(url, downloads / "cipd" / package["sha256"] / "package.zip", package["sha256"])
        destination = staging / path.removeprefix("src/")
        # A package replaces the Linux copy the archive carries in its place,
        # unless it joins files Chromium itself keeps there, such as a BUILD.gn.
        if destination.exists() and not package.get("joinsSource", False):
            shutil.rmtree(destination)
        unzip(download, destination)

    patch = chromium_host.patch_tool()
    for relative in lock["crestPatches"]:
        run([patch, "-p1", "--forward", "--fuzz=0", "--input", ENGINE / relative], staging)

    # Generated build files name their source directory, so the tree takes
    # its final path before GN runs. On Windows a scanner that just opened a
    # new file can hold the tree for a moment.
    for attempt in range(30):
        try:
            staging.rename(source)
            break
        except PermissionError:
            if attempt == 29:
                raise
            time.sleep(2)
    output = source / "out/CrestBaseline"
    output.mkdir(parents=True)
    flags = {**lock["buildArguments"], **profile["developmentBuildArguments"]}
    (output / "args.gn").write_text("".join(f"{key}={json.dumps(value)}\n" for key, value in flags.items()),
                                    encoding="utf-8", newline="\n")
    gn = chromium_host.gn(source, host)
    if "gn" in profile:
        # GN as DEPS pins it, prebuilt for this host.
        shutil.copy2(source / profile["gn"].removeprefix("src/"), gn)
    else:
        run([sys.executable, source / "tools/gn/bootstrap/bootstrap.py", "-o", "out/CrestBaseline/gn",
             "--skip-generate-buildfiles"], source)
        # Build steps such as V8's metagen run gn where DEPS installs it.
        (source / "buildtools/mac").mkdir(exist_ok=True)
        shutil.copy2(gn, source / "buildtools/mac/gn")
    environment = chromium_host.build_environment(host, source)
    run([gn, "gen", "out/CrestBaseline", "--fail-on-unused-args", *chromium_host.gn_arguments(host)], source,
        environment)
    print("Source prepared. Run build-chromium-baseline.py against it.")


if __name__ == "__main__":
    main()
