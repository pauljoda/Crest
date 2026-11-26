#!/usr/bin/env python3
"""Identify, build and package the prebuilt content filter the core links.

The content filter is Brave's adblock engine behind Crest's C interface,
compiled from CrestCore/native/ContentFilter. Contributors and release builds
download it prebuilt, so none of them needs Rust: a maintainer builds it with
the pinned toolchain, `build` records the archive's and every library's digest
in the lock, and `publish-content-filter.py` publishes it once per key. The key
hashes everything compiled into it: the crate and its lock file, the pinned
toolchain and this recipe. `build --check` rebuilds from source and compares
each library with the lock, which is how CI shows the published archive holds
what the sources compile to.

Each platform family (Apple, Windows, Linux) has an archive of its own under
the same key, built on that family's own host: a Mac cannot link MSVC
libraries and Windows cannot build Apple ones. `build` builds the family of
the machine it runs on and records it beside the families already locked for
the same key; every family is one more asset of the key's one release.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import re
import tempfile
import zipfile

import repository

REPOSITORY = Path(__file__).resolve().parents[2]
CRATE = "CrestCore/native/ContentFilter"
LOCK = f"{CRATE}/artifact.lock.json"
INPUTS = (
    f"{CRATE}/Cargo.toml",
    f"{CRATE}/Cargo.lock",
    f"{CRATE}/rust-toolchain.toml",
    f"{CRATE}/src",
    f"{CRATE}/include",
    "Scripts/control-plane/content_filter.py",
)
HEADER = "include/crest_content_filter.h"
# The core's runtime identifiers, each with the Rust target that builds it, the
# variable that sets its minimum OS where the platform has one (matching
# project.yml), and the platform family whose archive carries it.
TARGETS = {
    "osx-arm64": ("aarch64-apple-darwin", "MACOSX_DEPLOYMENT_TARGET", "apple"),
    "osx-x64": ("x86_64-apple-darwin", "MACOSX_DEPLOYMENT_TARGET", "apple"),
    "ios-arm64": ("aarch64-apple-ios", "IPHONEOS_DEPLOYMENT_TARGET", "apple"),
    "iossimulator-arm64": ("aarch64-apple-ios-sim", "IPHONEOS_DEPLOYMENT_TARGET", "apple"),
    "win-x64": ("x86_64-pc-windows-msvc", None, "windows"),
    "win-arm64": ("aarch64-pc-windows-msvc", None, "windows"),
    "linux-x64": ("x86_64-unknown-linux-gnu", None, "linux"),
}
# The operating system each family's archive is built on.
FAMILY_HOSTS = {"apple": "Darwin", "windows": "Windows", "linux": "Linux"}
# Each platform's minimum OS, which matches project.yml.
DEPLOYMENT_TARGETS = {
    "MACOSX_DEPLOYMENT_TARGET": "15.0",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.1",
}
# Every member gets the same timestamp and mode, so an archive's bytes depend
# only on what it holds.
MEMBER_DATE = (1980, 1, 1, 0, 0, 0)


def artifact_key(repo: Path = REPOSITORY) -> str:
    digest = hashlib.sha256()
    for name in INPUTS:
        path = repo / name
        files = sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
        if not files or not all(p.is_file() for p in files):
            raise SystemExit(f"Missing content filter input: {name}")
        for file in files:
            relative = file.relative_to(repo).as_posix()
            digest.update(relative.encode() + b"\0")
            digest.update(hashlib.sha256(file.read_bytes()).hexdigest().encode() + b"\n")
    return digest.hexdigest()


def release_tag(key: str) -> str:
    return f"content-filter-{key[:16]}"


def asset_name(key: str, family: str) -> str:
    return f"Crest-Content-Filter-{key[:16]}-{family}.zip"


def host_family() -> str:
    """The family this machine builds."""
    for family, system in FAMILY_HOSTS.items():
        if platform.system() == system:
            return family
    raise SystemExit(f"No content filter family builds on {platform.system()}")


def runtimes(family: str) -> list:
    return [runtime for runtime, (_, _, owner) in TARGETS.items() if owner == family]


def library_name(runtime: str) -> str:
    """The static library Rust writes for the runtime's target."""
    return "crest_content_filter.lib" if TARGETS[runtime][2] == "windows" else "libcrest_content_filter.a"


