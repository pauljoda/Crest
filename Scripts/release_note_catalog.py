#!/usr/bin/env python3
"""Validate and assemble Crest's explicit, history-stable release-note catalog.

The catalog is the frozen document `Documentation/ReleaseNotes.json`, which
holds every entry written before entries moved to their own files, followed by
one file per entry in `Documentation/ReleaseNotes/<id>.json`. A change adds its
own file, so two open changes never edit the same file. The catalog's order is
the document's order, then each entry file in the order the first-parent
history of the branch added it; files a commit has not added yet follow by
name. Release builds write the assembled catalog over the document in their
checkout with `--write-assembled`, so the app and the publication cursor read
one ordered catalog as before."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import pathlib
import re
import subprocess
import sys
from typing import Optional


CATALOG_PATH = "Documentation/ReleaseNotes.json"
ENTRY_DIRECTORY = "Documentation/ReleaseNotes"
LEGACY_SCHEMA_VERSION = 1
SCHEMA_VERSION = 2
SUPPORTED_CATEGORIES = ("new", "improved", "fixed", "internal")
PUBLICATION_CHANNELS = ("stable", "development", "nightly")
ENTRY_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class CatalogValidationError(ValueError):
    """The release-note catalog does not satisfy its repository contract."""


@dataclass(frozen=True)
class ReleaseNoteEntry:
    identifier: str
    category: str
    message: str


@dataclass(frozen=True)
class ReleaseNoteCatalog:
    schema_version: int
    publication_baselines: dict[str, str]
    entries: dict[str, ReleaseNoteEntry]


def unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise CatalogValidationError(f"duplicate JSON key '{key}'")
        value[key] = item
    return value


def parse_catalog_document(contents: str, source: str) -> ReleaseNoteCatalog:
    try:
        document = json.loads(contents, object_pairs_hook=unique_json_object)
    except (json.JSONDecodeError, CatalogValidationError) as error:
        raise CatalogValidationError(f"{source}: {error}") from error

    if not isinstance(document, dict):
        raise CatalogValidationError(f"{source}: catalog root must be an object")
    schema_version = document.get("schemaVersion")
    if schema_version == LEGACY_SCHEMA_VERSION:
        required_fields = {"schemaVersion", "entries"}
    elif schema_version == SCHEMA_VERSION:
        required_fields = {"schemaVersion", "publicationBaselines", "entries"}
    else:
        raise CatalogValidationError(
            f"{source}: schemaVersion must be {LEGACY_SCHEMA_VERSION} or {SCHEMA_VERSION}"
        )
    if set(document) != required_fields:
        required = ", ".join(required_fields)
        raise CatalogValidationError(
            f"{source}: schemaVersion {schema_version} catalog must contain only {required}"
        )

    raw_entries = document["entries"]
    if not isinstance(raw_entries, dict):
        raise CatalogValidationError(f"{source}: entries must be an object")

    entries: dict[str, ReleaseNoteEntry] = {}
    for identifier, raw_entry in raw_entries.items():
        entry_source = f"{source}: entry '{identifier}'"
        if not ENTRY_ID.fullmatch(identifier) or len(identifier) > 80:
            raise CatalogValidationError(
                f"{entry_source}: id must be a lowercase kebab-case value up to 80 characters"
            )
        if not isinstance(raw_entry, dict) or set(raw_entry) != {"category", "message"}:
            raise CatalogValidationError(
                f"{entry_source}: must contain only category and message"
            )

        category = raw_entry["category"]
        message = raw_entry["message"]
        if category not in SUPPORTED_CATEGORIES:
            supported = ", ".join(SUPPORTED_CATEGORIES)
            raise CatalogValidationError(
                f"{entry_source}: category must be one of {supported}"
            )
        if not isinstance(message, str) or not message.strip():
            raise CatalogValidationError(f"{entry_source}: message must be non-empty text")
        if message != message.strip() or "\n" in message or "\r" in message:
            raise CatalogValidationError(
                f"{entry_source}: message must be one trimmed line"
            )
        entries[identifier] = ReleaseNoteEntry(identifier, category, message)

    publication_baselines: dict[str, str] = {}
    if schema_version == SCHEMA_VERSION:
        raw_baselines = document["publicationBaselines"]
        if not isinstance(raw_baselines, dict) or set(raw_baselines) != set(
            PUBLICATION_CHANNELS
        ):
            channels = ", ".join(PUBLICATION_CHANNELS)
            raise CatalogValidationError(
                f"{source}: publicationBaselines must contain exactly {channels}"
            )
        for channel in PUBLICATION_CHANNELS:
            marker = raw_baselines[channel]
            if not isinstance(marker, str) or marker not in entries:
                raise CatalogValidationError(
                    f"{source}: {channel} publication baseline '{marker}' "
                    "must identify a catalog entry"
                )
            publication_baselines[channel] = marker

    return ReleaseNoteCatalog(schema_version, publication_baselines, entries)


def parse_catalog(contents: str, source: str) -> dict[str, ReleaseNoteEntry]:
    return parse_catalog_document(contents, source).entries


def parse_entry_file(contents: str, source: str, identifier: str) -> ReleaseNoteEntry:
    """One entry file: an object holding only the entry's category and message."""
    try:
        raw_entry = json.loads(contents, object_pairs_hook=unique_json_object)
    except (json.JSONDecodeError, CatalogValidationError) as error:
        raise CatalogValidationError(f"{source}: {error}") from error
    wrapped = json.dumps(
        {"schemaVersion": LEGACY_SCHEMA_VERSION, "entries": {identifier: raw_entry}}
    )
    return parse_catalog_document(wrapped, source).entries[identifier]


