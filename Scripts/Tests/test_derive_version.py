#!/usr/bin/env python3
"""Contract coverage for the version Crest derives from its history."""

from __future__ import annotations

import pathlib
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
DERIVE_SCRIPT = REPOSITORY_ROOT / "Scripts" / "derive-version.py"


class DeriveVersionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository = pathlib.Path(self.temporary_directory.name) / "crest"
        self.repository.mkdir()
        self.git("init", "-q", "--initial-branch=main")
        self.git("config", "user.name", "Crest Tests")
        self.git("config", "user.email", "tests@crestbrowser.com")
        self.set_base("0.8.10", "set the release line")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def git(self, *arguments: str) -> str:
        return subprocess.run(
            ["git", *arguments], cwd=self.repository, check=True, capture_output=True, text=True
        ).stdout.strip()

    def set_base(self, version: str, message: str) -> None:
        path = self.repository / "Config" / "Version.xcconfig"
        path.parent.mkdir(exist_ok=True)
        path.write_text(f"MARKETING_VERSION = {version}\n")
        self.git("add", "Config/Version.xcconfig")
        self.git("commit", "-q", "-m", message)

    def change(self, name: str) -> None:
        (self.repository / name).write_text(name)
        self.git("add", name)
        self.git("commit", "-q", "-m", name)

    def derive(self, *arguments: str, repository: pathlib.Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(DERIVE_SCRIPT), *arguments, "--repository-root", str(repository or self.repository)],
            check=False, capture_output=True, text=True,
        )

    def version(self) -> str:
        result = self.derive("version")
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_each_first_parent_commit_after_the_base_raises_the_patch(self) -> None:
        self.assertEqual(self.version(), "0.8.10")
        self.change("one")
        self.change("two")
        self.assertEqual(self.version(), "0.8.12")
        self.assertEqual(self.derive("tag").stdout.strip(), "v0.8.12")

    def test_a_merge_counts_once_however_many_commits_it_brings(self) -> None:
        self.git("switch", "-q", "-c", "topic")
        self.change("topic-one")
        self.change("topic-two")
        self.change("topic-three")
        self.git("switch", "-q", "main")
        self.change("main-change")
        self.git("merge", "-q", "--no-ff", "-m", "merge topic", "topic")
        self.assertEqual(self.version(), "0.8.12")

    def test_a_new_release_line_starts_again_from_its_base(self) -> None:
        self.change("one")
        self.set_base("0.9.0", "start 0.9")
        self.assertEqual(self.version(), "0.9.0")
        self.change("two")
        self.assertEqual(self.version(), "0.9.1")

    def test_a_shallow_checkout_is_refused_rather_than_misnumbered(self) -> None:
        self.change("one")
        self.change("two")
        shallow = self.repository.parent / "shallow"
        subprocess.run(
            ["git", "clone", "-q", "--depth", "1", f"file://{self.repository}", str(shallow)],
            check=True, capture_output=True,
        )
        result = self.derive("version", repository=shallow)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("full history", result.stderr)

    def test_stamp_writes_the_derived_version_into_this_checkout(self) -> None:
        self.change("one")
        result = self.derive("stamp")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.repository / "Config" / "Version.xcconfig").read_text(), "MARKETING_VERSION = 0.8.11\n"
        )


if __name__ == "__main__":
    unittest.main()
