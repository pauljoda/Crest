#!/usr/bin/env python3
"""Behavioral coverage for the GitHub and Sparkle notes of a Mac release."""

from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
RELEASE_NOTES_SCRIPT = REPOSITORY_ROOT / "Scripts" / "generate-release-notes.py"


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.repository = pathlib.Path(temporary.name)
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "Crest Tests")
        self.git("config", "user.email", "tests@crestbrowser.com")

    def git(self, *arguments: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(self.repository), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def commit_version(
        self,
        version: str,
        entries: list[dict[str, object]],
        release: dict[str, object] | None = None,
    ) -> str:
        (self.repository / "Config").mkdir(exist_ok=True)
        (self.repository / "Config" / "Version.xcconfig").write_text(f"MARKETING_VERSION = {version}\n")
        path = self.repository / "Documentation" / "ReleaseNotes" / version.rsplit(".", 1)[0] / f"{version}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        document: dict[str, object] = {"entries": entries}
        if release is not None:
            document = {"release": release, **document}
        path.write_text(json.dumps(document, indent=2) + "\n")
        self.git("add", ".")
        self.git("commit", "-m", f"chore: private subject for {version}")
        return self.git("rev-parse", "HEAD")

    def generate_notes(
        self,
        current_commit: str,
        previous_entry: str,
        previous_commit: str | None = None,
        channel: str = "nightly",
        release_tag: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        arguments = [
            "python3",
            str(RELEASE_NOTES_SCRIPT),
            "--repository-root",
            str(self.repository),
            "--repository",
            "crest-browser/Crest",
            "--channel",
            channel,
            "--current-ref",
            current_commit,
            "--previous-entry",
            previous_entry,
            "--asset-name",
            "Installer-Crest-nightly-test-arm64.dmg",
        ]
        if previous_commit is not None:
            arguments.extend(["--previous-ref", previous_commit])
        if release_tag is not None:
            arguments.extend(["--release-tag", release_tag])
        return subprocess.run(arguments, check=False, capture_output=True, text=True)

    def test_channel_links_and_installer_use_the_distinct_release_tag(self) -> None:
        previous = self.commit_version("0.5.24", [{"id": "boundary", "category": "internal", "message": "Boundary"}])
        current = self.commit_version("0.5.25", [{"id": "history", "category": "fixed", "message": "Keep release history"}])
        for channel in ("stable", "nightly", "development"):
            with self.subTest(channel=channel):
                tag = "v0.5.25" if channel == "stable" else f"{channel}-0.5.25-2026-09-03-1061-r61.1"
                result = self.generate_notes(current, "boundary", previous, channel=channel, release_tag=tag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"/releases/download/{tag}/Installer-", result.stdout)
                self.assertIn(f"[Release notes](https://crestbrowser.com/releases/mac/{channel}/0.5.25/)", result.stdout)
                query = (
                    "prerelease%3Afalse" if channel == "stable"
                    else f"prerelease%3Atrue+%22{channel.title()}+builds%22"
                )
                self.assertIn(
                    f"[Browse {channel.title()} releases](https://github.com/crest-browser/Crest/releases?q={query})",
                    result.stdout,
                )

    def test_cursor_selects_public_mac_entries_after_its_channel_boundary(self) -> None:
        self.commit_version(
            "0.5.24",
            [
                {"id": "stable-boundary", "category": "internal", "message": "Record the stable boundary"},
                {"id": "existing-change", "category": "fixed", "message": "Keep existing behavior reliable"},
                {"id": "development-change", "category": "new", "message": "Open links in a compact preview"},
                {"id": "nightly-boundary", "category": "internal", "message": "Record the nightly boundary"},
            ],
        )
        current = self.commit_version(
            "0.5.25",
            [
                {"id": "profiles", "category": "new", "message": "Create separate browsing profiles"},
                {"id": "tab-switching", "category": "improved", "message": "Switch between large tab collections more smoothly"},
                {"id": "navigation", "category": "fixed", "message": "Keep navigation controls in sync with the active page"},
                {"id": "phone-only", "category": "fixed", "message": "Keep the iPhone toolbar in place", "platforms": ["ios"]},
                {"id": "release-plumbing", "category": "internal", "message": "Adopt the structured release notes"},
            ],
        )

        nightly = self.generate_notes(current, "nightly-boundary")
        stable = self.generate_notes(current, "stable-boundary")

        self.assertEqual(nightly.returncode, 0, nightly.stderr)
        for heading, message in (
            ("### New", "- Create separate browsing profiles"),
            ("### Improved", "- Switch between large tab collections more smoothly"),
            ("### Fixed", "- Keep navigation controls in sync with the active page"),
        ):
            self.assertIn(heading, nightly.stdout)
            self.assertIn(message, nightly.stdout)
        self.assertNotIn("Open links in a compact preview", nightly.stdout)
        self.assertNotIn("Keep the iPhone toolbar in place", nightly.stdout)
        self.assertNotIn("structured release notes", nightly.stdout)
        self.assertNotIn("private subject", nightly.stdout)
        self.assertEqual(stable.returncode, 0, stable.stderr)
        self.assertIn("Open links in a compact preview", stable.stdout)
        self.assertIn("Keep existing behavior reliable", stable.stdout)

    def test_stable_release_publishes_its_versions_write_up(self) -> None:
        self.commit_version("0.5.24", [{"id": "boundary", "category": "internal", "message": "Boundary"}])
        current = self.commit_version(
            "0.5.25",
            [{"id": "profiles", "category": "new", "message": "Create separate browsing profiles"}],
            release={
                "summary": "Crest 0.5.25 brings browsing profiles.",
                "added": [
                    "Browsing profiles keep work and home apart.",
                    {"text": "Swipe between profiles on iPhone.", "platforms": ["ios"]},
                ],
                "upgrading": ["Mac requires macOS 26.1 or later."],
            },
        )

        stable = self.generate_notes(current, "boundary", channel="stable")
        nightly = self.generate_notes(current, "boundary", channel="nightly")

        self.assertEqual(stable.returncode, 0, stable.stderr)
        self.assertIn("Crest 0.5.25 brings browsing profiles.", stable.stdout)
        self.assertIn("### Added\n\n- Browsing profiles keep work and home apart.", stable.stdout)
        self.assertIn("### Upgrading\n\n- Mac requires macOS 26.1 or later.", stable.stdout)
        self.assertNotIn("Swipe between profiles on iPhone.", stable.stdout)
        self.assertNotIn("Create separate browsing profiles", stable.stdout)
        self.assertEqual(nightly.returncode, 0, nightly.stderr)
        self.assertNotIn("brings browsing profiles", nightly.stdout)
        self.assertIn("- Create separate browsing profiles", nightly.stdout)


if __name__ == "__main__":
    unittest.main()
