#!/usr/bin/env python3
"""Export Crest's release history as the JSON the product site renders.

Reads the release tags, the day each version reached the checked-out branch,
and `Documentation/ReleaseNotes/`, then writes one file:

    {
      "schema": 1,
      "platforms": {
        "mac": {
          "notes": {
            "0.10.24": [{ "id": "...", "category": "fixed", "message": "..." }]
          },
          "channels": {
            "stable": [
              {
                "version": "0.10.24",
                "date": "2026-11-17",
                "covers": ["0.10.24", "0.10.23", "..."],
                "writeUp": { "summary": "...", "sections": [{ "kind": "added", "items": ["..."] }] }
              }
            ],
            "nightly": [...], "development": [...]
          }
        },
        "ios": { "notes": {...}, "channels": { "app-store": [...], "testflight": [...] } }
      }
    }

`notes` holds each version's public entries that reach the platform, once, in
the order they were written; a version with none is left out. A version file's
entries belong to its version, and a fragment's to the version of the commit
that added it, so the checkout needs its full history. Each channel
lists its releases newest first. A release covers the versions after the
release before it, up to its own, and `covers` names them newest first, so its
changes are those versions' notes in that order. `writeUp` is the curated
write-up of a Stable or App Store release, with only the items that reach the
platform, and null everywhere else. `date` is null when no tag, version
history or fragment commit gives one.

A channel's releases come from its tags: `v<version>` for Mac Stable,
`nightly-<version>-<date>-…` and `development-<version>-<date>-…` for the Mac
prerelease channels, and `ios-v<version>` for the App Store. TestFlight lists
every version with changes for iPhone and iPad.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import pathlib
import re
import subprocess
import sys
from typing import Optional

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from release_note_catalog import (  # noqa: E402
    VERSION_FILE_PATH,
    ReleaseNoteCatalog,
    ReleaseWriteUp,
    Version,
    VersionNotes,
    read_working_catalog,
)


SCHEMA = 1


# MARK: - Types


@dataclass(frozen=True)
class Channel:
    platform: str
    slug: str
    # A pattern for the channel's release tags, with `version` and an optional
    # `date` group; None lists every version that reaches the platform.
    tag: Optional[re.Pattern[str]]
    # Whether a release carries its version's curated write-up.
    curated: bool


@dataclass
class Release:
    channel: Channel
    version: Version
    date: Optional[str]
    covered: list[VersionNotes]
    write_up: Optional[ReleaseWriteUp]

    def document(self) -> dict:
        write_up = None
        if self.write_up is not None:
            write_up = {
                "summary": self.write_up.summary,
                "sections": [
                    {"kind": section, "items": items}
                    for section, items in self.write_up.sections_for(self.channel.platform)
                ],
            }
        return {
            "version": str(self.version),
            "date": self.date,
            "covers": [str(notes.version) for notes in reversed(self.covered)],
            "writeUp": write_up,
        }


VERSION_GROUP = r"(?P<version>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))"
DATE_GROUP = r"(?P<date>\d{4}-\d{2}-\d{2})"

CHANNELS = (
    Channel("mac", "stable", re.compile(rf"^v{VERSION_GROUP}$"), True),
    Channel("mac", "nightly", re.compile(rf"^nightly-{VERSION_GROUP}-{DATE_GROUP}-"), False),
    Channel("mac", "development", re.compile(rf"^development-{VERSION_GROUP}-{DATE_GROUP}-"), False),
    Channel("ios", "app-store", re.compile(rf"^ios-v{VERSION_GROUP}$"), True),
    Channel("ios", "testflight", None, False),
)


# MARK: - Repository facts


def git(repository_root: pathlib.Path, *arguments: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def release_tags(repository_root: pathlib.Path) -> list[tuple[str, str]]:
    """Each tag's name and creation date."""
    output = git(repository_root, "for-each-ref", "--format=%(refname:short)%09%(creatordate:short)", "refs/tags")
    return [tuple(line.split("\t", 1)) for line in output.splitlines() if "\t" in line]