def member(runtime: str) -> str:
    return f"{runtime}/{library_name(runtime)}"


def read_lock(repo: Path = REPOSITORY) -> dict:
    """The lock, with every family's archive under `archives`. A lock written
    before families existed describes the Apple archive alone."""
    lock = json.loads((repo / LOCK).read_text())
    if "archives" not in lock:
        lock = {"key": lock["key"], "archives": {"apple": {name: lock[name] for name in ("archive", "sha256", "files")}}}
    return lock


def family_archive(lock: dict, family: str):
    """The family's locked archive, or None when it is not built for the key."""
    return lock["archives"].get(family)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def toolchain(repo: Path = REPOSITORY) -> str:
    """The channel rust-toolchain.toml pins. Xcode's Python predates tomllib."""
    text = (repo / CRATE / "rust-toolchain.toml").read_text()
    return re.search(r'^channel\s*=\s*"([^"]+)"', text, re.MULTILINE).group(1)


def target_directory(repo: Path = REPOSITORY) -> Path:
    """Where cargo builds. Cargo keeps what it compiled when a minimum OS
    changes, so each set of minimums builds in a directory of its own."""
    minimums = "-".join(f"{variable.split('_')[0].lower()}{version}"
                        for variable, version in sorted(DEPLOYMENT_TARGETS.items()))
    return repo / CRATE / "target" / minimums


def cargo_environment(repo: Path = REPOSITORY) -> dict:
    """The environment every build of the crate uses, so the libraries do not
    depend on where the checkout or the Cargo home is."""
    environment = dict(os.environ)
    cargo_home = Path(environment.get("CARGO_HOME", Path.home() / ".cargo"))
    environment["PATH"] = f"{cargo_home / 'bin'}{os.pathsep}{environment.get('PATH', '')}"
    environment["RUSTFLAGS"] = (f"--remap-path-prefix={cargo_home}=/cargo "
                                f"--remap-path-prefix={(repo / CRATE).resolve()}=/crest-content-filter")
    environment.update(DEPLOYMENT_TARGETS)
    environment["CARGO_TARGET_DIR"] = str(target_directory(repo))
    return environment


def cargo(repo: Path = REPOSITORY):
    """The cargo that builds the crate, or None without a Rust toolchain."""
    return shutil.which("cargo", path=cargo_environment(repo)["PATH"])


def compile_library(target, repo: Path = REPOSITORY) -> Path:
    """Compiles the crate for `target`, or for this machine without one, and
    answers the release directory that holds its libraries."""
    executable = cargo(repo)
    if executable is None:
        raise SystemExit("Building the content filter from source needs Rust: install rustup "
                         "(https://rustup.rs); the crate pins its toolchain")
    environment = cargo_environment(repo)
    crate = repo / CRATE
    # Newer rustup no longer installs a pinned toolchain on first use.
    channel = toolchain(repo)
    subprocess.run(["rustup", "toolchain", "install", channel, "--profile", "minimal"],
                   cwd=crate, env=environment, check=True, stdout=subprocess.DEVNULL)
    if target:
        subprocess.run(["rustup", "target", "add", "--toolchain", channel, target],
                       cwd=crate, env=environment, check=True, stdout=subprocess.DEVNULL)
    command = [executable, "build", "--release", "--locked"] + (["--target", target] if target else [])
    subprocess.run(command, cwd=crate, env=environment, check=True)
    return target_directory(repo) / (target or "") / "release"


