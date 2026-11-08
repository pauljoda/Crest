#!/usr/bin/env python3
"""Put the content filter library the core links for one runtime in place.

The core's builds run this, so a checkout without Rust builds the core:

- For an Apple runtime it prints the static library Native AOT links. The
  prebuilt archive the lock names is downloaded once, checked against the
  lock's digests and kept in the cache.
- For `host` it prints the dynamic library the core's tests load without
  Native AOT. On a Mac that library is linked from the verified macOS static
  library; elsewhere, such as CI's Linux runner, it is compiled from source.

When the crate's sources no longer match the lock, or CREST_CONTENT_FILTER_FROM_SOURCE
is 1, the library is compiled from source instead, which needs Rust.
"""
import argparse
import fcntl
import hashlib
import io
import os
from pathlib import Path
import platform
import subprocess
import sys
import urllib.request
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_filter  # noqa: E402

DOWNLOADS = "https://github.com/{repository}/releases/download/{tag}/{asset}"


class Unpublished(Exception):
    """The locked archive cannot be downloaded, as before a maintainer publishes it."""


def verified(path: Path, digest: str) -> bool:
    return path.is_file() and content_filter.sha256(path) == digest


def unpack(lock: dict, cache: Path, repository: str):
    """Downloads the locked archive and keeps each member whose digest the lock records."""
    url = DOWNLOADS.format(repository=repository, tag=content_filter.release_tag(lock["key"]), asset=lock["archive"])
    print(f"Downloading the content filter {lock['archive']}", file=sys.stderr)
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            data = response.read()
    except OSError as error:
        raise Unpublished(f"Cannot download {url}: {error}") from error
    if hashlib.sha256(data).hexdigest() != lock["sha256"]:
        raise SystemExit(f"{lock['archive']} does not match the digest in {content_filter.LOCK}")
    with zipfile.ZipFile(io.BytesIO(data)) as bundle:
        for name, digest in lock["files"].items():
            contents = bundle.read(name)
            if hashlib.sha256(contents).hexdigest() != digest:
                raise SystemExit(f"{name} in {lock['archive']} does not match {content_filter.LOCK}")
            target = cache / name
            target.parent.mkdir(parents=True, exist_ok=True)
            pending = target.with_suffix(target.suffix + ".pending")
            pending.write_bytes(contents)
            pending.replace(target)


def published_library(runtime: str, cache: Path, repository: str) -> Path:
    lock = content_filter.read_lock()
    folder = cache / lock["key"][:16]
    library = folder / content_filter.member(runtime)
    if not all(verified(folder / name, digest) for name, digest in lock["files"].items()):
        unpack(lock, folder, repository)
    return library


def source_library(runtime: str) -> Path:
    target = content_filter.TARGETS[runtime][0] if runtime != "host" else None
    release = content_filter.compile_library(target)
    if runtime != "host":
        return release / content_filter.LIBRARY
    suffix = {"Darwin": ".dylib", "Windows": ".dll"}.get(platform.system(), ".so")
    return release / f"libcrest_content_filter{suffix}"


def mac_test_library(static_library: Path, folder: Path) -> Path:
    """A dynamic library holding every export of the verified static one."""
    library = folder / "host/libcrest_content_filter.dylib"
    stamp = library.with_suffix(".source")
    if library.is_file() and stamp.is_file() and stamp.read_text() == content_filter.sha256(static_library):
        return library
    library.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "clang", "-dynamiclib", "-arch", "arm64",
                    f"-mmacosx-version-min={content_filter.DEPLOYMENT_TARGET}",
                    f"-Wl,-force_load,{static_library}", "-install_name", "@rpath/libcrest_content_filter.dylib",
                    "-o", library], check=True)
    stamp.write_text(content_filter.sha256(static_library))
    return library


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", required=True, choices=[*content_filter.TARGETS, "host"])
    parser.add_argument("--cache", type=Path, default=content_filter.REPOSITORY / "CrestCore/artifacts/content-filter")
    parser.add_argument("--repository", default=os.environ.get("CREST_CONTENT_FILTER_REPOSITORY", "pauljoda/Crest"))
    args = parser.parse_args()

    from_source = os.environ.get("CREST_CONTENT_FILTER_FROM_SOURCE") == "1"
    if not from_source and content_filter.read_lock()["key"] != content_filter.artifact_key():
        if content_filter.cargo() is None:
            raise SystemExit(f"The content filter's sources differ from {content_filter.LOCK} and no Rust "
                             "toolchain is installed: install rustup, or ask a maintainer to publish it")
        print("The content filter's sources differ from the lock; compiling them", file=sys.stderr)
        from_source = True

    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    # Parallel builds of the app and its frameworks ask at the same time.
    with (cache / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        library = resolve(args.runtime, cache, args.repository, from_source)
    print(library)


def resolve(runtime: str, cache: Path, repository: str, from_source: bool) -> Path:
    try:
        return located(runtime, cache, repository, from_source)
    except Unpublished as error:
        if from_source or content_filter.cargo() is None:
            raise SystemExit(f"{error}\nThe content filter is not published yet; install rustup to compile it")
        print(f"{error}\nCompiling the content filter from source instead", file=sys.stderr)
        library = located(runtime, cache, repository, True)
        # The sources are the locked ones, so the build must be the locked library.
        expected = content_filter.read_lock()["files"].get(content_filter.member(runtime))
        if expected and content_filter.sha256(library) != expected:
            raise SystemExit(f"Compiling the locked sources gave a {runtime} library that differs from "
                             f"{content_filter.LOCK}; refusing to use it")
        return library


def located(runtime: str, cache: Path, repository: str, from_source: bool) -> Path:
    if from_source:
        library = source_library(runtime)
    elif runtime != "host":
        library = published_library(runtime, cache, repository)
    elif platform.system() == "Darwin" and platform.machine() == "arm64":
        static_library = published_library("osx-arm64", cache, repository)
        library = mac_test_library(static_library, static_library.parents[1])
    else:
        # No prebuilt library runs here; CI's Linux runner has Rust.
        library = source_library("host")
    if not library.is_file():
        raise SystemExit(f"No content filter library at {library}")
    return library


if __name__ == "__main__":
    main()
