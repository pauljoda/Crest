#!/usr/bin/env python3
"""Validate Crest's release notes under Documentation/ReleaseNotes.

A pull request that changes Crest adds one fragment, `changes/<slug>.json`,
and never touches the version:

    {
      "entries": [
        { "id": "kebab-case-id", "category": "fixed", "message": "...", "platforms": ["mac"] }
      ]
    }

A fragment's entries belong to the version of the commit that adds it to main,
which `crest_version.py` computes from git, so pull requests merge in any order.
A pull request with several fixes lists one entry for each in its fragment.

`<major>.<minor>/<version>.json` files are history: the entries of the versions
from before versions came from git, and `release`, the curated write-up of a
version published as Stable:

    { "release": { "summary": "...", "added": ["..."], "fixed": ["..."] }, "entries": [...] }

A Stable release from now on adds its write-up as a version file holding only
`release`, named for the version of the commit that adds it
(`crest_version.py next`).

An entry's ID, category, message and platforms never change once it is on main,
and it never moves or goes away. Write-ups may be written and edited at any
time. Leaving out `platforms` means the change reaches every platform, the
desktop shell for Windows and Linux included; a change only the Apple apps
receive lists `mac`, `ios` or both.

    release_note_catalog.py                       check the notes in the working tree
    release_note_catalog.py --pull-request BASE   check what HEAD changes since its merge base with BASE
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, replace
import json
import pathlib
import re
import subprocess
import sys
from typing import Iterable, Mapping, Optional

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from crest_version import (  # noqa: E402
    VERSION_FILE_PATH,
    MainCommit,
    Version,
    VersionError,
    place,
)


CATALOG_DIRECTORY = "Documentation/ReleaseNotes"
# Fragments live here, relative to the catalog directory.
FRAGMENT_DIRECTORY = "changes"
# The single catalog file the version files replaced; read only to compare a
# commit against a parent that still has it.
LEGACY_CATALOG_PATH = "Documentation/ReleaseNotes.json"
SUPPORTED_CATEGORIES = ("new", "improved", "fixed", "internal")
PUBLIC_CATEGORIES = ("new", "improved", "fixed")
PLATFORMS = ("mac", "ios", "windows", "linux")
RELEASE_SECTIONS = ("added", "changed", "fixed", "security", "removed", "upgrading")
PUBLICATION_CHANNELS = ("stable", "development", "nightly")
ENTRY_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
# What a pull request may change without a release note: documentation,
# Markdown anywhere, the repository's own tooling, and the version file, which
# has its own rule. Everything else reaches the apps.
NOTE_FREE_FOLDERS = ("Documentation/", "HelpCenter/", ".github/", ".agents/", ".claude/", "ci_scripts/", "Scripts/")
# Engine and packaging scripts shape what ships.
NOTED_FOLDERS = ("Scripts/control-plane/",)
NOTE_FREE_FILES = (VERSION_FILE_PATH, "LICENSE", "NOTICE")


class CatalogValidationError(ValueError):
    """The release notes do not satisfy their repository contract."""


# MARK: - Types


@dataclass(frozen=True)
class ReleaseNoteEntry:
    identifier: str
    category: str
    message: str
    platforms: tuple[str, ...]
    # Set when the catalog is assembled; a fragment's comes from git.
    version: Optional[Version] = None

    @property
    def is_public(self) -> bool:
        return self.category in PUBLIC_CATEGORIES

    def reaches(self, platform: str) -> bool:
        return not self.platforms or platform in self.platforms

    @property
    def content(self) -> tuple[str, str, tuple[str, ...]]:
        """What may never change once the entry is on main."""
        return (self.category, self.message, self.platforms)


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
class NotesFile:
    """One file of the catalog: a version's file or a fragment."""

    # Relative to the catalog directory.
    path: str
    # The version a version file is named for; None for a fragment.
    named_version: Optional[Version]
    entries: tuple[ReleaseNoteEntry, ...]
    write_up: Optional[ReleaseWriteUp]

    @property
    def is_fragment(self) -> bool:
        return self.named_version is None


@dataclass(frozen=True)
class VersionNotes:
    version: Version
    entries: tuple[ReleaseNoteEntry, ...]
    write_up: Optional[ReleaseWriteUp]
    # The day the commit that gave this version its fragments reached main;
    # None for a version file's version.
    landed: Optional[str] = None

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


def parse_entry(raw: object, source: str) -> ReleaseNoteEntry:
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
    return ReleaseNoteEntry(identifier, category, message, platforms)


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