def build(repo: Path, output: Path, family: str) -> dict:
    """Builds every library of `family` and packages them with the header.
    Answers the lock entry that describes the archive."""
    key = artifact_key(repo)
    files = {HEADER: repo / CRATE / HEADER}
    for runtime in runtimes(family):
        files[member(runtime)] = compile_library(TARGETS[runtime][0], repo) / library_name(runtime)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / asset_name(key, family)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, MEMBER_DATE)
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            bundle.writestr(info, files[name].read_bytes())
    return {
        "archive": archive.name,
        "sha256": sha256(archive),
        "files": {name: sha256(path) for name, path in sorted(files.items())},
    }


def record(entry: dict, family: str, key: str, repo: Path = REPOSITORY) -> dict:
    """The lock with `family` built for `key`. Other families built for the
    same key stay; those locked for an older key are dropped, since their
    libraries no longer match the sources."""
    lock = read_lock(repo)
    archives = lock["archives"] if lock["key"] == key else {}
    return {"key": key, "archives": {**archives, family: entry}}


def write_lock(lock: dict, repo: Path = REPOSITORY):
    archives = dict(sorted(lock["archives"].items()))
    (repo / LOCK).write_text(json.dumps({"key": lock["key"], "archives": archives}, indent=2) + "\n",
                             encoding="utf-8", newline="\n")


NOTICES = "ThirdParty/ContentFilter-LICENSES.txt"
LICENSE_FILES = ("LICENSE", "LICENCE", "COPYING", "UNLICENSE")


def crates(repo: Path = REPOSITORY) -> list:
    """Every crate Cargo.lock resolves, other than Crest's own, as (name, version)."""
    text = (repo / CRATE / "Cargo.lock").read_text()
    found = re.findall(r'^\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"', text, re.MULTILINE)
    return sorted((name, version) for name, version in found if name != "crest-content-filter")


def notices(repo: Path = REPOSITORY) -> str:
    """The license texts of every crate the content filter is built from,
    each distinct text once with the crates it covers. A crate that ships no
    license file is covered by its declared license's standard text."""
    metadata = json.loads(subprocess.run([cargo(repo), "metadata", "--format-version", "1", "--locked"],
                                         cwd=repo / CRATE, env=cargo_environment(repo), check=True,
                                         capture_output=True, text=True).stdout)
    packages = {(package["name"], package["version"]): package for package in metadata["packages"]}
    texts, standard = {}, {}
    for name, version in crates(repo):
        package = packages[(name, version)]
        folder = Path(package["manifest_path"]).parent
        files = sorted(path for path in folder.iterdir() if path.name.upper().startswith(LICENSE_FILES))
        for path in files:
            text = path.read_text(errors="replace").strip()
            texts.setdefault(text, []).append(f"{name} {version} ({package['license']})")
            if path.name.upper() in ("LICENSE-APACHE", "LICENSE-MIT"):
                standard.setdefault(path.name.upper(), text)
        if not files:
            texts.setdefault(("missing", name, version, package["license"], ", ".join(package["authors"])), [])
    sections = []
    for text, covered in texts.items():
        if isinstance(text, tuple):
            _, name, version, license_name, authors = text
            body = standard["LICENSE-APACHE" if "Apache" in license_name else "LICENSE-MIT"]
            # The borrowed text's copyright lines name another crate's authors.
            lines = [line for line in body.splitlines() if not line.startswith("Copyright ")]
            if "Apache" not in license_name:
                lines.insert(lines.index("") + 1 if "" in lines else 0, f"Copyright (c) {authors}")
            body = "\n".join(lines)
            sections.append(f"{name} {version} ({license_name}) ships no license file; its authors, "
                            f"{authors}, publish it under {license_name}:\n\n{body}")
        else:
            sections.append("Applies to " + ", ".join(covered) + ":\n\n" + text)
    heading = ("Crest's content filter (CrestCore/native/ContentFilter) is built from Brave's adblock engine and "
               "the Rust crates below, each under the license that follows its name.")
    return heading + "\n\n" + ("\n\n" + "=" * 78 + "\n\n").join(sections) + "\n"


