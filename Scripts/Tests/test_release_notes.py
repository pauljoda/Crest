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

    def test_notes_group_user_facing_changes_and_hide_internal_commit_noise(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            previous_commit = self.commit(repository, "Initial release", "Already published.")
            first_commit = self.commit(
                repository,
                "feat(browser): add split view",
                "Implementation detail that does not belong in release notes.",
            )
            second_commit = self.commit(repository, "perf: speed up tab switching")
            third_commit = self.commit(repository, "Polish the onboarding flow (#42)")
            self.commit(repository, "Fix disappearing tabs")
            self.commit(repository, "chore(release): prepare 0.4.0")
            self.commit(repository, "fix(ci): restore hosted validation")
            current_commit = self.commit(
                repository,
                "fix: restore toolbar spacing (APP-249)",
            )

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
                    current_commit,
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
            self.assertIn("## Highlights", notes)
            self.assertIn("### New", notes)
            self.assertIn("- Add split view", notes)
            self.assertIn("### Improved", notes)
            self.assertIn("- Speed up tab switching", notes)
            self.assertIn("- Polish the onboarding flow", notes)
            self.assertIn("### Fixed", notes)
            self.assertIn("- Fix disappearing tabs", notes)
            self.assertIn("- Restore toolbar spacing", notes)
            self.assertLess(notes.index("### Fixed"), notes.index("Fix disappearing tabs"))
            self.assertIn(
                "[Download the installer]"
                "(https://github.com/pauljoda/Crest/releases/download/development/"
                "Installer-Crest-0.4.0-development-test-arm64.dmg)",
                notes,
            )
            self.assertIn("Development builds contain the newest changes", notes)
            self.assertNotIn("Initial release", notes)
            self.assertNotIn("Implementation detail", notes)
            self.assertNotIn("prepare 0.4.0", notes)
            self.assertNotIn("hosted validation", notes)
            self.assertNotIn("feat(browser)", notes)
            self.assertNotIn("(#42)", notes)
            self.assertNotIn("(APP-249)", notes)
            self.assertIn(
                "[View all changes]"
                f"(https://github.com/pauljoda/Crest/compare/{previous_commit}...{current_commit})",
                notes,
            )
            self.assertLess(notes.index("Add split view"), notes.index("Speed up tab switching"))
            self.assertLess(notes.index("Speed up tab switching"), notes.index("Polish the onboarding flow"))
            self.assertNotIn(first_commit[:7], notes)
            self.assertNotIn(second_commit[:7], notes)
            self.assertNotIn(third_commit[:7], notes)

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
            self.assertIn("- First nightly build", notes)
            self.assertNotIn("The current change.", notes)
            self.assertIn(
                f"[View source](https://github.com/pauljoda/Crest/commit/{current_commit})",
                notes,
            )

    def test_notes_limit_highlights_and_link_to_the_complete_comparison(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            previous_commit = self.commit(repository, "Initial release")
            for index in range(14):
                current_commit = self.commit(repository, f"fix: restore behavior {index}")

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
                    "--previous-ref",
                    previous_commit,
                    "--asset-name",
                    "Installer-Crest-0.4.0-nightly-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertNotIn("- Restore behavior 0\n", notes)
            self.assertNotIn("- Restore behavior 1\n", notes)
            self.assertIn("- Restore behavior 2\n", notes)
            self.assertIn("- Restore behavior 13\n", notes)
            self.assertEqual(notes.count("- Restore behavior"), 12)
            self.assertIn("Showing the 12 most recent highlights from 14 user-facing changes.", notes)
            self.assertIn(
                "[View all changes]"
                f"(https://github.com/pauljoda/Crest/compare/{previous_commit}...{current_commit})",
                notes,
            )

    def test_notes_omit_merge_commits_but_keep_their_user_facing_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            previous_commit = self.commit(repository, "Initial release")
            self.run_git(repository, "checkout", "-b", "feature")
            self.run_git(repository, "commit", "--allow-empty", "-m", "feat: add profiles")
            self.run_git(repository, "checkout", "main")
            self.commit(repository, "fix: restore navigation")
            self.run_git(repository, "merge", "--no-ff", "feature", "-m", "Merge feature")
            current_commit = self.run_git(repository, "rev-parse", "HEAD")

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
                    current_commit,
                    "--previous-ref",
                    previous_commit,
                    "--asset-name",
                    "Installer-Crest-development-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertIn("- Add profiles", notes)
            self.assertIn("- Restore navigation", notes)
            self.assertNotIn("Merge feature", notes)


if __name__ == "__main__":
    unittest.main()
