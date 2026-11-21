#!/usr/bin/env python3
"""Contract coverage for Crest's per-version release notes."""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG_SCRIPT = REPOSITORY_ROOT / "Scripts" / "release_note_catalog.py"


class ReleaseNoteCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository = pathlib.Path(self.temporary_directory.name)
        for arguments in (
            ["init", "--initial-branch=main"],
            ["config", "user.name", "Crest Tests"],
            ["config", "user.email", "tests@crestbrowser.com"],
        ):
            self.git(*arguments)
        self.write_marketing_version("0.1.1")
        self.write_version_notes("0.1.1", [self.entry("existing-change", "fixed", "Keep existing behavior reliable")])
        self.git("add", ".")
        self.git("commit", "-m", "baseline")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def git(self, *arguments: str) -> None:
        subprocess.run(["git", *arguments], cwd=self.repository, check=True, capture_output=True)

    def entry(self, identifier: str, category: str, message: str, **fields: object) -> dict[str, object]:
        return {"id": identifier, "category": category, "message": message, **fields}

    def write_marketing_version(self, version: str) -> None:
        path = self.repository / "Config" / "Version.xcconfig"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"MARKETING_VERSION = {version}\n")

    def write_version_notes(
        self,
        version: str,
        entries: list[dict[str, object]],
        release: dict[str, object] | None = None,
        line: str | None = None,
    ) -> pathlib.Path:
        line = line or version.rsplit(".", 1)[0]
        path = self.repository / "Documentation" / "ReleaseNotes" / line / f"{version}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        document: dict[str, object] = {"entries": entries}
        if release is not None:
            document = {"release": release, **document}
        path.write_text(json.dumps(document, indent=2) + "\n")
        return path

    def run_catalog_check(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(CATALOG_SCRIPT), "--repository-root", str(self.repository), *arguments],
            cwd=self.repository,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_version_files_must_be_well_formed_and_named_for_their_version(self) -> None:
        valid = self.run_catalog_check()
        self.assertEqual(valid.returncode, 0, valid.stderr)

        invalid_cases = {
            "wrong line folder": lambda: self.write_version_notes(
                "0.1.1", [self.entry("moved", "fixed", "Describe a fix")], line="0.2"
            ),
            "invalid id": lambda: self.write_version_notes(
                "0.1.1", [self.entry("Bad ID", "new", "Describe a feature")]
            ),
            "unknown category": lambda: self.write_version_notes(
                "0.1.1", [self.entry("valid-id", "changed", "Describe a change")]
            ),
            "unknown field": lambda: self.write_version_notes(
                "0.1.1", [self.entry("valid-id", "fixed", "Describe a fix", commit="abc")]
            ),
            "every platform listed": lambda: self.write_version_notes(
                "0.1.1", [self.entry("valid-id", "fixed", "Describe a fix", platforms=["mac", "ios"])]
            ),
            "duplicate id across versions": lambda: self.write_version_notes(
                "0.1.0", [self.entry("existing-change", "fixed", "Describe it again")]
            ),
            "newer than the marketing version": lambda: self.write_version_notes(
                "0.1.2", [self.entry("future-change", "fixed", "Describe a future fix")]
            ),
            "empty release write-up": lambda: self.write_version_notes(
                "0.1.1", [self.entry("existing-change", "fixed", "Keep existing behavior reliable")], release={}
            ),
        }
        notes = self.repository / "Documentation" / "ReleaseNotes"
        for name, write in invalid_cases.items():
            with self.subTest(name):
                shutil.rmtree(notes)
                self.write_version_notes(
                    "0.1.1", [self.entry("existing-change", "fixed", "Keep existing behavior reliable")]
                )
                write()
                result = self.run_catalog_check()
                self.assertNotEqual(result.returncode, 0, name)

    def test_staged_contract_puts_new_entries_in_the_staged_versions_file(self) -> None:
        self.write_marketing_version("0.1.2")
        self.git("add", "Config")

        missing = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn(
            "add at least one new release-note entry to Documentation/ReleaseNotes/0.1/0.1.2.json",
            missing.stderr,
        )

        self.write_version_notes(
            "0.1.1",
            [
                self.entry("existing-change", "fixed", "Keep existing behavior reliable"),
                self.entry("new-change", "new", "Add a new workflow"),
            ],
        )
        self.git("add", "Documentation")
        misplaced = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(misplaced.returncode, 0)
        self.assertIn("belong in Documentation/ReleaseNotes/0.1/0.1.2.json", misplaced.stderr)

        self.write_version_notes(
            "0.1.1", [self.entry("existing-change", "fixed", "Keep existing behavior reliable")]
        )
        self.write_version_notes("0.1.2", [self.entry("new-change", "new", "Add a new workflow")])
        self.git("add", "Documentation")
        added = self.run_catalog_check("--require-staged-entry")
        self.assertEqual(added.returncode, 0, added.stderr)
        self.assertIn("new-change", added.stdout)

    def test_staged_contract_keeps_existing_entries_but_lets_write_ups_change(self) -> None:
        self.write_marketing_version("0.1.2")
        self.write_version_notes("0.1.2", [self.entry("new-change", "new", "Add a new workflow")])
        self.write_version_notes(
            "0.1.1",
            [self.entry("existing-change", "fixed", "Keep existing behavior reliable")],
            release={"summary": "Crest 0.1.1 keeps things reliable.", "fixed": ["Existing behavior is reliable."]},
        )
        self.git("add", ".")
        with_write_up = self.run_catalog_check("--require-staged-entry")
        self.assertEqual(with_write_up.returncode, 0, with_write_up.stderr)

        self.write_version_notes(
            "0.1.1", [self.entry("existing-change", "improved", "Rewrite existing release copy")]
        )
        self.git("add", ".")
        rewritten = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(rewritten.returncode, 0)
        self.assertIn("must not change or move release-note entries", rewritten.stderr)

        (self.repository / "Documentation" / "ReleaseNotes" / "0.1" / "0.1.1.json").unlink()
        self.git("add", ".")
        deleted = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(deleted.returncode, 0)
        self.assertIn("must not delete release-note entries", deleted.stderr)


if __name__ == "__main__":
    unittest.main()
