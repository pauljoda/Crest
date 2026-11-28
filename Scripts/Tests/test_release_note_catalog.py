#!/usr/bin/env python3
"""Contract coverage for Crest's release notes: version files, fragments and the pull request rules."""

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
        (self.repository / "CrestShared").mkdir()
        (self.repository / "CrestShared" / "App.swift").write_text("// Crest\n")
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

    def notes_path(self, relative_path: str) -> pathlib.Path:
        return self.repository / "Documentation" / "ReleaseNotes" / relative_path

    def write_document(self, relative_path: str, document: dict[str, object]) -> pathlib.Path:
        path = self.notes_path(relative_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(document, indent=2) + "\n")
        return path

    def write_version_notes(
        self,
        version: str,
        entries: list[dict[str, object]],
        release: dict[str, object] | None = None,
        line: str | None = None,
    ) -> pathlib.Path:
        line = line or version.rsplit(".", 1)[0]
        document: dict[str, object] = {"entries": entries} if entries else {}
        if release is not None:
            document = {"release": release, **document}
        return self.write_document(f"{line}/{version}.json", document)

    def write_fragment(self, slug: str, entries: list[dict[str, object]]) -> pathlib.Path:
        return self.write_document(f"changes/{slug}.json", {"entries": entries})

    def run_catalog_check(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(CATALOG_SCRIPT), "--repository-root", str(self.repository), *arguments],
            cwd=self.repository,
            check=False,
            capture_output=True,
            text=True,
        )

    def check_pull_request(self) -> subprocess.CompletedProcess[str]:
        """Commit the working tree on the pull request's branch and check it against main."""
        self.git("add", "-A")
        self.git("commit", "--allow-empty", "-m", "pull request")
        return self.run_catalog_check("--pull-request", "main")

    def start_pull_request(self) -> None:
        self.git("switch", "-C", "pull-request", "main")

    def test_notes_files_must_be_well_formed_and_where_they_belong(self) -> None:
        self.write_fragment("pending-fix", [self.entry("pending-fix", "fixed", "Describe a pending fix")])
        valid = self.run_catalog_check()
        self.assertEqual(valid.returncode, 0, valid.stderr)

        invalid_cases = {
            "wrong line folder": lambda: self.write_version_notes(
                "0.1.1", [self.entry("moved", "fixed", "Describe a fix")], line="0.2"
            ),
            "invalid id": lambda: self.write_fragment("bad-id", [self.entry("Bad ID", "new", "Describe a feature")]),
            "unknown category": lambda: self.write_fragment(
                "a-change", [self.entry("valid-id", "changed", "Describe a change")]
            ),
            "unknown field": lambda: self.write_fragment(
                "a-fix", [self.entry("valid-id", "fixed", "Describe a fix", commit="abc")]
            ),
            "every platform listed": lambda: self.write_fragment(
                "a-fix", [self.entry("valid-id", "fixed", "Describe a fix", platforms=["mac", "ios", "windows", "linux"])]
            ),
            "duplicate id across files": lambda: self.write_fragment(
                "again", [self.entry("existing-change", "fixed", "Describe it again")]
            ),
            "entries in a version past the anchor": lambda: self.write_version_notes(
                "0.1.2", [self.entry("future-change", "fixed", "Describe a future fix")]
            ),
            "empty release write-up": lambda: self.write_version_notes(
                "0.1.1", [self.entry("existing-change", "fixed", "Keep existing behavior reliable")], release={}
            ),
            "fragment with a write-up": lambda: self.write_document(
                "changes/a-fix.json", {"release": {"summary": "A summary."}, "entries": []}
            ),
            "fragment without entries": lambda: self.write_fragment("a-fix", []),
            "fragment slug": lambda: self.write_fragment("A Fix", [self.entry("a-fix", "fixed", "Describe a fix")]),
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

        with self.subTest("a Stable write-up past the anchor"):
            shutil.rmtree(notes)
            self.write_version_notes("0.1.1", [self.entry("existing-change", "fixed", "Keep existing behavior reliable")])
            self.write_version_notes("0.1.4", [], release={"summary": "Crest 0.1.4 keeps things reliable."})
            self.assertEqual(self.run_catalog_check().returncode, 0)

    def test_an_app_change_adds_its_notes_as_a_new_fragment(self) -> None:
        self.start_pull_request()
        (self.repository / "CrestShared" / "App.swift").write_text("// Crest, fixed\n")
        missing = self.check_pull_request()
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("add a fragment", missing.stderr)

        self.write_fragment(
            "reliable-tabs",
            [self.entry("reliable-tabs", "fixed", "Keep tabs reliable"), self.entry("faster-tabs", "improved", "Open tabs faster")],
        )
        added = self.check_pull_request()
        self.assertEqual(added.returncode, 0, added.stderr)
        self.assertIn("reliable-tabs, faster-tabs", added.stdout)

        self.start_pull_request()
        (self.repository / "README.md").write_text("Crest\n")
        documentation = self.check_pull_request()
        self.assertEqual(documentation.returncode, 0, documentation.stderr)

    def test_a_pull_request_keeps_the_version_unless_it_opens_a_line(self) -> None:
        self.start_pull_request()
        self.write_fragment("reliable-tabs", [self.entry("reliable-tabs", "fixed", "Keep tabs reliable")])
        self.write_marketing_version("0.1.2")
        bumped = self.check_pull_request()
        self.assertNotEqual(bumped.returncode, 0)
        self.assertIn("changes only to open a new release line", bumped.stderr)

        self.write_marketing_version("0.2.0")
        opened = self.check_pull_request()
        self.assertEqual(opened.returncode, 0, opened.stderr)

    def test_entries_on_main_never_change_but_write_ups_do(self) -> None:
        merged = [
            self.entry("merged-fix", "fixed", "Keep downloads reliable"),
            self.entry("merged-polish", "improved", "Show downloads sooner"),
        ]
        self.write_fragment("merged-fix", merged)
        self.git("add", ".")
        self.git("commit", "-m", "merged pull request")

        cases = {
            "rewritten entry": (
                lambda: self.write_version_notes("0.1.1", [self.entry("existing-change", "improved", "Rewrite it")]),
                "never change, move or go away",
            ),
            "deleted version file": (
                lambda: self.notes_path("0.1/0.1.1.json").unlink(),
                "never change, move or go away",
            ),
            "deleted fragment": (
                lambda: self.notes_path("changes/merged-fix.json").unlink(),
                "never change, move or go away",
            ),
            "reordered fragment": (
                lambda: self.write_fragment("merged-fix", list(reversed(merged))),
                "never change, move or go away",
            ),
            "entry moved to a fragment": (
                lambda: (
                    self.write_version_notes("0.1.1", [], release={"summary": "Crest 0.1.1."}),
                    self.write_fragment(
                        "moved", [self.entry("existing-change", "fixed", "Keep existing behavior reliable")]
                    ),
                ),
                "never change, move or go away",
            ),
            "new entry in a version file": (
                lambda: self.write_version_notes(
                    "0.1.1",
                    [
                        self.entry("existing-change", "fixed", "Keep existing behavior reliable"),
                        self.entry("late-change", "fixed", "Describe a late fix"),
                    ],
                ),
                "new entries go in a new fragment",
            ),
            "new entry in a merged fragment": (
                lambda: self.write_fragment(
                    "merged-fix", [*merged, self.entry("late-change", "fixed", "Describe a late fix")]
                ),
                "new entries go in a new fragment",
            ),
            "new version file with entries": (
                lambda: self.write_version_notes("0.1.2", [self.entry("late-change", "fixed", "Describe a late fix")]),
                "new entries go in a new fragment",
            ),
        }
        for name, (change, message) in cases.items():
            with self.subTest(name):
                self.start_pull_request()
                change()
                result = self.check_pull_request()
                self.assertNotEqual(result.returncode, 0, name)
                self.assertIn(message, result.stderr)

        with self.subTest("write-ups"):
            self.start_pull_request()
            self.write_version_notes(
                "0.1.1",
                [self.entry("existing-change", "fixed", "Keep existing behavior reliable")],
                release={"summary": "Crest 0.1.1 keeps things reliable.", "fixed": ["Existing behavior is reliable."]},
            )
            self.write_version_notes("0.1.3", [], release={"summary": "Crest 0.1.3 keeps downloads reliable."})
            result = self.check_pull_request()
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
