#!/usr/bin/env python3
"""Turn a branch's version bump and per-version entries into one release-note fragment.

Branches made before versions came from git bump `Config/Version.xcconfig` and
add their entries to version files under `Documentation/ReleaseNotes`, or, if
older still, to the single `Documentation/ReleaseNotes.json`. Run this in the
branch's checkout, with its work committed: it moves every entry the branch
added there into one new fragment, takes those entries back out, and puts
`Config/Version.xcconfig` back as the branch found it. It changes only the
working tree, so review it, then:

    git add -A Config Documentation
    git commit -s -m "Move the release notes to a fragment"
    git merge origin/main        # or squash the branch and rebase it
    python3 Scripts/release_note_catalog.py --pull-request origin/main

The branch is compared with its merge base with `--base` (origin/main by
default). The fragment is named for `--slug`, or for the branch's first entry.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from crest_version import VERSION_FILE_PATH  # noqa: E402
from release_note_catalog import (  # noqa: E402
    CATALOG_DIRECTORY,
    LEGACY_CATALOG_PATH,
    CatalogValidationError,
    documents_at,
    file_at,
    format_document,
    notes_files,
    unique_json_object,
    write_fragment,
)


def git(repository_root: pathlib.Path, *arguments: str) -> str:
    result = subprocess.run(["git", "-C", str(repository_root), *arguments], capture_output=True, text=True)
    if result.returncode != 0:
        raise CatalogValidationError(f"git {' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def raw_entry(entry) -> dict[str, object]:
    raw: dict[str, object] = {"id": entry.identifier, "category": entry.category, "message": entry.message}
    if entry.platforms:
        raw["platforms"] = list(entry.platforms)
    return raw


def legacy_entries(repository_root: pathlib.Path, commit: str) -> dict[str, dict[str, object]]:
    """The entries of the single catalog file the version files replaced, by ID, as written."""
    contents = file_at(repository_root, f"{commit}:{LEGACY_CATALOG_PATH}")
    if contents is None:
        return {}
    return json.loads(contents, object_pairs_hook=unique_json_object)["entries"]


def convert_legacy(repository_root: pathlib.Path, merge_base: str, known: set[str]) -> list[dict[str, object]]:
    """Take the entries the branch added to the single catalog file back out, returning them."""
    added = {
        identifier: raw
        for identifier, raw in legacy_entries(repository_root, "HEAD").items()
        if identifier not in legacy_entries(repository_root, merge_base) and identifier not in known
    }
    if not added:
        return []
    path = repository_root / LEGACY_CATALOG_PATH
    original = file_at(repository_root, f"{merge_base}:{LEGACY_CATALOG_PATH}")
    if original is None:
        path.unlink()
    else:
        path.write_text(original)
    return [
        {"id": identifier, **{key: raw[key] for key in ("category", "message", "platforms") if key in raw}}
        for identifier, raw in added.items()
    ]


def convert(repository_root: pathlib.Path, base: str, slug: str | None) -> list[str]:
    """Rewrite the working tree; returns the paths it changed."""
    if git(repository_root, "status", "--porcelain", "--untracked-files=no"):
        raise CatalogValidationError("commit or set aside the branch's changes first")
    merge_base = git(repository_root, "merge-base", base, "HEAD")
    before = {file.path: file for file in notes_files(documents_at(repository_root, merge_base))}
    after = notes_files(documents_at(repository_root, "HEAD"))
    known = {entry.identifier for file in before.values() for entry in file.entries}

    moved = []
    touched = []
    for file in sorted(after, key=lambda file: (file.named_version is None, file.named_version, file.path)):
        if file.is_fragment:
            continue
        added = [entry for entry in file.entries if entry.identifier not in known]
        if added:
            moved.extend(added)
            touched.append(file)

    changed: list[str] = []
    entries = convert_legacy(repository_root, merge_base, known)
    if entries:
        changed.append(LEGACY_CATALOG_PATH)
    version_file = repository_root / VERSION_FILE_PATH
    original_version_file = file_at(repository_root, f"{merge_base}:{VERSION_FILE_PATH}")
    if original_version_file is not None and version_file.read_text() != original_version_file:
        version_file.write_text(original_version_file)
        changed.append(VERSION_FILE_PATH)
    entries.extend(raw_entry(entry) for entry in moved)
    if not entries:
        return changed

    for file in touched:
        relative_path = f"{CATALOG_DIRECTORY}/{file.path}"
        path = repository_root / relative_path
        document = json.loads(path.read_text(), object_pairs_hook=unique_json_object)
        original = before.get(file.path)
        if original is not None and original.write_up == file.write_up:
            # The branch only added entries; the file goes back as it was.
            path.write_text(file_at(repository_root, f"{merge_base}:{relative_path}"))
        else:
            remaining = [raw for raw in document.get("entries", []) if raw["id"] in known]
            document = {key: value for key, value in document.items() if key == "release"}
            if remaining:
                document["entries"] = remaining
            if document:
                path.write_text(format_document(document))
            else:
                path.unlink()
        changed.append(relative_path)

    fragment = write_fragment(repository_root, slug or str(entries[0]["id"]), entries)
    changed.append(str(fragment.relative_to(repository_root)))
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--base", default="origin/main", help="the branch the pull request merges into")
    parser.add_argument("--slug", help="the fragment's name; defaults to the branch's first entry ID")
    arguments = parser.parse_args()
    try:
        changed = convert(arguments.repository_root, arguments.base, arguments.slug)
    except (CatalogValidationError, ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if not changed:
        print("The branch adds no entries to version files and keeps the version; nothing to convert.")
        return 0
    print("Changed:")
    for path in changed:
        print(f"  {path}")
    print("Review, commit with the new fragment, merge the base, then run "
          "`python3 Scripts/release_note_catalog.py --pull-request origin/main`.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
