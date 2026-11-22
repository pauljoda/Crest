#!/usr/bin/env python3
"""Generate the GitHub and Sparkle notes of a Mac release from Crest's version notes.

A Stable release whose version has a curated write-up publishes that write-up.
Every other release lists the public entries that reach the Mac after its
channel's cursor or, without a cursor, the entries the previous release's
commit did not have. Each release links to its page on the product site.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import urllib.parse

from release_note_catalog import (
    VERSION_FILE_PATH,
    CatalogValidationError,
    ReleaseNoteEntry,
    Version,
    legacy_entries_at,
    read_catalog_at,
)


PLATFORM = "mac"
SITE_URL = "https://crestbrowser.com"

CHANNEL_DESCRIPTIONS = {
    "stable": "Stable releases are signed, notarized, and ready for everyday use.",
    "nightly": (
        "Nightly builds contain the newest changes and may be less reliable "
        "than stable releases."
    ),
    "development": (
        "Development builds contain the newest changes and may be less reliable "
        "than stable releases."
    ),
}

CATEGORY_HEADINGS = (
    ("new", "New"),
    ("improved", "Improved"),
    ("fixed", "Fixed"),
)

SECTION_HEADINGS = {
    "added": "Added",
    "changed": "Changed",
    "fixed": "Fixed",
    "security": "Security",
    "removed": "Removed",
    "upgrading": "Upgrading",
}

MAX_HIGHLIGHTS = 12


def git(repository_root: pathlib.Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def is_ancestor(
    repository_root: pathlib.Path,
    possible_ancestor: str,
    current_commit: str,
) -> bool:
    result = subprocess.run(
        ["git", "-C", str(repository_root), "merge-base", "--is-ancestor", possible_ancestor, current_commit],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode in (0, 1):
        return result.returncode == 0
    result.check_returncode()
    return False


def changes_after(entries: dict[str, ReleaseNoteEntry], previous_entry: str) -> list[ReleaseNoteEntry]:
    """The public Mac entries after the channel's cursor, in release order."""
    if previous_entry not in entries:
        raise CatalogValidationError(
            f"release-note cursor '{previous_entry}' is not in the current catalog"
        )
    identifiers = list(entries)
    later = identifiers[identifiers.index(previous_entry) + 1 :]
    return [
        entries[identifier]
        for identifier in later
        if entries[identifier].is_public and entries[identifier].reaches(PLATFORM)
    ]


def changes_since(
    repository_root: pathlib.Path,
    entries: dict[str, ReleaseNoteEntry],
    previous_ref: str,
) -> list[ReleaseNoteEntry]:
    """The public Mac entries that the previous release's commit did not have."""
    previous_catalog = read_catalog_at(repository_root, previous_ref)
    if previous_catalog is not None:
        published = set(previous_catalog.entries)
    else:
        published = set(legacy_entries_at(repository_root, previous_ref) or {})
    return [
        entry
        for identifier, entry in entries.items()
        if identifier not in published and entry.is_public and entry.reaches(PLATFORM)
    ]


def highlight_lines(changes: list[ReleaseNoteEntry]) -> list[str]:
    visible = changes[-MAX_HIGHLIGHTS:]
    lines: list[str] = []
    if len(changes) > len(visible):
        lines.extend(
            [
                (
                    f"Showing the {len(visible)} most recent highlights "
                    f"from {len(changes)} user-facing changes."
                ),
                "",
            ]
        )
    if not visible:
        return ["### Maintenance", "", "- Reliability and internal improvements.", ""]
    for category, heading in CATEGORY_HEADINGS:
        messages = [change.message for change in visible if change.category == category]
        if not messages:
            continue
        lines.extend([f"### {heading}", ""])
        lines.extend(f"- {message}" for message in messages)
        lines.append("")
    return lines


def release_notes(
    repository_root: pathlib.Path,
    repository: str,
    server_url: str,
    channel: str,
    release_tag: str,
    current_ref: str,
    previous_ref: str | None,
    previous_entry: str | None,
    asset_name: str,
) -> str:
    current_commit = git(repository_root, "rev-parse", f"{current_ref}^{{commit}}")
    catalog = read_catalog_at(repository_root, current_commit)
    if catalog is None:
        raise CatalogValidationError(f"{current_ref} has no release notes")
    version = Version.from_version_file(
        git(repository_root, "show", f"{current_commit}:{VERSION_FILE_PATH}"),
        f"{current_ref}:{VERSION_FILE_PATH}",
    )
    version_notes = catalog.notes(version)
    write_up = version_notes.write_up if channel == "stable" and version_notes else None

    lines = ["## Highlights", ""]
    if write_up is not None:
        if write_up.summary:
            lines.extend([write_up.summary, ""])
        for section, items in write_up.sections_for(PLATFORM):
            lines.extend([f"### {SECTION_HEADINGS[section]}", ""])
            lines.extend(f"- {item}" for item in items)
            lines.append("")
    elif previous_entry is not None:
        lines.extend(highlight_lines(changes_after(catalog.entries, previous_entry)))
    elif previous_ref is not None:
        lines.extend(highlight_lines(changes_since(repository_root, catalog.entries, previous_ref)))
    else:
        raise CatalogValidationError("pass the channel's cursor or the previous release's commit")

    repository_url = f"{server_url.rstrip('/')}/{repository}"
    channel_query = (
        "prerelease:false" if channel == "stable"
        else f'prerelease:true "{channel.title()} builds"'
    )
    channel_url = f"{repository_url}/releases?{urllib.parse.urlencode({'q': channel_query})}"
    download_url = (
        f"{repository_url}/releases/download/"
        f"{urllib.parse.quote(release_tag, safe='.-_')}/"
        f"{urllib.parse.quote(asset_name, safe='.-_')}"
    )
    page_url = f"{SITE_URL}/releases/{PLATFORM}/{channel}/{version}/"
    has_linear_history = previous_ref is not None and is_ancestor(
        repository_root,
        git(repository_root, "rev-parse", f"{previous_ref}^{{commit}}"),
        current_commit,
    )
    if has_linear_history:
        details_url = f"{repository_url}/compare/{previous_ref}...{current_commit}"
        details_label = "View all changes"
    else:
        details_url = f"{repository_url}/commit/{current_commit}"
        details_label = "View source"

    lines.extend(
        [
            "---",
            "",
            CHANNEL_DESCRIPTIONS[channel],
            "",
            f"[Release notes]({page_url}) · [{details_label}]({details_url}) · [Download the installer]({download_url})",
            "",
            f"[Browse {channel.title()} releases]({channel_url})",
            "",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--repository", required=True)
    parser.add_argument("--server-url", default="https://github.com")
    parser.add_argument("--channel", choices=CHANNEL_DESCRIPTIONS, required=True)
    parser.add_argument("--release-tag")
    parser.add_argument("--current-ref", required=True)
    parser.add_argument("--previous-ref")
    parser.add_argument("--previous-entry")
    parser.add_argument("--asset-name", required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    print(
        release_notes(
            repository_root=arguments.repository_root,
            repository=arguments.repository,
            server_url=arguments.server_url,
            channel=arguments.channel,
            release_tag=arguments.release_tag or arguments.channel,
            current_ref=arguments.current_ref,
            previous_ref=arguments.previous_ref,
            previous_entry=arguments.previous_entry,
            asset_name=arguments.asset_name,
        ),
        end="",
    )


if __name__ == "__main__":
    main()