def entry_identifier(path: str) -> str:
    """The entry id an entry file's name gives it."""
    name = pathlib.PurePosixPath(path).name
    if not name.endswith(".json"):
        raise CatalogValidationError(f"{path}: entry files must be named <id>.json")
    return name[: -len(".json")]


def assemble(
    document: ReleaseNoteCatalog,
    files: list[tuple[str, ReleaseNoteEntry]],
) -> ReleaseNoteCatalog:
    """The document's entries, then each file's entry in the given order.

    An entry the document already holds with the same text is the document's
    own, as in a release checkout that wrote the assembled catalog over it;
    the same id with different text is a duplicate."""
    entries = dict(document.entries)
    for path, entry in files:
        existing = entries.get(entry.identifier)
        if existing is not None:
            if existing == entry and entry.identifier in document.entries:
                continue
            raise CatalogValidationError(f"{path}: release-note id '{entry.identifier}' is already used")
        entries[entry.identifier] = entry
    return ReleaseNoteCatalog(document.schema_version, document.publication_baselines, entries)


def added_order(repository_root: pathlib.Path, reference: str) -> dict[str, int]:
    """The position at which the first-parent history of `reference` added
    each entry file, oldest first. A merge counts as adding what it brought
    in against its first parent."""
    result = subprocess.run(
        [
            "git", "-C", str(repository_root), "log", "--reverse", "--first-parent",
            "--diff-merges=first-parent", "--diff-filter=A", "--name-only",
            "--format=%x00", reference, "--", ENTRY_DIRECTORY,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    order: dict[str, int] = {}
    if result.returncode != 0:
        return order
    for line in result.stdout.splitlines():
        path = line.strip().strip("\0")
        if path.startswith(ENTRY_DIRECTORY + "/") and path not in order:
            order[path] = len(order)
    return order


def ordered_files(paths: list[str], order: dict[str, int]) -> list[str]:
    """`paths` in the order history added them, then the rest by name."""
    return sorted(paths, key=lambda path: (path not in order, order.get(path, 0), path))


def working_entry_files(repository_root: pathlib.Path) -> list[str]:
    directory = repository_root / ENTRY_DIRECTORY
    if not directory.is_dir():
        return []
    return [
        f"{ENTRY_DIRECTORY}/{path.name}"
        for path in directory.iterdir()
        if path.is_file() and not path.name.startswith(".")
    ]


def assembled_working_catalog(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    """The catalog in the working tree, in release order."""
    document = working_catalog_document(repository_root)
    paths = ordered_files(working_entry_files(repository_root), added_order(repository_root, "HEAD"))
    files = [
        (path, parse_entry_file((repository_root / path).read_text(), path, entry_identifier(path)))
        for path in paths
    ]
    return assemble(document, files)


def assembled_catalog_at(repository_root: pathlib.Path, reference: str) -> Optional[ReleaseNoteCatalog]:
    """The catalog a commit holds, in release order, or None without one."""
    contents = git_file(repository_root, f"{reference}:{CATALOG_PATH}")
    if contents is None:
        return None
    document = parse_catalog_document(contents, f"{reference}:{CATALOG_PATH}")
    listing = subprocess.run(
        ["git", "-C", str(repository_root), "ls-tree", "--name-only", f"{reference}:{ENTRY_DIRECTORY}"],
        check=False,
        capture_output=True,
        text=True,
    )
    names = listing.stdout.split() if listing.returncode == 0 else []
    paths = ordered_files([f"{ENTRY_DIRECTORY}/{name}" for name in names], added_order(repository_root, reference))
    files = []
    for path in paths:
        source = f"{reference}:{path}"
        contents = git_file(repository_root, source)
        if contents is None:
            raise CatalogValidationError(f"{source} is unreadable")
        files.append((path, parse_entry_file(contents, source, entry_identifier(path))))
    return assemble(document, files)


def assembled_document(catalog: ReleaseNoteCatalog) -> str:
    """The assembled catalog as one catalog document."""
    document: dict[str, object] = {"schemaVersion": catalog.schema_version}
    if catalog.schema_version == SCHEMA_VERSION:
        document["publicationBaselines"] = dict(catalog.publication_baselines)
    document["entries"] = {
        identifier: {"category": entry.category, "message": entry.message}
        for identifier, entry in catalog.entries.items()
    }
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def git_file(repository_root: pathlib.Path, object_name: str) -> Optional[str]:
    result = subprocess.run(
        ["git", "-C", str(repository_root), "show", object_name],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout
    return None


def working_catalog(repository_root: pathlib.Path) -> dict[str, ReleaseNoteEntry]:
    return assembled_working_catalog(repository_root).entries


def working_catalog_document(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    catalog_path = repository_root / CATALOG_PATH
    if not catalog_path.is_file():
        raise CatalogValidationError(f"{CATALOG_PATH} is missing")
    return parse_catalog_document(catalog_path.read_text(), CATALOG_PATH)


def staged_catalog(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    contents = git_file(repository_root, f":{CATALOG_PATH}")
    if contents is None:
        raise CatalogValidationError(f"stage {CATALOG_PATH} with the current commit")
    return parse_catalog_document(contents, f"staged {CATALOG_PATH}")


def head_catalog(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    contents = git_file(repository_root, f"HEAD:{CATALOG_PATH}")
    if contents is None:
        return ReleaseNoteCatalog(LEGACY_SCHEMA_VERSION, {}, {})
    return parse_catalog_document(contents, f"HEAD {CATALOG_PATH}")


def staged_entry_changes(repository_root: pathlib.Path) -> list[tuple[str, str]]:
    """Each staged change under the entry directory, as (status, path)."""
    result = subprocess.run(
        ["git", "-C", str(repository_root), "diff", "--cached", "--name-status",
         "--no-renames", "HEAD", "--", ENTRY_DIRECTORY],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        result = subprocess.run(
            ["git", "-C", str(repository_root), "diff", "--cached", "--name-status",
             "--no-renames", "--root", "--", ENTRY_DIRECTORY],
            check=True,
            capture_output=True,
            text=True,
        )
    return [tuple(line.split("\t", 1)) for line in result.stdout.splitlines() if line.strip()]


def validate_staged_entry(repository_root: pathlib.Path) -> tuple[str, ...]:
    """A change commit adds at least one entry file and leaves every entry
    the branch already holds, in the document or a file, as it was."""
    previous_document = head_catalog(repository_root)
    current_document = staged_catalog(repository_root)
    if previous_document.entries and current_document != previous_document:
        raise CatalogValidationError(
            f"{CATALOG_PATH} is frozen: add a new entry as {ENTRY_DIRECTORY}/<id>.json instead"
        )

    added: list[tuple[str, ReleaseNoteEntry]] = []
    for status, path in staged_entry_changes(repository_root):
        if status != "A":
            raise CatalogValidationError(
                f"catalog commits must not change or delete an existing entry file: {path}"
            )
        contents = git_file(repository_root, f":{path}")
        if contents is None:
            raise CatalogValidationError(f"stage {path} with the current commit")
        added.append((path, parse_entry_file(contents, f"staged {path}", entry_identifier(path))))

    if not added:
        raise CatalogValidationError(
            f"stage at least one new release-note entry as {ENTRY_DIRECTORY}/<id>.json"
        )
    head = assembled_catalog_at(repository_root, "HEAD") or ReleaseNoteCatalog(
        current_document.schema_version, current_document.publication_baselines, dict(current_document.entries))
    assemble(head, added)
    return tuple(entry.identifier for _, entry in added)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--require-staged-entry", action="store_true")
    parser.add_argument(
        "--write-assembled",
        action="store_true",
        help=f"write the assembled catalog over {CATALOG_PATH}; release checkouts only, never committed",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.require_staged_entry:
            added_entries = validate_staged_entry(arguments.repository_root)
            print(f"Validated new release-note entries: {', '.join(added_entries)}")
            return 0

        catalog = assembled_working_catalog(arguments.repository_root)
        if arguments.write_assembled:
            (arguments.repository_root / CATALOG_PATH).write_text(assembled_document(catalog))
            print(f"Wrote {len(catalog.entries)} release-note entries to {CATALOG_PATH}.")
            return 0
        print(f"Validated {len(catalog.entries)} release-note entries.")
        return 0
    except (CatalogValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
