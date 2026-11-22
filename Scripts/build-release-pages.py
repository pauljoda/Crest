#!/usr/bin/env python3
"""Build the product site's release notes from Crest's release history.

Reads the JSON `Scripts/export-release-history.py` writes and renders
`Website/releases/`, which is generated at deploy time and never committed:

- `/releases/<platform>/<channel>/<version>/`: a release with everything that
  changed in it, and the releases before it as rows that open their own pages.
  Every release of a channel has one.
- `/releases/<platform>/<channel>/` and `/releases/<platform>/`: the latest page.
  `/releases/` is the Mac's Stable channel.
- `release.json` beside each release page, for Crest's own What's New.
- `index.json`, which the site's 404 page reads to send an address for a version
  without a page to the release that contains it.

The history says which releases each channel has and what changed in them;
this script only decides how they look. It runs no git and reads no release
note files, so it works from any checkout that has the history file.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import datetime
import html
import json
import pathlib
import re
import shutil
import sys
from typing import Optional

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from site_page import FOOTER, SITE_URL, banner, head_html, header_html, icon  # noqa: E402


STYLESHEET = "/assets/releases.css?v=20261121-releases-2"
# The release history format this script reads.
HISTORY_SCHEMA = 1


# MARK: - Types


@dataclass(frozen=True)
class Category:
    """A kind of change, as a heading with its icon and color."""

    key: str
    title: str
    icon: str
    color: str


@dataclass(frozen=True)
class Channel:
    platform: str
    slug: str
    title: str
    # One of the site's brand colors, which also names its `stack-` panel.
    tone: str

    @property
    def color(self) -> str:
        return f"var(--{self.tone})"


@dataclass(frozen=True)
class Platform:
    slug: str
    title: str
    icon: str
    channels: tuple[Channel, ...]


@dataclass(frozen=True)
class Note:
    """A public change that reaches the release's platform."""

    identifier: str
    category: str
    message: str
    version: str


@dataclass(frozen=True)
class WriteUp:
    """A Stable or App Store release's curated notes, for its platform."""

    summary: Optional[str]
    sections: tuple[tuple[str, tuple[str, ...]], ...]


@dataclass
class Release:
    channel: Channel
    version: str
    date: Optional[str]
    write_up: Optional[WriteUp]
    # Newest version first.
    notes: list[Note]

    @classmethod
    def from_document(cls, channel: Channel, document: dict, notes: dict[str, list[Note]]) -> "Release":
        """A release from the history, with the notes of the versions it covers."""
        write_up = document["writeUp"]
        return cls(
            channel,
            document["version"],
            document["date"],
            WriteUp(
                write_up["summary"],
                tuple((section["kind"], tuple(section["items"])) for section in write_up["sections"]),
            )
            if write_up is not None
            else None,
            [note for version in document["covers"] for note in notes.get(version, ())],
        )

    @property
    def path(self) -> str:
        return f"/releases/{self.channel.platform}/{self.channel.slug}/{self.version}/"

    def write_up_sections(self) -> list[tuple[str, list[str]]]:
        return [(section, list(items)) for section, items in self.write_up.sections] if self.write_up else []


# MARK: - Icons


ICONS = {
    "sparkles": icon('<path d="M10 3.5l1.6 4.6 4.6 1.6-4.6 1.6L10 15.9l-1.6-4.6-4.6-1.6 4.6-1.6z"/><path d="M18 14l.8 2.2 2.2.8-2.2.8L18 20l-.8-2.2-2.2-.8 2.2-.8z"/>'),
    "arrow-up": icon('<circle cx="12" cy="12" r="9"/><path d="M12 16.5v-9M8 11l4-4 4 4"/>'),
    "check": icon('<circle cx="12" cy="12" r="9"/><path d="M8 12.4l2.8 2.8L16.2 9.6"/>'),
    "shield": icon('<path d="M12 3l7 3v5.5c0 4.3-3 7.9-7 9.5-4-1.6-7-5.2-7-9.5V6z"/><path d="M9 12l2.2 2.2L15.5 10"/>'),
    "minus": icon('<circle cx="12" cy="12" r="9"/><path d="M8 12h8"/>'),
    "info": icon('<circle cx="12" cy="12" r="9"/><path d="M12 11v5.5M12 7.6v.1"/>'),
    "swap": icon('<path d="M7 7h11l-3-3M17 17H6l3 3"/>'),
    "mac": icon('<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M1.8 19.5h20.4"/>'),
    "phone": icon('<rect x="6.5" y="2.5" width="11" height="19" rx="2.6"/><path d="M10.5 18.5h3"/>'),
    "arrow-left": icon('<path d="M19 12H5M11 6l-6 6 6 6"/>'),
    "arrow-right": icon('<path d="M5 12h14M13 6l6 6-6 6"/>'),
}

