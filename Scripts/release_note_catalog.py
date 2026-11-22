#!/usr/bin/env python3
"""Validate Crest's release notes: one file per version under Documentation/ReleaseNotes.

Each version Crest reaches has `Documentation/ReleaseNotes/<major>.<minor>/<version>.json`,
written by the commit that moves `MARKETING_VERSION` to it:

    {
      "release": { "summary": "...", "added": ["..."], "fixed": ["..."] },
      "entries": [
        { "id": "kebab-case-id", "category": "fixed", "message": "...", "platforms": ["mac"] }
      ]
    }

`entries` record what that version changed. An entry's ID, category, message and
platforms never change once it is on main. `release` is the curated write-up of a
version published as Stable; it may be written and edited after the version lands.
Leaving out `platforms` means the change reaches every platform.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import pathlib
import re
import subprocess
import sys
from typing import Iterable, Optional


CATALOG_DIRECTORY = "Documentation/ReleaseNotes"
# The single catalog file the version files replaced; read only to compare a
# commit against a parent that still has it.
LEGACY_CATALOG_PATH = "Documentation/ReleaseNotes.json"
VERSION_FILE_PATH = "Config/Version.xcconfig"
SUPPORTED_CATEGORIES = ("new", "improved", "fixed", "internal")
PUBLIC_CATEGORIES = ("new", "improved", "fixed")
PLATFORMS = ("mac", "ios")
RELEASE_SECTIONS = ("added", "changed", "fixed", "security", "removed", "upgrading")
PUBLICATION_CHANNELS = ("stable", "development", "nightly")
ENTRY_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
MARKETING_VERSION = re.compile(r"^\s*MARKETING_VERSION\s*=\s*(\S+)\s*$", re.MULTILINE)


class CatalogValidationError(ValueError):
    """The release notes do not satisfy their repository contract."""


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
            raise CatalogValidationError(f"'{text}' is not a strict X.Y.Z version")
        return cls(*(int(part) for part in match.groups()))

    @classmethod
    def from_version_file(cls, contents: str, source: str) -> "Version":
        match = MARKETING_VERSION.search(contents)
        if match is None:
            raise CatalogValidationError(f"{source} does not define MARKETING_VERSION")
        return cls.parse(match.group(1))

    @property
    def line(self) -> str:
        return f"{self.major}.{self.minor}"

    @property
    def path(self) -> str:
        """The version's notes file, relative to the repository root."""
        return f"{CATALOG_DIRECTORY}/{self.line}/{self}.json"

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"


@dataclass(frozen=True)
class ReleaseNoteEntry:
    identifier: str
    category: str
    message: str
    platforms: tuple[str, ...]
    version: Version

    @property
    def is_public(self) -> bool:
        return self.category in PUBLIC_CATEGORIES

    def reaches(self, platform: str) -> bool:
        return not self.platforms or platform in self.platforms

    @property
    def content(self) -> tuple[str, str, tuple[str, ...], Version]:
        """What may never change once the entry is on main."""
        return (self.category, self.message, self.platforms, self.version)


@dataclass(frozen=True)
class WriteUpItem:
    text: str
    platforms: tuple[str, ...]

    def reaches(self, platform: str) -> bool:
        return not self.platforms or platform in self.platforms


@dataclass(frozen=True)
class ReleaseWriteUp:
    """The curated notes of a version published as Stable."""

    summary: Optional[str]
    sections: tuple[tuple[str, tuple[WriteUpItem, ...]], ...]

    def sections_for(self, platform: str) -> list[tuple[str, list[str]]]:
        """Each section's items that reach `platform`, in section order, without empty ones."""
        visible = []
        for section, items in self.sections:
            texts = [item.text for item in items if item.reaches(platform)]
            if texts:
                visible.append((section, texts))
        return visible


@dataclass(frozen=True)
class VersionNotes:
    version: Version
    entries: tuple[ReleaseNoteEntry, ...]
    write_up: Optional[ReleaseWriteUp]

    def public_entries(self, platform: str) -> list[ReleaseNoteEntry]:
        return [entry for entry in self.entries if entry.is_public and entry.reaches(platform)]


@dataclass(frozen=True)
class ReleaseNoteCatalog:
    versions: tuple[VersionNotes, ...]

    @property
    def entries(self) -> dict[str, ReleaseNoteEntry]:
        """Every entry by ID, in release order: by version, then as written."""
        return {
            entry.identifier: entry
            for notes in self.versions
            for entry in notes.entries
        }

    @property
    def newest(self) -> Optional[VersionNotes]:
        return self.versions[-1] if self.versions else None

    def notes(self, version: Version) -> Optional[VersionNotes]:
        return next((notes for notes in self.versions if notes.version == version), None)