def version_dates(repository_root: pathlib.Path, catalog: ReleaseNoteCatalog) -> dict[Version, str]:
    """The day each version first reached the checked-out branch.

    A version file's version dates from the day MARKETING_VERSION first held
    it, and a version that only fragments give from the day its commit landed.
    """
    output = git(
        repository_root,
        "log",
        "--first-parent",
        "--reverse",
        "--format=%x00%cs",
        "-U0",
        "--",
        VERSION_FILE_PATH,
    )
    dates: dict[Version, str] = {}
    current_date = None
    for line in output.splitlines():
        if line.startswith("\0"):
            current_date = line[1:]
        elif line.startswith("+") and "MARKETING_VERSION" in line and current_date:
            text = line.split("=", 1)[1].strip()
            try:
                dates.setdefault(Version.parse(text), current_date)
            except ValueError:
                continue
    for notes in catalog.versions:
        if notes.landed is not None:
            dates.setdefault(notes.version, notes.landed)
    return dates


def channel_releases(
    channel: Channel,
    catalog: ReleaseNoteCatalog,
    tags: list[tuple[str, str]],
    dates: dict[Version, str],
) -> list[Release]:
    """A channel's releases, newest first."""
    published: dict[Version, Optional[str]] = {}
    if channel.tag is not None:
        for name, created in tags:
            match = channel.tag.match(name)
            if match is None:
                continue
            version = Version.parse(match.group("version"))
            date = match.groupdict().get("date") or created
            if version not in published or (date and date < (published[version] or date)):
                published[version] = date
    else:
        for notes in catalog.versions:
            if notes.public_entries(channel.platform):
                published[notes.version] = dates.get(notes.version)

    if not catalog.versions:
        return []
    oldest = catalog.versions[0].version
    releases: list[Release] = []
    previous: Optional[Version] = None
    for version in sorted(version for version in published if version >= oldest):
        covered = [
            notes
            for notes in catalog.versions
            if (previous is None or notes.version > previous) and notes.version <= version
        ]
        own = catalog.notes(version)
        write_up = own.write_up if channel.curated and own else None
        releases.append(Release(channel, version, published[version], covered, write_up))
        previous = version
    return list(reversed(releases))


def platform_notes(catalog: ReleaseNoteCatalog, platform: str) -> dict[str, list[dict]]:
    """Each version's public entries that reach `platform`, oldest version first."""
    notes: dict[str, list[dict]] = {}
    for version_notes in catalog.versions:
        entries = version_notes.public_entries(platform)
        if entries:
            notes[str(version_notes.version)] = [
                {"id": entry.identifier, "category": entry.category, "message": entry.message}
                for entry in entries
            ]
    return notes


def release_history(repository_root: pathlib.Path) -> dict:
    catalog = read_working_catalog(repository_root)
    tags = release_tags(repository_root)
    dates = version_dates(repository_root, catalog)
    platforms: dict[str, dict] = {}
    for channel in CHANNELS:
        if channel.platform not in platforms:
            platforms[channel.platform] = {"notes": platform_notes(catalog, channel.platform), "channels": {}}
        releases = channel_releases(channel, catalog, tags, dates)
        platforms[channel.platform]["channels"][channel.slug] = [release.document() for release in releases]
    return {"schema": SCHEMA, "platforms": platforms}


# MARK: - Command line


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--repository",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parents[1],
        help="a Crest checkout with its full history and tags",
    )
    parser.add_argument("--output", type=pathlib.Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    history = release_history(arguments.repository)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(history, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    counts = ", ".join(
        f"{platform}/{channel} {len(releases)}"
        for platform, section in history["platforms"].items()
        for channel, releases in section["channels"].items()
    )
    print(f"Wrote the release history to {arguments.output} ({counts}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