# MARK: - Catalog of channels


NOTE_CATEGORIES = (
    Category("new", "New", "sparkles", "var(--sky)"),
    Category("improved", "Improved", "arrow-up", "var(--butter)"),
    Category("fixed", "Fixed", "check", "var(--sage)"),
)
SECTION_CATEGORIES = {
    "added": Category("added", "Added", "sparkles", "var(--sky)"),
    "changed": Category("changed", "Changed", "swap", "var(--butter)"),
    "fixed": Category("fixed", "Fixed", "check", "var(--sage)"),
    "security": Category("security", "Security", "shield", "var(--coral)"),
    "removed": Category("removed", "Removed", "minus", "#C9D2E3"),
    "upgrading": Category("upgrading", "Upgrading", "info", "var(--field)"),
}

PLATFORMS = (
    Platform(
        "mac",
        "Mac",
        "mac",
        (
            Channel("mac", "stable", "Stable", "sage"),
            Channel("mac", "nightly", "Nightly", "slate"),
            Channel("mac", "development", "Development", "butter"),
        ),
    ),
    Platform(
        "ios",
        "iPhone and iPad",
        "phone",
        (
            Channel("ios", "app-store", "App Store", "sky"),
            Channel("ios", "testflight", "TestFlight", "coral"),
        ),
    ),
)

# How many earlier releases a page lists below its own.
EARLIER_RELEASES = 10


# MARK: - Release history


def read_history(path: pathlib.Path) -> dict[tuple[str, str], list[Release]]:
    """Every channel's releases, newest first, from the exported history."""
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schema") != HISTORY_SCHEMA:
        raise SystemExit(f"{path} is release history schema {document.get('schema')}; this site reads {HISTORY_SCHEMA}.")
    channels = {(channel.platform, channel.slug): channel for platform in PLATFORMS for channel in platform.channels}
    releases: dict[tuple[str, str], list[Release]] = {key: [] for key in channels}
    for platform, section in document["platforms"].items():
        notes = {
            version: [Note(note["id"], note["category"], note["message"], version) for note in items]
            for version, items in section["notes"].items()
        }
        for slug, items in section["channels"].items():
            channel = channels.get((platform, slug))
            if channel is None:
                raise SystemExit(f"{path} has releases for {platform}/{slug}, a channel the site doesn't show yet.")
            releases[(platform, slug)] = [Release.from_document(channel, item, notes) for item in items]
    return releases


# MARK: - Text


INLINE = re.compile(r"\*\*(?P<strong>.+?)\*\*|`(?P<code>[^`]+)`|\[(?P<label>[^\]]+)\]\((?P<href>[^)\s]+)\)")


def inline(text: str) -> str:
    """Release-note text as HTML: bold, code and links; everything else escaped."""
    parts = []
    position = 0
    for match in INLINE.finditer(text):
        parts.append(html.escape(text[position : match.start()]))
        if match.group("strong") is not None:
            parts.append(f"<strong>{inline(match.group('strong'))}</strong>")
        elif match.group("code") is not None:
            parts.append(f"<code>{html.escape(match.group('code'))}</code>")
        else:
            href = match.group("href")
            label = inline(match.group("label"))
            if href.startswith(("https://", "http://", "/")):
                parts.append(f'<a href="{html.escape(href)}">{label}</a>')
            else:
                parts.append(label)
        position = match.end()
    parts.append(html.escape(text[position:]))
    return "".join(parts)


def plain(text: str) -> str:
    return INLINE.sub(lambda match: match.group("strong") or match.group("code") or match.group("label"), text)


def long_date(day: Optional[str]) -> str:
    if not day:
        return ""
    value = datetime.date.fromisoformat(day)
    return f"{value:%B} {value.day}, {value.year}"


def short_date(day: Optional[str]) -> str:
    if not day:
        return ""
    value = datetime.date.fromisoformat(day)
    return f"{value:%b} {value.day}"


def time_element(day: Optional[str], text: str) -> str:
    return f'<time datetime="{day}">{text}</time>' if day else ""


def description_for(release: Release) -> str:
    if release.write_up and release.write_up.summary:
        text = plain(release.write_up.summary)
    else:
        notes = release.notes
        lead = plain(notes[0].message) if notes else "Behind-the-scenes improvements."
        text = f"What changed in Crest {release.version} for {platform_named(release.channel.platform).title}: {lead}"
    return text if len(text) <= 160 else text[:157].rsplit(" ", 1)[0] + "…"


