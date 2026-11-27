#!/usr/bin/env python3
"""Compute Crest's version from git.

`Config/Version.xcconfig` holds the anchor version of the release line: the
version of the last commit on main's first-parent history that changed
MARKETING_VERSION. Every later commit on that history is one patch further on:

    version(C) = X.Y.(Z + git rev-list --first-parent --count anchor..C)

Pull requests never change the file; only opening a release line does, with
`Scripts/set-version.sh --release`. A commit that isn't on main's
first-parent history, such as a branch, takes the version of its merge base
with main. Main is `origin/main` when the checkout has it, then `main`, then
the commit's own history.

    crest_version.py                  the version of HEAD
    crest_version.py --at REF         the version of REF
    crest_version.py next             the version the next commit on main gets
    crest_version.py --on-main        fail unless the commit is on main's history

Every published build takes its version from here, so it needs the full
history; a shallow clone is refused rather than counted short.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import pathlib
import re
import subprocess
import sys
from typing import Optional


VERSION_FILE_PATH = "Config/Version.xcconfig"
MAIN_REFS = ("refs/remotes/origin/main", "refs/heads/main")
VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
MARKETING_VERSION = re.compile(r"^\s*MARKETING_VERSION\s*=\s*(\S+)\s*$", re.MULTILINE)


class VersionError(ValueError):
    """Crest's version cannot be computed for the commit."""


# MARK: - Types


@dataclass(frozen=True, order=True)
class Version:
    """A strict X.Y.Z marketing version, ordered numerically."""

    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, text: str) -> "Version":
        match = VERSION.fullmatch(text)
        if match is None:
            raise VersionError(f"'{text}' is not a strict X.Y.Z version")
        return cls(*(int(part) for part in match.groups()))

    @classmethod
    def from_version_file(cls, contents: str, source: str) -> "Version":
        match = MARKETING_VERSION.search(contents)
        if match is None:
            raise VersionError(f"{source} does not define MARKETING_VERSION")
        return cls.parse(match.group(1))

    @property
    def line(self) -> str:
        return f"{self.major}.{self.minor}"

    def advanced(self, count: int) -> "Version":
        """The version `count` patches further along the same line."""
        return Version(self.major, self.minor, self.patch + count)

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"


@dataclass(frozen=True)
class MainCommit:
    """A commit on main's first-parent history, with the version it carries."""

    sha: str
    # The committer date, YYYY-MM-DD.
    date: str
    version: Version


class VersionHistory:
    """The version of every commit on a first-parent history, from its first anchor on."""

    def __init__(self, commits: tuple[MainCommit, ...]) -> None:
        self.commits = commits
        self.by_sha = {commit.sha: commit for commit in commits}

    @classmethod
    def read(cls, repository_root: pathlib.Path, tip: str) -> "VersionHistory":
        if git(repository_root, "rev-parse", "--is-shallow-repository") == "true":
            raise VersionError(
                "Crest's version is counted over the full history; "
                "fetch it with `git fetch --unshallow` first"
            )
        chain = [
            line.split(" ", 1)
            for line in reversed(git(repository_root, "log", "--first-parent", "--format=%H %cs", tip).splitlines())
        ]
        touching = git(repository_root, "log", "--first-parent", "--format=%H", tip, "--", VERSION_FILE_PATH).split()
        values = dict(zip(touching, version_file_values(repository_root, touching)))

        commits = []
        anchor: Optional[Version] = None
        offset = 0
        for sha, date in chain:
            value = values.get(sha)
            if value is not None and value != anchor:
                anchor, offset = value, 0
            elif anchor is not None:
                offset += 1
            if anchor is not None:
                commits.append(MainCommit(sha, date, anchor.advanced(offset)))
        return cls(tuple(commits))


@dataclass(frozen=True)
class Placement:
    """Where a commit sits against main: its own place, or the main commit it builds on."""

    history: VersionHistory
    commit: MainCommit
    on_main: bool

    @property
    def version(self) -> Version:
        return self.commit.version

    @property
    def next(self) -> Version:
        """The version the next commit on main after this one gets."""
        return self.commit.version.advanced(1)


# MARK: - Git


def git(repository_root: pathlib.Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise VersionError(f"git {' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def has_ref(repository_root: pathlib.Path, ref: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(repository_root), "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        check=False,
        capture_output=True,
    )
    return result.returncode == 0


def version_file_values(repository_root: pathlib.Path, commits: list[str]) -> list[Optional[Version]]:
    """MARKETING_VERSION in each commit, read in one batch; None where the file is absent or invalid."""
    if not commits:
        return []
    output = subprocess.run(
        ["git", "-C", str(repository_root), "cat-file", "--batch"],
        check=True,
        capture_output=True,
        input="".join(f"{commit}:{VERSION_FILE_PATH}\n" for commit in commits).encode(),
    ).stdout
    values: list[Optional[Version]] = []
    offset = 0
    for _ in commits:
        header_end = output.index(b"\n", offset)
        header = output[offset:header_end].split()
        if header[-1] == b"missing":
            values.append(None)
            offset = header_end + 1
            continue
        size = int(header[2])
        start = header_end + 1
        try:
            values.append(Version.from_version_file(output[start : start + size].decode(), VERSION_FILE_PATH))
        except VersionError:
            values.append(None)
        offset = start + size + 1
    return values


def main_ref(repository_root: pathlib.Path, requested: Optional[str]) -> Optional[str]:
    if requested is not None:
        if not has_ref(repository_root, requested):
            raise VersionError(f"main ref {requested} does not exist")
        return requested
    return next((ref for ref in MAIN_REFS if has_ref(repository_root, ref)), None)


# MARK: - Placement


def place(repository_root: pathlib.Path, ref: str = "HEAD", main: Optional[str] = None) -> Placement:
    """The main commit whose version `ref` carries."""
    sha = git(repository_root, "rev-parse", f"{ref}^{{commit}}")
    tip = main_ref(repository_root, main) or sha
    history = VersionHistory.read(repository_root, tip)
    if sha in history.by_sha:
        return Placement(history, history.by_sha[sha], True)

    base = git(repository_root, "merge-base", tip, sha)
    if base and base not in history.by_sha:
        # The base came in through a merge; take the main commit that merged it.
        merged_by = git(repository_root, "rev-list", "--first-parent", "--ancestry-path", "--reverse", f"{base}..{tip}")
        base = merged_by.split("\n", 1)[0]
    if base not in history.by_sha:
        raise VersionError(f"{ref} has no version: no commit before it on main sets MARKETING_VERSION")
    return Placement(history, history.by_sha[base], False)


# MARK: - Command line


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", choices=("next",))
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--at", default="HEAD", metavar="REF")
    parser.add_argument("--main", metavar="REF", help="main's ref; defaults to origin/main, then main")
    parser.add_argument("--on-main", action="store_true", help="fail unless REF is on main's first-parent history")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        placement = place(arguments.repository_root, arguments.at, arguments.main)
        if arguments.on_main and not placement.on_main:
            raise VersionError(f"{arguments.at} is not on main's first-parent history")
        print(placement.next if arguments.command == "next" else placement.version)
        return 0
    except VersionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
