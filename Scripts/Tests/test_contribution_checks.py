#!/usr/bin/env python3
"""Durable failure modes of the pull request contribution checks."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHECK_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-contribution.py"
TEMPLATE = REPOSITORY_ROOT / ".github" / "PULL_REQUEST_TEMPLATE.md"


def load_check_module():
    spec = importlib.util.spec_from_file_location("crest_contribution", CHECK_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Scripts/check-contribution.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def commit(message: str, parents: int = 1) -> dict:
    return {
        "sha": "0123456789abcdef",
        "parents": [{"sha": "p"}] * parents,
        "commit": {"message": message},
    }


class ContributionCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.check = load_check_module()
        cls.template = TEMPLATE.read_text(encoding="utf-8")

    def test_ai_use_without_the_skill_is_rejected(self) -> None:
        body = self.template.replace(f"- [ ] {self.check.AI_USED_MARKER}", f"- [x] {self.check.AI_USED_MARKER}")
        self.assertEqual(len(self.check.ai_declaration_problems(body)), 1)

        body = body.replace("- [ ] I ran the `crest-contribution`", "- [x] I ran the `crest-contribution`")
        self.assertEqual(self.check.ai_declaration_problems(body), [])

    def test_sign_off_is_required_except_for_merges(self) -> None:
        signed = commit("fix: a thing\n\nSigned-off-by: Person <person@example.com>")
        unsigned = commit("fix: a thing")
        empty_trailer = commit("fix: a thing\n\nSigned-off-by:")
        merge = commit("Merge branch 'main'", parents=2)

        self.assertEqual(self.check.sign_off_problems([signed, merge]), [])
        self.assertEqual(len(self.check.sign_off_problems([signed, unsigned, empty_trailer])), 2)

    def test_only_the_pull_request_author_can_exempt_a_pull_request(self) -> None:
        self.assertTrue(self.check.exempt_from_sign_off("dependabot[bot]", set()))
        self.assertTrue(self.check.exempt_from_sign_off("owner", {"owner"}))
        self.assertFalse(self.check.exempt_from_sign_off("person", {"owner"}))


class ReleaseFileCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.check = load_check_module()

    def test_the_version_file_only_moves_to_a_later_release_line(self) -> None:
        problems = self.check.release_file_problems
        version = "Config/Version.xcconfig"
        self.assertEqual(problems([("A", "Documentation/ReleaseNotes/new-change.json")], None, None), [])
        self.assertTrue(problems([("M", version)], "MARKETING_VERSION = 0.8.114\n", "MARKETING_VERSION = 0.8.115\n"))
        self.assertTrue(problems([("M", version)], "MARKETING_VERSION = 0.8.114\n", "MARKETING_VERSION = 0.7.0\n"))
        self.assertEqual(problems([("M", version)], "MARKETING_VERSION = 0.8.114\n", "MARKETING_VERSION = 0.9.0\n"), [])
        self.assertEqual(problems([("M", version)], "MARKETING_VERSION = 0.8.114\n", "MARKETING_VERSION = 1.0.0\n"), [])

    def test_the_catalog_document_is_frozen_and_merged_entry_files_are_kept(self) -> None:
        problems = self.check.release_file_problems
        self.assertTrue(problems([("M", "Documentation/ReleaseNotes.json")], None, None))
        self.assertTrue(problems([("M", "Documentation/ReleaseNotes/old-change.json")], None, None))
        self.assertTrue(problems([("D", "Documentation/ReleaseNotes/old-change.json")], None, None))

    def test_the_command_reads_the_pull_request_against_its_base(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)

            def git(*arguments: str) -> str:
                return subprocess.run(["git", "-C", str(repository), *arguments], check=True,
                                      capture_output=True, text=True).stdout.strip()

            git("init", "-q", "--initial-branch=main")
            git("config", "user.name", "Crest Tests")
            git("config", "user.email", "tests@crestbrowser.com")
            (repository / "Config").mkdir()
            (repository / "Config" / "Version.xcconfig").write_text("MARKETING_VERSION = 0.8.114\n")
            git("add", "-A")
            git("commit", "-q", "-m", "base")
            base = git("rev-parse", "HEAD")
            event = repository.parent / f"{repository.name}-event.json"
            event.write_text(json.dumps({"pull_request": {"created_at": "2026-10-30T00:00:00Z", "base": {"sha": base}}}))

            def run() -> subprocess.CompletedProcess[str]:
                return subprocess.run(["python3", str(CHECK_SCRIPT), "release-files", "--event", str(event)],
                                      cwd=repository, check=False, capture_output=True, text=True)

            (repository / "Documentation" / "ReleaseNotes").mkdir(parents=True)
            (repository / "Documentation" / "ReleaseNotes" / "new-change.json").write_text("{}\n")
            git("add", "-A")
            git("commit", "-q", "-m", "entry")
            self.assertEqual(run().returncode, 0)

            (repository / "Config" / "Version.xcconfig").write_text("MARKETING_VERSION = 0.8.115\n")
            git("commit", "-q", "-am", "old-style bump")
            bumped = run()
            self.assertNotEqual(bumped.returncode, 0)
            self.assertIn("patch versions are derived from history", bumped.stderr)
            event.unlink()


if __name__ == "__main__":
    unittest.main()