def named_version(relative_path: str) -> Optional[Version]:
    """The version a version file is named for, or None for a fragment, checking where each lives."""
    source = f"{CATALOG_DIRECTORY}/{relative_path}"
    parts = relative_path.split("/")
    if parts[0] == FRAGMENT_DIRECTORY:
        if len(parts) != 2 or not parts[1].endswith(".json") or not ENTRY_ID.fullmatch(parts[1][: -len(".json")]):
            raise CatalogValidationError(
                f"{source}: fragments live at {FRAGMENT_DIRECTORY}/<kebab-case-slug>.json"
            )
        return None
    if len(parts) != 2 or not parts[1].endswith(".json"):
        raise CatalogValidationError(
            f"{source}: notes live at <major>.<minor>/<version>.json or {FRAGMENT_DIRECTORY}/<slug>.json"
        )
    try:
        version = Version.parse(parts[1][: -len(".json")])
    except VersionError as error:
        raise CatalogValidationError(f"{source}: {error}") from error
    if parts[0] != version.line:
        raise CatalogValidationError(f"{source}: belongs in the {version.line} folder")
    return version


def notes_file(relative_path: str, contents: str) -> NotesFile:
    source = f"{CATALOG_DIRECTORY}/{relative_path}"
    version = named_version(relative_path)
    try:
        document = json.loads(contents, object_pairs_hook=unique_json_object)
    except (json.JSONDecodeError, CatalogValidationError) as error:
        raise CatalogValidationError(f"{source}: {error}") from error
    allowed = {"entries"} if version is None else {"entries", "release"}
    if not isinstance(document, dict) or not document or not set(document) <= allowed:
        expected = "entries" if version is None else "entries, a release write-up, or both"
        raise CatalogValidationError(f"{source}: must hold {expected}")
    raw_entries = document.get("entries", [])
    if not isinstance(raw_entries, list):
        raise CatalogValidationError(f"{source}: entries must be a list")
    entries = tuple(parse_entry(raw, source) for raw in raw_entries)
    write_up = parse_write_up(document["release"], source) if "release" in document else None
    if not entries and write_up is None:
        raise CatalogValidationError(f"{source}: add at least one entry")
    return NotesFile(relative_path, version, entries, write_up)


def notes_files(documents: Iterable[tuple[str, str]]) -> list[NotesFile]:
    """The files of a catalog, checking each and that no entry ID repeats."""
    files = [notes_file(path, contents) for path, contents in documents]
    seen: dict[str, str] = {}
    for file in files:
        for entry in file.entries:
            if entry.identifier in seen:
                raise CatalogValidationError(
                    f"entry id '{entry.identifier}' is in both {seen[entry.identifier]} and {file.path}"
                )
            seen[entry.identifier] = file.path
    return files


# MARK: - Assembly


@dataclass(frozen=True)
class FragmentVersions:
    """The main commit that added each fragment, and the version of a fragment that isn't on main yet."""

    added_by: Mapping[str, MainCommit]
    pending: Version


def assemble(
    documents: Iterable[tuple[str, str]],
    fragment_versions: Optional[FragmentVersions] = None,
) -> ReleaseNoteCatalog:
    """A catalog from (path relative to the catalog directory, contents) pairs.

    Release order is by version, then a version's file, then its fragments by
    path, each as written.
    """
    files = sorted(notes_files(documents), key=lambda file: (file.is_fragment, file.path))
    grouped: dict[Version, list[NotesFile]] = {}
    landed: dict[Version, str] = {}
    for file in files:
        version = file.named_version
        if version is None:
            if fragment_versions is None:
                raise CatalogValidationError(f"{file.path} is a fragment; read the catalog from git")
            commit = fragment_versions.added_by.get(file.path)
            version = commit.version if commit is not None else fragment_versions.pending
            if commit is not None:
                landed.setdefault(version, commit.date)
        grouped.setdefault(version, []).append(file)

    versions = []
    for version in sorted(grouped):
        version_files = grouped[version]
        write_ups = [file.write_up for file in version_files if file.write_up is not None]
        entries = tuple(
            replace(entry, version=version)
            for file in version_files
            for entry in file.entries
        )
        versions.append(VersionNotes(version, entries, write_ups[0] if write_ups else None, landed.get(version)))
    return ReleaseNoteCatalog(tuple(versions))


def has_fragments(documents: list[tuple[str, str]]) -> bool:
    return any(path.startswith(f"{FRAGMENT_DIRECTORY}/") for path, _ in documents)


# MARK: - Git


