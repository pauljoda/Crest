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

    def write_catalog(self, entries: dict[str, dict[str, str]]) -> None:
        catalog = self.repository / "Documentation" / "ReleaseNotes.json"
        catalog.parent.mkdir(parents=True, exist_ok=True)
        catalog.write_text(
            json.dumps(
                {"schemaVersion": 1, "entries": entries},
                indent=2,
            )
            + "\n"
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

    def test_valid_catalog_accepts_all_supported_categories(self) -> None:
        self.write_catalog(
            {
                category: {
                    "category": category,
                    "message": f"Describe the {category} change clearly",
                }
                for category in ("new", "improved", "fixed", "internal")
            }
        )

        result = self.run_catalog_check()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Validated 4 release-note entries", result.stdout)

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

    def test_staged_contract_requires_a_new_entry_and_preserves_existing_ids(self) -> None:
        entries = {
            "existing-change": {
                "category": "fixed",
                "message": "Keep existing behavior reliable",
            }
        }
        self.write_catalog(entries)
        self.commit_catalog()

        no_change = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(no_change.returncode, 0)
        self.assertIn("stage at least one new release-note entry", no_change.stderr)

        entries["new-change"] = {
            "category": "improved",
            "message": "Make the current workflow easier to understand",
        }
        self.write_catalog(entries)
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        added = self.run_catalog_check("--require-staged-entry")
        self.assertEqual(added.returncode, 0, added.stderr)
        self.assertIn("new-change", added.stdout)

        entries.pop("existing-change")
        self.write_catalog(entries)
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        deleted = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(deleted.returncode, 0)
        self.assertIn("must not delete release-note entries", deleted.stderr)

    def test_staged_contract_appends_new_ids_after_the_existing_catalog(self) -> None:
        existing_entries = {
            "existing-change": {
                "category": "fixed",
                "message": "Keep existing behavior reliable",
            }
        }
        self.write_catalog(existing_entries)
        self.commit_catalog()

        inserted_entries = {
            "new-change": {
                "category": "new",
                "message": "Add a new workflow",
            },
            **existing_entries,
        }
        self.write_catalog(inserted_entries)
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        result = self.run_catalog_check("--require-staged-entry")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("append new release-note entries", result.stderr)


if __name__ == "__main__":
    unittest.main()
