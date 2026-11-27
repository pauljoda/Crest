#!/usr/bin/env python3
"""Read what a channel's appcast already publishes.

Without `--require-newer`, prints the source commit of the channel's latest
published item. With it, fails unless the version about to be published is
newer than every version the channel offers, because Crest refuses an update
that isn't. The one exception is the commit the channel already publishes,
which keeps its version. An experimental build is compared only with its own
branch's, since experimental versions follow each branch's merge base; a tie
there is reported, not refused.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import pathlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ElementTree
from typing import Optional

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from crest_version import Version, VersionError  # noqa: E402


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ROLLING_CHANNELS = ("development", "nightly")
CHANNELS = ("stable", *ROLLING_CHANNELS, "experimental")


@dataclass(frozen=True)
class Publication:
    """An item a channel's appcast offers."""

    # None when the item names no strict version.
    version: Optional[Version]
    # The source commit's prefix, from the installer's name; Stable installers name none.
    commit_prefix: Optional[str]
    release_tag: str


def publications(appcast: str, channel: str) -> list[Publication]:
    """The channel's items, newest first as the appcast lists them; Stable items carry no channel."""
    root = ElementTree.fromstring(appcast)
    channel_element = f"{{{SPARKLE_NAMESPACE}}}channel"
    version_element = f"{{{SPARKLE_NAMESPACE}}}shortVersionString"
    # Universal installers carry no architecture; earlier ones end in -arm64.
    asset_pattern = re.compile(
        rf"^(?:Installer-)?Crest-.+-{re.escape(channel)}-"
        rf"\d{{4}}-\d{{2}}-\d{{2}}-([0-9a-f]{{7,40}})(?:-arm64)?\.dmg$"
    )

    found = []
    for item in root.findall(".//item"):
        item_channel = (item.findtext(channel_element) or "").strip() or "stable"
        enclosure = item.find("enclosure")
        if item_channel != channel or enclosure is None:
            continue
        path = pathlib.PurePosixPath(urllib.parse.unquote(urllib.parse.urlparse(enclosure.get("url", "")).path))
        match = asset_pattern.fullmatch(path.name)
        text = (item.findtext(version_element) or enclosure.get(version_element) or "").strip()
        try:
            version: Optional[Version] = Version.parse(text)
        except VersionError:
            version = None
        found.append(Publication(version, match.group(1) if match else None, path.parent.name))
    return found


def published_commit_prefix(appcast: str, channel: str) -> str | None:
    return next((item.commit_prefix for item in publications(appcast, channel) if item.commit_prefix), None)


def newer_than_published(
    appcast: str,
    channel: str,
    version: Version,
    source_sha: str,
    branch_slug: Optional[str] = None,
) -> Optional[str]:
    """None when `version` may be published, a note on a tolerated tie, or a refusal as VersionError."""
    items = [item for item in publications(appcast, channel) if item.version is not None]
    if branch_slug is not None:
        # experimental-<version>-<branch>-<date>-…
        items = [
            item for item in items if item.release_tag.startswith(f"experimental-{item.version}-{branch_slug}-")
        ]
    if not items:
        return None
    highest = max(item.version for item in items)
    if version > highest:
        return None
    same_commit = any(
        item.version == version and item.commit_prefix and source_sha.startswith(item.commit_prefix)
        for item in items
    )
    if version == highest and (same_commit or branch_slug is not None):
        return (
            f"Crest {version} ties the {channel} channel's newest version; copies that already have "
            f"{highest} won't be offered this build."
        )
    offered = f"{branch_slug}'s experimental builds already carry" if branch_slug else f"the {channel} channel already offers"
    raise VersionError(
        f"Crest {version} is not newer than {highest}, which {offered}, and Crest refuses an update that "
        f"isn't newer. The anchor in Config/Version.xcconfig was probably lowered; versions on main must only rise."
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--appcast", type=pathlib.Path, required=True)
    parser.add_argument("--channel", choices=CHANNELS, required=True)
    parser.add_argument("--require-newer", metavar="VERSION", help="fail unless VERSION is newer than the channel's")
    parser.add_argument("--source-sha", help="the commit about to be published, with --require-newer")
    parser.add_argument("--branch-slug", help="an experimental build's branch, with --require-newer")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    appcast = arguments.appcast.read_text()
    if arguments.require_newer is None:
        commit_prefix = published_commit_prefix(appcast, arguments.channel)
        if commit_prefix is not None:
            print(commit_prefix)
        return 0
    try:
        note = newer_than_published(
            appcast,
            arguments.channel,
            Version.parse(arguments.require_newer),
            arguments.source_sha or "",
            arguments.branch_slug,
        )
    except VersionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if note is not None:
        print(note)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