def published(repository: str, lock: dict) -> bool:
    """Whether every archive the lock names is released and complete."""
    result = subprocess.run(["gh", "api", f"repos/{repository}/releases/tags/{release_tag(lock['key'])}"],
                            capture_output=True, text=True)
    if result.returncode:
        if "(HTTP 404)" in result.stderr:
            return False
        raise SystemExit(f"Cannot inspect the content filter release: {result.stderr.strip()}")
    release = json.loads(result.stdout)
    names = {item["name"] for item in release.get("assets", []) if item.get("state") == "uploaded"}
    expected = {name for entry in lock["archives"].values() for name in (entry["archive"], f"{entry['archive']}.sha256")}
    return not release.get("draft") and lock["key"] in (release.get("body") or "") and expected <= names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for field in ("key", "tag", "asset"):
        commands.add_parser(field)
    build_command = commands.add_parser("build", help="Build one family's libraries from source and update the lock")
    build_command.add_argument("--output", type=Path, help="Where the archive goes (default: the crate's target/)")
    build_command.add_argument("--family", choices=sorted(FAMILY_HOSTS),
                               help="The family to build (default: this machine's)")
    build_command.add_argument("--check", action="store_true",
                               help="Compare the rebuilt libraries with the lock instead of rewriting it")
    commands.add_parser("notices", help=f"Rewrite {NOTICES} from the crates Cargo.lock resolves")
    published_command = commands.add_parser("published", help="Say whether the locked archive is released")
    published_command.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", repository.REPOSITORY))
    published_command.add_argument("--require", action="store_true", help="Fail when it is not")
    args = parser.parse_args()

    if args.command == "notices":
        (REPOSITORY / NOTICES).write_text(notices())
        print(f"Wrote {NOTICES} for {len(crates())} crates.")
        return
    if args.command == "published":
        lock = read_lock()
        ready = published(args.repository, lock)
        print(f"{release_tag(lock['key'])}: {'published' if ready else 'not published'}")
        if args.require and not ready:
            raise SystemExit("Publish the content filter with publish-content-filter.py before this merges")
        return

    if args.command in ("key", "tag", "asset"):
        key = artifact_key()
        print({"key": key, "tag": release_tag(key), "asset": asset_name(key, host_family())}[args.command])
        return
    family = args.family or host_family()
    output = args.output or REPOSITORY / CRATE / "target/artifact"
    if not args.check:
        key = artifact_key()
        entry = build(REPOSITORY, output, family)
        write_lock(record(entry, family, key))
        print(f"Built {entry['archive']} (sha256 {entry['sha256']}) and updated {LOCK}.")
        return
    recorded = read_lock()
    if recorded["key"] != artifact_key():
        raise SystemExit(f"{LOCK} names key {recorded['key'][:16]}, but the sources hash to "
                         f"{artifact_key()[:16]}: run `content_filter.py build` and commit the lock")
    locked = family_archive(recorded, family)
    if locked is None:
        raise SystemExit(f"{LOCK} has no {family} archive for this key: run `content_filter.py build` on {FAMILY_HOSTS[family]}")
    with tempfile.TemporaryDirectory(prefix="crest-content-filter-") as temporary:
        rebuilt = build(REPOSITORY, Path(temporary), family)
    differing = sorted(name for name, digest in rebuilt["files"].items() if locked["files"].get(name) != digest)
    if differing or set(rebuilt["files"]) != set(locked["files"]):
        sys.exit("The sources do not compile to the locked libraries: " + ", ".join(differing or ["file list"]))
    print(f"Rebuilt every library of {locked['archive']} from source; each matches the lock.")


if __name__ == "__main__":
    main()