def git(repository_root: pathlib.Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=False,
        capture_output=True,
        text=True,
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


def documents_in(directory: pathlib.Path) -> list[tuple[str, str]]:
    if not directory.is_dir():
        raise CatalogValidationError(f"{CATALOG_DIRECTORY} is missing")
    return [
        (path.relative_to(directory).as_posix(), path.read_text())
        for path in sorted(directory.rglob("*"))
        if not path.is_dir() and path.name != ".DS_Store"
    ]


def documents_at(repository_root: pathlib.Path, treeish: str) -> list[tuple[str, str]]:
    listing = git(repository_root, "ls-tree", "-r", treeish, "--", CATALOG_DIRECTORY)
    if listing.returncode != 0:
        raise CatalogValidationError(f"cannot read {treeish}: {listing.stderr.strip()}")
    rows = [line.split(None, 3) for line in listing.stdout.splitlines()]
    blobs = [(row[3], row[2]) for row in rows if not row[3].endswith("/.DS_Store")]
    prefix = f"{CATALOG_DIRECTORY}/"
    contents = read_blobs(repository_root, [blob for _, blob in blobs])
    return [(path[len(prefix) :], text) for (path, _), text in zip(blobs, contents)]


def fragment_versions(repository_root: pathlib.Path, ref: str) -> FragmentVersions:
    """The main commit that added each fragment `ref` can see; one not on main yet is pending."""
    try:
        placement = place(repository_root, ref)
    except VersionError as error:
        raise CatalogValidationError(str(error)) from error
    log = git(
        repository_root,
        "log",
        "--first-parent",
        "--diff-merges=first-parent",
        "--no-renames",
        "--diff-filter=A",
        "--name-only",
        "--format=%x00%H",
        placement.commit.sha,
        "--",
        f"{CATALOG_DIRECTORY}/{FRAGMENT_DIRECTORY}/",
    )
    if log.returncode != 0:
        raise CatalogValidationError(f"cannot read the fragments' history: {log.stderr.strip()}")
    added_by: dict[str, MainCommit] = {}
    prefix = f"{CATALOG_DIRECTORY}/"
    commit: Optional[MainCommit] = None
    for line in log.stdout.splitlines():
        if line.startswith("\0"):
            commit = placement.history.by_sha.get(line[1:])
        elif line.startswith(prefix) and commit is not None:
            # The log runs newest first; the newest add is the one in the tree.
            added_by.setdefault(line[len(prefix) :], commit)
    return FragmentVersions(added_by, placement.next)


def read_catalog_at(repository_root: pathlib.Path, treeish: str) -> Optional[ReleaseNoteCatalog]:
    """The catalog in a commit; None when it has none."""
    documents = documents_at(repository_root, treeish)
    if not documents:
        return None
    versions = fragment_versions(repository_root, treeish) if has_fragments(documents) else None
    return assemble(documents, versions)


def read_working_catalog(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    """The catalog in the working tree; a fragment HEAD's main history hasn't added is pending."""
    documents = documents_in(repository_root / CATALOG_DIRECTORY)
    versions = fragment_versions(repository_root, "HEAD") if has_fragments(documents) else None
    return assemble(documents, versions)


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


def validate_working_tree(repository_root: pathlib.Path) -> list[NotesFile]:
    """The notes in the working tree, checked without git."""
    files = notes_files(documents_in(repository_root / CATALOG_DIRECTORY))
    version_file = repository_root / VERSION_FILE_PATH
    if version_file.is_file():
        anchor = Version.from_version_file(version_file.read_text(), VERSION_FILE_PATH)
        for file in files:
            if file.entries and file.named_version is not None and file.named_version > anchor:
                raise CatalogValidationError(
                    f"{CATALOG_DIRECTORY}/{file.path} adds entries to a version past {anchor}; "
                    f"new entries go in {CATALOG_DIRECTORY}/{FRAGMENT_DIRECTORY}/<slug>.json"
                )
    return files


def needs_note(path: str) -> bool:
    """Whether a change to `path` reaches the apps, so its pull request needs a release note."""
    if path in NOTE_FREE_FILES or path.endswith(".md"):
        return False
    if path.startswith(NOTED_FOLDERS):
        return True
    if path.startswith(NOTE_FREE_FOLDERS):
        return False
    return "/" in path or not path.startswith(".")


def validate_pull_request(repository_root: pathlib.Path, base: str, head: str = "HEAD") -> tuple[str, ...]:
    """The entries a pull request adds, after checking it follows the fragment rules.

    The pull request is what `head` changes since its merge base with `base`.
    """
    merge_base = git(repository_root, "merge-base", base, head)
    if merge_base.returncode != 0:
        raise CatalogValidationError(f"{head} shares no history with {base}")
    merge_base_sha = merge_base.stdout.strip()
    diff = git(repository_root, "diff", "--no-renames", "--name-only", merge_base_sha, head)
    if diff.returncode != 0:
        raise CatalogValidationError(f"cannot compare {head} with {base}: {diff.stderr.strip()}")
    changed = diff.stdout.splitlines()

    if VERSION_FILE_PATH in changed:
        before = file_at(repository_root, f"{merge_base_sha}:{VERSION_FILE_PATH}")
        after = file_at(repository_root, f"{head}:{VERSION_FILE_PATH}")
        if before is None or after is None:
            raise CatalogValidationError(f"pull requests keep {VERSION_FILE_PATH}")
        try:
            previous = Version.from_version_file(before, f"{base}:{VERSION_FILE_PATH}")
            proposed = Version.from_version_file(after, f"{head}:{VERSION_FILE_PATH}")
        except VersionError as error:
            raise CatalogValidationError(str(error)) from error
        if (proposed.major, proposed.minor) <= (previous.major, previous.minor):
            raise CatalogValidationError(
                f"{VERSION_FILE_PATH} changes only to open a new release line "
                f"(Scripts/set-version.sh --release); versions come from git, so leave it at {previous}"
            )

    before_files = {file.path: file for file in notes_files(documents_at(repository_root, merge_base_sha))}
    after_files = {file.path: file for file in notes_files(documents_at(repository_root, head))}

    changed_entries: dict[str, None] = {}
    for path, file in before_files.items():
        later_entries = after_files[path].entries if path in after_files else ()
        later = {entry.identifier: entry for entry in later_entries}
        changed_entries.update(
            (entry.identifier, None)
            for entry in file.entries
            if entry.identifier not in later or later[entry.identifier].content != entry.content
        )
        # Release order is as written, and the channels' cursors depend on it.
        existing = {entry.identifier for entry in file.entries}
        kept = [entry.identifier for entry in file.entries if entry.identifier in later]
        reordered = [entry.identifier for entry in later_entries if entry.identifier in existing]
        changed_entries.update((now, None) for now, then in zip(reordered, kept) if now != then)
    if changed_entries:
        raise CatalogValidationError(
            f"release-note entries on main never change, move or go away: {', '.join(changed_entries)}"
        )

    added: list[str] = []
    misplaced: list[str] = []
    for path, file in after_files.items():
        earlier = {entry.identifier for entry in before_files[path].entries} if path in before_files else set()
        new = [entry.identifier for entry in file.entries if entry.identifier not in earlier]
        if file.is_fragment and path not in before_files:
            added.extend(new)
        else:
            misplaced.extend(new)
    if misplaced:
        raise CatalogValidationError(
            f"new entries go in a new fragment, {CATALOG_DIRECTORY}/{FRAGMENT_DIRECTORY}/<slug>.json, "
            f"not in a version file or an existing fragment: {', '.join(misplaced)}"
        )
    noted = [path for path in changed if needs_note(path)]
    if noted and not added:
        raise CatalogValidationError(
            f"this pull request changes the apps ({noted[0]}"
            + (f" and {len(noted) - 1} more" if len(noted) > 1 else "")
            + f"); add a fragment, {CATALOG_DIRECTORY}/{FRAGMENT_DIRECTORY}/<slug>.json, with its entries"
        )
    return tuple(added)


# MARK: - Writing


def format_document(document: dict[str, object]) -> str:
    """A notes file's canonical text: two-space JSON with platform lists on one line."""
    text = json.dumps(document, indent=2, ensure_ascii=False)
    text = re.sub(
        r'"platforms": \[([^\]]*)\]',
        lambda match: '"platforms": ['
        + ", ".join(part.strip() for part in match.group(1).split(","))
        + "]",
        text,
    )
    return text + "\n"


def new_fragment(
    repository_root: pathlib.Path, slug: str, entries: list[dict[str, object]]
) -> tuple[pathlib.Path, str]:
    """The path and checked text of a new fragment with `entries`, refusing to replace one."""
    relative_path = f"{FRAGMENT_DIRECTORY}/{slug}.json"
    path = repository_root / CATALOG_DIRECTORY / relative_path
    if path.exists():
        raise CatalogValidationError(f"{CATALOG_DIRECTORY}/{relative_path} already exists")
    text = format_document({"entries": entries})
    notes_file(relative_path, text)
    return path, text


def write_fragment(repository_root: pathlib.Path, slug: str, entries: list[dict[str, object]]) -> pathlib.Path:
    """Write a new fragment with `entries`, refusing to replace one."""
    path, text = new_fragment(repository_root, slug, entries)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


# MARK: - Command line


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--pull-request", metavar="BASE", help="check what HEAD changes since its merge base with BASE")
    parser.add_argument("--head", default="HEAD", help="the pull request's commit (default HEAD)")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.pull_request:
            added = validate_pull_request(arguments.repository_root, arguments.pull_request, arguments.head)
            if added:
                print(f"Validated the pull request's release notes: {', '.join(added)}")
            else:
                print("Validated the pull request: it changes neither the apps nor their release notes.")
            return 0

        files = validate_working_tree(arguments.repository_root)
        fragments = [file for file in files if file.is_fragment]
        entries = sum(len(file.entries) for file in files)
        print(
            f"Validated {entries} release-note entries "
            f"in {len(files) - len(fragments)} version files and {len(fragments)} fragments."
        )
        return 0
    except (CatalogValidationError, VersionError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
