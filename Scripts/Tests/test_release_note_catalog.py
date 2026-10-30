#!/usr/bin/env python3
"""Contract coverage for Crest's explicit release-note catalog."""

from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG_SCRIPT = REPOSITORY_ROOT / "Scripts" / "release_note_catalog.py"


class ReleaseNoteCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository = pathlib.Path(self.temporary_directory.name)
        subprocess.run(
            ["git", "init", "--initial-branch=main"],
            cwd=self.repository,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Crest Tests"],
            cwd=self.repository,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.email", "tests@crestbrowser.com"],
            cwd=self.repository,
            check=True,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_catalog(
        self,
        entries: dict[str, dict[str, str]],
        publication_baselines: dict[str, str] | None = None,
    ) -> None:
        catalog = self.repository / "Documentation" / "ReleaseNotes.json"
        catalog.parent.mkdir(parents=True, exist_ok=True)
        document: dict[str, object] = {
            "schemaVersion": 1,
            "entries": entries,
        }
        if publication_baselines is not None:
            document = {
                "schemaVersion": 2,
                "publicationBaselines": publication_baselines,
                "entries": entries,
            }
        catalog.write_text(
            json.dumps(document, indent=2) + "\n"
        )

    def run_catalog_check(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "python3",
                str(CATALOG_SCRIPT),
                "--repository-root",
                str(self.repository),
                *arguments,
            ],
            cwd=self.repository,
            check=False,
            capture_output=True,
            text=True,
        )

    def commit_catalog(self) -> None:
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )
        subprocess.run(
            ["git", "commit", "-m", "catalog baseline"],
            cwd=self.repository,
            check=True,
            capture_output=True,
        )

    def test_version_two_catalog_requires_a_valid_baseline_for_each_channel(self) -> None:
        entries = {
            "stable-boundary": {
                "category": "internal",
                "message": "Record the stable publication boundary",
            },
            "development-boundary": {
                "category": "internal",
                "message": "Record the development publication boundary",
            },
            "nightly-boundary": {
                "category": "internal",
                "message": "Record the nightly publication boundary",
            },
        }
        valid_baselines = {
            "stable": "stable-boundary",
            "development": "development-boundary",
            "nightly": "nightly-boundary",
        }

        self.write_catalog(entries, valid_baselines)
        valid = self.run_catalog_check()
        self.assertEqual(valid.returncode, 0, valid.stderr)

        for invalid_baselines in (
            {"stable": "stable-boundary", "nightly": "nightly-boundary"},
            valid_baselines | {"preview": "nightly-boundary"},
            valid_baselines | {"nightly": "missing-entry"},
        ):
            with self.subTest(invalid_baselines=invalid_baselines):
                self.write_catalog(entries, invalid_baselines)
                invalid = self.run_catalog_check()
                self.assertNotEqual(invalid.returncode, 0)

    def test_catalog_rejects_unknown_fields_categories_and_invalid_ids(self) -> None:
        invalid_catalogs = (
            {
                "Bad ID": {
                    "category": "new",
                    "message": "Add a valid feature description",
                }
            },
            {
                "valid-id": {
                    "category": "changed",
                    "message": "Describe an unsupported category",
                }
            },
            {
                "valid-id": {
                    "category": "fixed",
                    "message": "Describe a valid fix",
                    "commit": "impossible-self-reference",
                }
            },
        )

        for entries in invalid_catalogs:
            with self.subTest(entries=entries):
                self.write_catalog(entries)
                result = self.run_catalog_check()
                self.assertNotEqual(result.returncode, 0)

    def write_entry(self, identifier: str, category: str, message: str) -> str:
        path = self.repository / "Documentation" / "ReleaseNotes" / f"{identifier}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"category": category, "message": message}) + "\n")
        return str(path.relative_to(self.repository))

    def commit(self, *paths: str, message: str = "change") -> None:
        subprocess.run(["git", "add", *paths], cwd=self.repository, check=True)
        subprocess.run(["git", "commit", "-m", message], cwd=self.repository, check=True, capture_output=True)

    def test_a_change_adds_an_entry_file_and_leaves_existing_entries_alone(self) -> None:
        entries = {"existing-change": {"category": "fixed", "message": "Keep existing behavior reliable"}}
        self.write_catalog(entries)
        self.commit_catalog()

        no_change = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(no_change.returncode, 0)
        self.assertIn("stage at least one new release-note entry", no_change.stderr)

        added_path = self.write_entry("new-change", "improved", "Make the current workflow easier to understand")
        subprocess.run(["git", "add", added_path], cwd=self.repository, check=True)
        added = self.run_catalog_check("--require-staged-entry")
        self.assertEqual(added.returncode, 0, added.stderr)
        self.assertIn("new-change", added.stdout)
        subprocess.run(["git", "commit", "-m", "entry"], cwd=self.repository, check=True, capture_output=True)

        # The document is frozen: an entry added to it is refused.
        entries["late-change"] = {"category": "new", "message": "Append to the old document"}
        self.write_catalog(entries)
        subprocess.run(["git", "add", "Documentation/ReleaseNotes.json"], cwd=self.repository, check=True)
        frozen = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(frozen.returncode, 0)
        self.assertIn("is frozen", frozen.stderr)
        subprocess.run(["git", "reset", "-q", "--hard"], cwd=self.repository, check=True)

        # An entry file already merged is never rewritten.
        self.write_entry("new-change", "improved", "Rewritten release copy")
        self.write_entry("another-change", "fixed", "Fix another workflow")
        subprocess.run(["git", "add", "Documentation/ReleaseNotes"], cwd=self.repository, check=True)
        rewritten = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(rewritten.returncode, 0)
        self.assertIn("must not change or delete an existing entry file", rewritten.stderr)

    def test_entry_files_follow_the_document_in_the_order_history_added_them(self) -> None:
        self.write_catalog({"existing-change": {"category": "fixed", "message": "Keep existing behavior reliable"}})
        self.commit_catalog()
        # Added later but named first: history, not the name, orders it.
        self.commit(self.write_entry("zeta-change", "new", "Add the first workflow"))
        self.commit(self.write_entry("alpha-change", "fixed", "Fix the second workflow"))
        # Not committed yet: after every committed entry, by name.
        self.write_entry("beta-change", "improved", "Improve a pending workflow")

        result = self.run_catalog_check("--write-assembled")
        self.assertEqual(result.returncode, 0, result.stderr)
        assembled = json.loads((self.repository / "Documentation" / "ReleaseNotes.json").read_text())
        self.assertEqual(
            list(assembled["entries"]),
            ["existing-change", "zeta-change", "alpha-change", "beta-change"],
        )
        # A release checkout reads its stamped catalog as the same catalog.
        again = self.run_catalog_check()
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIn("Validated 4 release-note entries", again.stdout)

        # A file reusing an id the catalog already holds with other text is a duplicate.
        self.write_entry("existing-change", "new", "Reuse an existing id")
        duplicate = self.run_catalog_check()
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn("already used", duplicate.stderr)


    def test_a_merged_entry_file_is_never_deleted(self) -> None:
        self.write_catalog({"existing-change": {"category": "fixed", "message": "Keep existing behavior reliable"}})
        self.commit_catalog()
        self.commit(self.write_entry("merged-change", "new", "Add a workflow"))
        (self.repository / "Documentation" / "ReleaseNotes" / "merged-change.json").unlink()
        self.write_entry("next-change", "fixed", "Fix another workflow")
        subprocess.run(["git", "add", "-A", "Documentation/ReleaseNotes"], cwd=self.repository, check=True)

        result = self.run_catalog_check("--require-staged-entry")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must not change or delete an existing entry file", result.stderr)

    def test_merged_and_directly_committed_entries_keep_first_parent_order(self) -> None:
        self.write_catalog({"existing-change": {"category": "fixed", "message": "Keep existing behavior reliable"}})
        self.commit_catalog()
        subprocess.run(["git", "switch", "-q", "-c", "topic"], cwd=self.repository, check=True)
        self.commit(self.write_entry("from-topic", "new", "Arrive through a merge"))
        subprocess.run(["git", "switch", "-q", "main"], cwd=self.repository, check=True)
        self.commit(self.write_entry("direct-first", "fixed", "Arrive directly first"))
        subprocess.run(["git", "merge", "-q", "--no-ff", "-m", "merge topic", "topic"], cwd=self.repository, check=True)
        self.commit(self.write_entry("direct-last", "improved", "Arrive directly last"))

        result = self.run_catalog_check("--write-assembled")

        self.assertEqual(result.returncode, 0, result.stderr)
        assembled = json.loads((self.repository / "Documentation" / "ReleaseNotes.json").read_text())
        self.assertEqual(list(assembled["entries"]), ["existing-change", "direct-first", "from-topic", "direct-last"])


if __name__ == "__main__":
    unittest.main()
