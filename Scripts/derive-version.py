#!/usr/bin/env python3
"""Derive Crest's public version from its release line and its history.

`Config/Version.xcconfig` names the release line's base version, X.Y.Z. A
change never edits it: the patch component of a build is the base patch plus
the number of first-parent commits since the commit that last changed the
file. Every merge to the default branch adds a first-parent commit, so the
version rises with each one, and two open changes never edit the same line.
`Scripts/set-version.sh --release X.Y.Z` starts a new line by changing the
base, which brings the count back to zero.

Release builds write the derived version over the file in their checkout with
`stamp`, so every later step reads it where it always has. Never commit a
stamped file.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


VERSION_PATH = "Config/Version.xcconfig"
SETTING = re.compile(r"^([ \t]*MARKETING_VERSION[ \t]*=[ \t]*)(\S+)[ \t]*$", re.MULTILINE)
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


class VersionError(ValueError):
    """The release line or the history cannot give a version."""


def git(repository_root: pathlib.Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise VersionError(result.stderr.strip() or f"git {' '.join(arguments)} failed")
    return result.stdout.strip()


def base_version(contents: str) -> tuple[int, int, int]:
    """The release line's base version the file names."""
    match = SETTING.search(contents)
    if match is None:
        raise VersionError(f"{VERSION_PATH} must define MARKETING_VERSION")
    version = SEMVER.fullmatch(match.group(2))
    if version is None:
        raise VersionError(f"MARKETING_VERSION '{match.group(2)}' must be strict X.Y.Z")
    return tuple(int(part) for part in version.groups())


def derived_version(repository_root: pathlib.Path, reference: str = "HEAD") -> str:
    """The version `reference` builds as."""
    if git(repository_root, "rev-parse", "--is-shallow-repository") == "true":
        raise VersionError("the version is counted from history; fetch the full history (fetch-depth: 0)")
    major, minor, patch = base_version(git(repository_root, "show", f"{reference}:{VERSION_PATH}"))
    # The commit that set the base, as the first-parent history sees it: a
    # merge that brought the change in counts as setting it.
    based_at = git(
        repository_root, "log", "-1", "--first-parent", "--diff-merges=first-parent",
        "--format=%H", reference, "--", VERSION_PATH)
    if not based_at:
        raise VersionError(f"{VERSION_PATH} has no history at {reference}")
    since = int(git(repository_root, "rev-list", "--count", "--first-parent", f"{based_at}..{reference}"))
    return f"{major}.{minor}.{patch + since}"


def stamp(repository_root: pathlib.Path, version: str) -> None:
    """Write `version` over the file in this checkout only."""
    path = repository_root / VERSION_PATH
    contents = path.read_text()
    stamped, count = SETTING.subn(lambda match: f"{match.group(1)}{version}", contents)
    if count != 1:
        raise VersionError(f"{VERSION_PATH} must define MARKETING_VERSION exactly once")
    path.write_text(stamped)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["version", "tag", "stamp"],
                        help="print the version, print its stable tag, or write it over the file in this checkout")
    parser.add_argument("--repository-root", type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[1])
    parser.add_argument("--ref", default="HEAD", help="the commit to derive the version of")
    arguments = parser.parse_args()
    try:
        version = derived_version(arguments.repository_root, arguments.ref)
        if arguments.command == "stamp":
            stamp(arguments.repository_root, version)
            print(f"Stamped {VERSION_PATH} with Crest {version} for this checkout.")
        else:
            print(f"v{version}" if arguments.command == "tag" else version)
        return 0
    except (VersionError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
