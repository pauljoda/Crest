#!/usr/bin/env python3
"""Behavioral coverage for Crest's commit-based release notes."""

from __future__ import annotations

import pathlib
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
RELEASE_NOTES_SCRIPT = REPOSITORY_ROOT / "Scripts" / "generate-release-notes.py"


class ReleaseNotesTests(unittest.TestCase):
    def run_git(self, repository: pathlib.Path, *arguments: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(repository), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def commit(
        self,
        repository: pathlib.Path,
        subject: str,
        body: str | None = None,
    ) -> str:
        tracked_file = repository / "tracked.txt"
        previous = tracked_file.read_text() if tracked_file.exists() else ""
        tracked_file.write_text(f"{previous}{subject}\n")
        self.run_git(repository, "add", tracked_file.name)
        arguments = ["commit", "-m", subject]
        if body is not None:
            arguments.extend(["-m", body])
        self.run_git(repository, *arguments)
        return self.run_git(repository, "rev-parse", "HEAD")

    def test_notes_list_each_new_commit_title_and_description_in_order(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            previous_commit = self.commit(repository, "Initial release", "Already published.")
            first_commit = self.commit(
                repository,
                "Add split view",
                "Adds side-by-side browsing.\n\nKeeps both tabs live.",
            )
            second_commit = self.commit(repository, "Fix toolbar spacing")

            result = subprocess.run(
                [
                    "python3",
                    str(RELEASE_NOTES_SCRIPT),
                    "--repository-root",
                    str(repository),
                    "--repository",
                    "pauljoda/Crest",
                    "--channel",
                    "development",
                    "--current-ref",
                    second_commit,
                    "--previous-ref",
                    previous_commit,
                    "--asset-name",
                    "Installer-Crest-0.4.0-development-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertIn("# Crest development build", notes)
            self.assertIn(
                "[Download Crest for Mac (Apple silicon)]"
                "(https://github.com/pauljoda/Crest/releases/download/development/"
                "Installer-Crest-0.4.0-development-test-arm64.dmg)",
                notes,
            )
            self.assertIn("Development builds are signed and notarized", notes)
            self.assertNotIn("Initial release", notes)
            self.assertLess(notes.index("Add split view"), notes.index("Fix toolbar spacing"))
            self.assertIn("Adds side-by-side browsing.\n\nKeeps both tabs live.", notes)
            self.assertIn(
                f"[View commit `{first_commit[:7]}`](https://github.com/pauljoda/Crest/commit/{first_commit})",
                notes,
            )
            self.assertIn(
                f"[View commit `{second_commit[:7]}`](https://github.com/pauljoda/Crest/commit/{second_commit})",
                notes,
            )

    def test_first_channel_build_describes_only_the_current_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            self.commit(repository, "Repository history")
            current_commit = self.commit(repository, "First nightly build", "The current change.")

            result = subprocess.run(
                [
                    "python3",
                    str(RELEASE_NOTES_SCRIPT),
                    "--repository-root",
                    str(repository),
                    "--repository",
                    "pauljoda/Crest",
                    "--channel",
                    "nightly",
                    "--current-ref",
                    current_commit,
                    "--asset-name",
                    "Installer-Crest-0.4.0-nightly-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertNotIn("Repository history", notes)
            self.assertIn("First nightly build", notes)
            self.assertIn("The current change.", notes)


if __name__ == "__main__":
    unittest.main()