def platform_named(slug: str) -> Platform:
    return next(platform for platform in PLATFORMS if platform.slug == slug)


# MARK: - Rendering


def group_html(category: Category, items: list[str]) -> str:
    rows = "".join(f"<li>{inline(item)}</li>" for item in items)
    return (
        f'<section class="rn-group" style="--rn-color: {category.color}">'
        f'<h3><span class="rn-icon">{ICONS[category.icon]}</span>{category.title}</h3>'
        f"<ul>{rows}</ul></section>"
    )


def notes_html(notes: list[Note]) -> str:
    groups = []
    for category in NOTE_CATEGORIES:
        items = [note.message for note in notes if note.category == category.key]
        if items:
            groups.append(group_html(category, items))
    return "".join(groups)


def counts_html(notes: list[Note]) -> str:
    counts = []
    for category in NOTE_CATEGORIES:
        count = sum(1 for note in notes if note.category == category.key)
        # Every category keeps its column, so counts line up from row to row.
        counts.append(
            f'<span class="rn-count" style="--rn-color: {category.color}">'
            f'<span class="rn-icon">{ICONS[category.icon]}</span>{count}'
            f'<span class="rn-hidden"> {category.title.lower()}</span></span>'
            if count
            else '<span class="rn-count"></span>'
        )
    return f'<span class="rn-counts">{"".join(counts)}</span>' if notes else ""


def row_html(release: Release) -> str:
    """An earlier release, as one row that opens its page."""
    return (
        f'<li class="rn-row"><a href="{release.path}">'
        f"<strong>{release.version}</strong>{time_element(release.date, long_date(release.date))}"
        f'{counts_html(release.notes)}<span class="rn-open">{ICONS["arrow-right"]}</span></a></li>'
    )


def release_html(release: Release) -> str:
    """The release a page is for, with everything that changed in it."""
    channel = release.channel
    notes = release.notes
    body = []
    if release.write_up is not None:
        if release.write_up.summary:
            body.append(f'<p class="rn-summary">{inline(release.write_up.summary)}</p>')
        for section, items in release.write_up_sections():
            body.append(group_html(SECTION_CATEGORIES[section], items))
        if notes:
            body.append(
                f'<details class="rn-all"><summary>All changes <span>{len(notes)}</span></summary>'
                f"{notes_html(notes)}</details>"
            )
    elif notes:
        body.append(notes_html(notes))
    else:
        body.append('<p class="rn-quiet">Behind-the-scenes improvements.</p>')
    return (
        f'<article class="rn-release" style="--rn-accent: {channel.color}">'
        f"<header><h2>{release.version}</h2>{time_element(release.date, long_date(release.date))}</header>"
        f'{"".join(body)}</article>'
    )