# MARK: - Parsing


def unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise CatalogValidationError(f"duplicate JSON key '{key}'")
        value[key] = item
    return value


def one_line(value: object, source: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CatalogValidationError(f"{source} must be non-empty text")
    if value != value.strip() or "\n" in value or "\r" in value:
        raise CatalogValidationError(f"{source} must be one trimmed line")
    return value


def platform_list(value: object, source: str) -> tuple[str, ...]:
    if (
        not isinstance(value, list)
        or not value
        or any(platform not in PLATFORMS for platform in value)
        or len(set(value)) != len(value)
    ):
        supported = ", ".join(PLATFORMS)
        raise CatalogValidationError(
            f"{source}: platforms must list some of {supported}, each once"
        )
    if set(value) == set(PLATFORMS):
        raise CatalogValidationError(
            f"{source}: leave platforms out for a change that reaches every platform"
        )
    return tuple(platform for platform in PLATFORMS if platform in value)


def parse_entry(raw: object, version: Version, source: str) -> ReleaseNoteEntry:
    if not isinstance(raw, dict) or not {"id", "category", "message"} <= set(raw) or not set(raw) <= {
        "id",
        "category",
        "message",
        "platforms",
    }:
        raise CatalogValidationError(
            f"{source}: an entry has id, category, message and optional platforms"
        )
    identifier = raw["id"]
    if not isinstance(identifier, str) or not ENTRY_ID.fullmatch(identifier) or len(identifier) > 80:
        raise CatalogValidationError(
            f"{source}: entry id {identifier!r} must be lowercase kebab-case up to 80 characters"
        )
    entry_source = f"{source}: entry '{identifier}'"
    category = raw["category"]
    if category not in SUPPORTED_CATEGORIES:
        supported = ", ".join(SUPPORTED_CATEGORIES)
        raise CatalogValidationError(f"{entry_source}: category must be one of {supported}")
    message = one_line(raw["message"], f"{entry_source}: message")
    platforms = platform_list(raw["platforms"], entry_source) if "platforms" in raw else ()
    return ReleaseNoteEntry(identifier, category, message, platforms, version)


def parse_write_up(raw: object, source: str) -> ReleaseWriteUp:
    allowed = {"summary", *RELEASE_SECTIONS}
    if not isinstance(raw, dict) or not raw or not set(raw) <= allowed:
        sections = ", ".join(RELEASE_SECTIONS)
        raise CatalogValidationError(
            f"{source}: release holds a summary and some of {sections}"
        )
    summary = one_line(raw["summary"], f"{source}: release summary") if "summary" in raw else None
    sections = []
    for section in RELEASE_SECTIONS:
        if section not in raw:
            continue
        raw_items = raw[section]
        item_source = f"{source}: release {section}"
        if not isinstance(raw_items, list) or not raw_items:
            raise CatalogValidationError(f"{item_source} must be a non-empty list")
        items = []
        for raw_item in raw_items:
            if isinstance(raw_item, str):
                items.append(WriteUpItem(one_line(raw_item, item_source), ()))
            elif isinstance(raw_item, dict) and set(raw_item) == {"text", "platforms"}:
                items.append(
                    WriteUpItem(
                        one_line(raw_item["text"], item_source),
                        platform_list(raw_item["platforms"], item_source),
                    )
                )
            else:
                raise CatalogValidationError(
                    f"{item_source}: an item is text, or an object with text and platforms"
                )
        sections.append((section, tuple(items)))
    return ReleaseWriteUp(summary, tuple(sections))


def parse_version_document(contents: str, version: Version, source: str) -> VersionNotes:
    try:
        document = json.loads(contents, object_pairs_hook=unique_json_object)
    except (json.JSONDecodeError, CatalogValidationError) as error:
        raise CatalogValidationError(f"{source}: {error}") from error
    if not isinstance(document, dict) or "entries" not in document or not set(document) <= {
        "release",
        "entries",
    }:
        raise CatalogValidationError(f"{source}: must hold entries and an optional release")
    raw_entries = document["entries"]
    if not isinstance(raw_entries, list):
        raise CatalogValidationError(f"{source}: entries must be a list")
    entries = tuple(parse_entry(raw, version, source) for raw in raw_entries)
    write_up = parse_write_up(document["release"], source) if "release" in document else None
    if not entries and write_up is None:
        raise CatalogValidationError(f"{source}: add at least one entry")
    return VersionNotes(version, entries, write_up)


def version_for_path(relative_path: str) -> Version:
    """The version a notes file is named for, checking it sits in its own line's folder."""
    parts = relative_path.split("/")
    if len(parts) != 2 or not parts[1].endswith(".json"):
        raise CatalogValidationError(
            f"{CATALOG_DIRECTORY}/{relative_path}: notes live at <major>.<minor>/<version>.json"
        )
    version = Version.parse(parts[1].removesuffix(".json"))
    if parts[0] != version.line:
        raise CatalogValidationError(
            f"{CATALOG_DIRECTORY}/{relative_path}: belongs in the {version.line} folder"
        )
    return version


def assemble(documents: Iterable[tuple[str, str]]) -> ReleaseNoteCatalog:
    """A catalog from (path relative to the catalog directory, contents) pairs."""
    versions = []
    for relative_path, contents in documents:
        version = version_for_path(relative_path)
        versions.append(
            parse_version_document(contents, version, f"{CATALOG_DIRECTORY}/{relative_path}")
        )
    versions.sort(key=lambda notes: notes.version)
    seen: dict[str, Version] = {}
    for notes in versions:
        for entry in notes.entries:
            if entry.identifier in seen:
                raise CatalogValidationError(
                    f"entry id '{entry.identifier}' is in both {seen[entry.identifier]} and {notes.version}"
                )
            seen[entry.identifier] = notes.version
    return ReleaseNoteCatalog(tuple(versions))


def read_catalog(directory: pathlib.Path) -> ReleaseNoteCatalog:
    if not directory.is_dir():
        raise CatalogValidationError(f"{CATALOG_DIRECTORY} is missing")
    documents = []
    for path in sorted(directory.rglob("*")):
        if path.is_dir() or path.name == ".DS_Store":
            continue
        documents.append((path.relative_to(directory).as_posix(), path.read_text()))
    return assemble(documents)


# MARK: - Git


def git(repository_root: pathlib.Path, *arguments: str, stdin: Optional[str] = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=False,
        capture_output=True,
        text=True,
        input=stdin,
    )


def read_blobs(repository_root: pathlib.Path, objects: list[str]) -> list[str]:
    """The contents of each git object, read in one batch."""
    if not objects:
        return []
    result = subprocess.run(
        ["git", "-C", str(repository_root), "cat-file", "--batch"],
        check=True,
        capture_output=True,
        input="\n".join(objects).encode() + b"\n",
    )
    output = result.stdout
    contents = []
    offset = 0
    for _ in objects:
        header_end = output.index(b"\n", offset)
        size = int(output[offset:header_end].split()[2])
        start = header_end + 1
        contents.append(output[start : start + size].decode())
        offset = start + size + 1
    return contents


def read_catalog_at(repository_root: pathlib.Path, treeish: str) -> Optional[ReleaseNoteCatalog]:
    """The catalog in a commit, or in the index when `treeish` is ":"; None when it has none."""
    if treeish == ":":
        listing = git(repository_root, "ls-files", "--stage", "--", CATALOG_DIRECTORY)
        rows = [line.split(None, 3) for line in listing.stdout.splitlines()]
        blobs = [(row[3], row[1]) for row in rows]
    else:
        listing = git(repository_root, "ls-tree", "-r", treeish, "--", CATALOG_DIRECTORY)
        if listing.returncode != 0:
            raise CatalogValidationError(f"cannot read {treeish}: {listing.stderr.strip()}")
        rows = [line.split(None, 3) for line in listing.stdout.splitlines()]
        blobs = [(row[3], row[2]) for row in rows]
    if not blobs:
        return None
    prefix = f"{CATALOG_DIRECTORY}/"
    contents = read_blobs(repository_root, [blob for _, blob in blobs])
    return assemble(
        (path.removeprefix(prefix), text)
        for (path, _), text in zip(blobs, contents)
        if not path.endswith("/.DS_Store")
    )


def legacy_entries_at(repository_root: pathlib.Path, treeish: str) -> Optional[dict[str, tuple[str, str]]]:
    """Category and message of each entry in a commit that still has the single catalog file."""
    result = git(repository_root, "show", f"{treeish}:{LEGACY_CATALOG_PATH}")
    if result.returncode != 0:
        return None
    entries = json.loads(result.stdout)["entries"]
    return {identifier: (entry["category"], entry["message"]) for identifier, entry in entries.items()}


def file_at(repository_root: pathlib.Path, object_name: str) -> Optional[str]:
    result = git(repository_root, "show", object_name)
    return result.stdout if result.returncode == 0 else None


# MARK: - Validation


def validate_working_catalog(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    catalog = read_catalog(repository_root / CATALOG_DIRECTORY)
    version_file = repository_root / VERSION_FILE_PATH
    newest = catalog.newest
    if version_file.is_file() and newest is not None:
        marketing_version = Version.from_version_file(version_file.read_text(), VERSION_FILE_PATH)
        if newest.version > marketing_version:
            raise CatalogValidationError(
                f"{newest.version.path} is newer than MARKETING_VERSION {marketing_version}"
            )
    return catalog


def validate_staged_entry(repository_root: pathlib.Path) -> tuple[str, ...]:
    """The entries a fix commit adds, after checking it adds them where they belong."""
    staged_version_file = file_at(repository_root, f":{VERSION_FILE_PATH}")
    if staged_version_file is None:
        raise CatalogValidationError(f"stage {VERSION_FILE_PATH} with the current commit")
    version = Version.from_version_file(staged_version_file, f"staged {VERSION_FILE_PATH}")
    current = read_catalog_at(repository_root, ":")
    if current is None:
        raise CatalogValidationError(f"stage {version.path} with this change's release notes")
    current_entries = current.entries

    has_head = git(repository_root, "rev-parse", "--verify", "--quiet", "HEAD").returncode == 0
    previous = read_catalog_at(repository_root, "HEAD") if has_head else None
    if previous is not None:
        previous_content = {identifier: entry.content for identifier, entry in previous.entries.items()}
        current_content = {identifier: entry.content for identifier, entry in current_entries.items()}
    else:
        previous_content = (legacy_entries_at(repository_root, "HEAD") if has_head else None) or {}
        current_content = {
            identifier: (entry.category, entry.message) for identifier, entry in current_entries.items()
        }

    deleted = sorted(previous_content.keys() - current_content.keys())
    if deleted:
        raise CatalogValidationError(
            f"commits must not delete release-note entries: {', '.join(deleted)}"
        )
    rewritten = [
        identifier
        for identifier, content in previous_content.items()
        if current_content[identifier] != content
    ]
    if rewritten:
        raise CatalogValidationError(
            f"commits must not change or move release-note entries: {', '.join(rewritten)}"
        )

    added = tuple(identifier for identifier in current_entries if identifier not in previous_content)
    if not added:
        raise CatalogValidationError(
            f"add at least one new release-note entry to {version.path}"
        )
    misplaced = [identifier for identifier in added if current_entries[identifier].version != version]
    if misplaced:
        raise CatalogValidationError(
            f"new release-note entries belong in {version.path}: {', '.join(misplaced)}"
        )
    newest = current.newest
    if newest is not None and newest.version != version:
        raise CatalogValidationError(
            f"{newest.version.path} is newer than the staged MARKETING_VERSION {version}"
        )
    return added


# MARK: - Writing


def format_document(document: dict[str, object]) -> str:
    """A version file's canonical text: two-space JSON with platform lists on one line."""
    text = json.dumps(document, indent=2, ensure_ascii=False)
    text = re.sub(
        r'"platforms": \[([^\]]*)\]',
        lambda match: '"platforms": ['
        + ", ".join(part.strip() for part in match.group(1).split(","))
        + "]",
        text,
    )
    return text + "\n"


def append_entry(repository_root: pathlib.Path, version: Version, entry: dict[str, object]) -> pathlib.Path:
    """Add an entry to a version's notes file, creating the file when it is the version's first."""
    path = repository_root / version.path
    if path.is_file():
        document = json.loads(path.read_text(), object_pairs_hook=unique_json_object)
    else:
        document = {"entries": []}
    document["entries"].append(entry)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(format_document(document))
    parse_version_document(path.read_text(), version, version.path)
    return path


# MARK: - Command line


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--require-staged-entry", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.require_staged_entry:
            added_entries = validate_staged_entry(arguments.repository_root)
            print(f"Validated new release-note entries: {', '.join(added_entries)}")
            return 0

        catalog = validate_working_catalog(arguments.repository_root)
        print(
            f"Validated {len(catalog.entries)} release-note entries "
            f"in {len(catalog.versions)} versions."
        )
        return 0
    except (CatalogValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
