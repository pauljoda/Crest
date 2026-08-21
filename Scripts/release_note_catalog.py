#!/usr/bin/env python3
"""Validate Crest's explicit, history-stable release-note catalog."""

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
SCHEMA_VERSION = 1
SUPPORTED_CATEGORIES = ("new", "improved", "fixed", "internal")
ENTRY_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class CatalogValidationError(ValueError):
    """The release-note catalog does not satisfy its repository contract."""


@dataclass(frozen=True)
class ReleaseNoteEntry:
    identifier: str
    category: str
    message: str


def unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise CatalogValidationError(f"duplicate JSON key '{key}'")
        value[key] = item
    return value


def parse_catalog(contents: str, source: str) -> dict[str, ReleaseNoteEntry]:
    try:
        document = json.loads(contents, object_pairs_hook=unique_json_object)
    except (json.JSONDecodeError, CatalogValidationError) as error:
        raise CatalogValidationError(f"{source}: {error}") from error

    if not isinstance(document, dict):
        raise CatalogValidationError(f"{source}: catalog root must be an object")
    if set(document) != {"schemaVersion", "entries"}:
        raise CatalogValidationError(
            f"{source}: catalog must contain only schemaVersion and entries"
        )
    if document["schemaVersion"] != SCHEMA_VERSION:
        raise CatalogValidationError(
            f"{source}: schemaVersion must be {SCHEMA_VERSION}"
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

    return entries


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
    catalog_path = repository_root / CATALOG_PATH
    if not catalog_path.is_file():
        raise CatalogValidationError(f"{CATALOG_PATH} is missing")
    return parse_catalog(catalog_path.read_text(), CATALOG_PATH)


def staged_catalog(repository_root: pathlib.Path) -> dict[str, ReleaseNoteEntry]:
    contents = git_file(repository_root, f":{CATALOG_PATH}")
    if contents is None:
        raise CatalogValidationError(f"stage {CATALOG_PATH} with the current commit")
    return parse_catalog(contents, f"staged {CATALOG_PATH}")


def head_catalog(repository_root: pathlib.Path) -> dict[str, ReleaseNoteEntry]:
    contents = git_file(repository_root, f"HEAD:{CATALOG_PATH}")
    if contents is None:
        return {}
    return parse_catalog(contents, f"HEAD {CATALOG_PATH}")


def validate_staged_entry(repository_root: pathlib.Path) -> tuple[str, ...]:
    previous_entries = head_catalog(repository_root)
    current_entries = staged_catalog(repository_root)
    deleted_entries = tuple(sorted(previous_entries.keys() - current_entries.keys()))
    if deleted_entries:
        deleted = ", ".join(deleted_entries)
        raise CatalogValidationError(
            f"catalog commits must not delete release-note entries: {deleted}"
        )

    previous_order = tuple(previous_entries)
    current_order = tuple(current_entries)
    if current_order[: len(previous_order)] != previous_order:
        raise CatalogValidationError(
            "append new release-note entries after the existing catalog order"
        )

    added_entries = tuple(sorted(current_entries.keys() - previous_entries.keys()))
    if not added_entries:
        raise CatalogValidationError(
            f"stage at least one new release-note entry in {CATALOG_PATH}"
        )
    return added_entries


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
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

        entries = working_catalog(arguments.repository_root)
        print(f"Validated {len(entries)} release-note entries.")
        return 0
    except (CatalogValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