class Site:
    """Every channel's releases, and the pages that show them."""

    def __init__(self, releases: dict[tuple[str, str], list[Release]]) -> None:
        self.releases = releases

    def channels(self, platform: Platform) -> list[Channel]:
        return [channel for channel in platform.channels if self.releases[(platform.slug, channel.slug)]]

    def default_channel(self, platform: Platform) -> Optional[Channel]:
        channels = self.channels(platform)
        return channels[0] if channels else None

    def switcher_html(self, current: Channel) -> str:
        platforms = []
        for platform in PLATFORMS:
            if not self.channels(platform):
                continue
            selected = ' aria-current="page"' if platform.slug == current.platform else ""
            platforms.append(
                f'<a href="/releases/{platform.slug}/"{selected}>{ICONS[platform.icon]}{platform.title}</a>'
            )
        channels = []
        for channel in self.channels(platform_named(current.platform)):
            latest = self.releases[(channel.platform, channel.slug)][0]
            selected = ' aria-current="page"' if channel == current else ""
            channels.append(
                f'<a class="rn-channel" href="/releases/{channel.platform}/{channel.slug}/"{selected}>'
                f"{banner(channel.color, 'rn-banner')}<strong>{channel.title}</strong>"
                f"<span>{' · '.join(filter(None, (str(latest.version), short_date(latest.date))))}</span></a>"
            )
        return (
            f'<nav class="rn-platforms" aria-label="Platform">{"".join(platforms)}</nav>'
            f'<nav class="rn-channels" aria-label="Channel">{"".join(channels)}</nav>'
        )

    def page_html(self, channel: Channel, index: int, canonical: str) -> str:
        releases = self.releases[(channel.platform, channel.slug)]
        release = releases[index]
        platform = platform_named(channel.platform)
        step = EARLIER_RELEASES + 1
        earlier = releases[index + 1 : index + step]
        newer = None
        if index > 0:
            target = max(index - step, 0)
            newer = releases[target].path if target else f"/releases/{channel.platform}/{channel.slug}/"
        older = releases[index + step].path if index + step < len(releases) else None

        newer_button = (
            f'<a class="button button-secondary button-small rn-more" href="{newer}">{ICONS["arrow-left"]}Newer releases</a>'
            if newer
            else ""
        )
        older_button = (
            f'<a class="button button-secondary button-small rn-more" href="{older}">Older releases{ICONS["arrow-right"]}</a>'
            if older
            else ""
        )
        rows = f'<ol class="rn-rows">{"".join(row_html(item) for item in earlier)}</ol>' if earlier else ""
        if index == 0:
            title = f"Crest for {platform.title} Release Notes · {channel.title}"
        else:
            title = f"Crest {release.version} for {platform.title} · {channel.title} Release Notes"
        json_path = f"{release.path}release.json"
        return (
            head_html(title, description_for(release), canonical, stylesheet=STYLESHEET, json_path=json_path)
            + "\n"
            + header_html(body_class="rn-page", main_id="release-notes", skip_label="Skip to release notes")
            + f"""
  <main id="release-notes" class="rn">
    <section class="rn-head stack-{channel.tone}">
      <div class="rn-head-inner">
        <h1>Release notes</h1>
        {self.switcher_html(channel)}
        {newer_button}
      </div>
    </section>
    <div class="rn-timeline">
      {release_html(release)}
      {rows}
      {older_button}
    </div>
  </main>
"""
            + FOOTER
        )

    def release_document(self, release: Release, older: Optional[Release], newer: Optional[Release]) -> dict:
        return {
            "platform": release.channel.platform,
            "channel": release.channel.slug,
            "version": str(release.version),
            "date": release.date,
            "url": f"{SITE_URL}{release.path}",
            "summary": release.write_up.summary if release.write_up else None,
            "sections": [{"kind": section, "items": items} for section, items in release.write_up_sections()],
            "notes": [
                {"id": note.identifier, "category": note.category, "message": note.message, "version": note.version}
                for note in release.notes
            ],
            "previous": str(older.version) if older else None,
            "next": str(newer.version) if newer else None,
        }

    def manifest(self) -> dict:
        platforms = {}
        for platform in PLATFORMS:
            channels = self.channels(platform)
            if not channels:
                continue
            platforms[platform.slug] = {
                "title": platform.title,
                "defaultChannel": channels[0].slug,
                "channels": {
                    channel.slug: [str(release.version) for release in self.releases[(platform.slug, channel.slug)]]
                    for channel in channels
                },
            }
        return {"platforms": platforms}

    def write(self, output: pathlib.Path) -> int:
        if output.exists():
            shutil.rmtree(output)
        pages = 0

        def write_page(path: str, contents: str) -> None:
            nonlocal pages
            target = output / path.removeprefix("/releases/") / "index.html"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents)
            pages += 1

        for platform in PLATFORMS:
            for channel in self.channels(platform):
                releases = self.releases[(platform.slug, channel.slug)]
                channel_path = f"/releases/{platform.slug}/{channel.slug}/"
                write_page(channel_path, self.page_html(channel, 0, channel_path))
                for index, release in enumerate(releases):
                    write_page(release.path, self.page_html(channel, index, release.path))
                    older = releases[index + 1] if index + 1 < len(releases) else None
                    newer = releases[index - 1] if index > 0 else None
                    document = self.release_document(release, older, newer)
                    (output / release.path.removeprefix("/releases/") / "release.json").write_text(
                        json.dumps(document, indent=2, ensure_ascii=False) + "\n"
                    )
            default = self.default_channel(platform)
            if default is not None:
                platform_path = f"/releases/{platform.slug}/"
                write_page(platform_path, self.page_html(default, 0, platform_path))

        mac_stable = next(channel for channel in PLATFORMS[0].channels if channel.slug == "stable")
        write_page("/releases/", self.page_html(mac_stable, 0, "/releases/"))
        (output / "index.json").write_text(json.dumps(self.manifest(), separators=(",", ":")) + "\n")
        return pages


# MARK: - Command line


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--history",
        type=pathlib.Path,
        required=True,
        help="the JSON Scripts/export-release-history.py writes",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parents[1] / "Website" / "releases",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    releases = read_history(arguments.history)
    site = Site(releases)
    pages = site.write(arguments.output)
    counts = ", ".join(f"{platform}/{channel} {len(items)}" for (platform, channel), items in releases.items())
    print(f"Wrote {pages} release pages to {arguments.output} ({counts}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
