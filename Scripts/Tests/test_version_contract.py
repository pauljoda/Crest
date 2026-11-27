#!/usr/bin/env python3
"""Regression coverage for Crest's semantic-version contract and its versions from git."""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECK_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-version.sh"
VERSION_SCRIPT = REPOSITORY_ROOT / "Scripts" / "crest_version.py"
# Only macOS ships plutil; CI runs these on its macOS build runners.
REQUIRES_PLUTIL = unittest.skipUnless(
    shutil.which("plutil"), "check-version.sh reads the Info.plists with macOS plutil"
)


class VersionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.fixture_root = pathlib.Path(self.temporary_directory.name)

        for relative_path in (
            "Config/Version.xcconfig",
            "CrestMac/Configuration/Crest-Info.plist",
            "CrestMobile/Configuration/CrestMobile-Info.plist",
            "project.yml",
        ):
            source = REPOSITORY_ROOT / relative_path
            destination = self.fixture_root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        shutil.copytree(
            REPOSITORY_ROOT / "Documentation/ReleaseNotes",
            self.fixture_root / "Documentation/ReleaseNotes",
        )

        (self.fixture_root / "Crest.xcodeproj").mkdir()
        self.environment = os.environ | {
            "CREST_VERSION_REPOSITORY_ROOT": str(self.fixture_root),
        }
        self.current_version = self.current_marketing_version()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_check(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CHECK_SCRIPT), *arguments],
            cwd=self.fixture_root,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def current_marketing_version(self) -> str:
        contents = (
            self.fixture_root / "Config" / "Version.xcconfig"
        ).read_text()
        return contents.split("=", maxsplit=1)[1].strip()

    @REQUIRES_PLUTIL
    def test_repository_contract_passes_static_validation(self) -> None:
        result = subprocess.run(
            [str(CHECK_SCRIPT), "--static"],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(self.current_version, result.stdout)

    def test_static_check_rejects_malformed_semver(self) -> None:
        version_file = self.fixture_root / "Config" / "Version.xcconfig"

        for malformed in (
            "0.3",
            "01.3.0",
            "0.03.0",
            "0.3.00",
            "0.3.0-beta.1",
            "0.3.0+build.1",
        ):
            with self.subTest(version=malformed):
                version_file.write_text(f"MARKETING_VERSION = {malformed}\n")
                result = self.run_check("--static")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("strict X.Y.Z SemVer", result.stderr)

    @REQUIRES_PLUTIL
    def test_static_check_rejects_literal_plist_versions(self) -> None:
        plist = self.fixture_root / "CrestMac" / "Configuration" / "Crest-Info.plist"
        contents = plist.read_text().replace("$(MARKETING_VERSION)", "0.3.0")
        plist.write_text(contents)

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must substitute $(MARKETING_VERSION)", result.stderr)

    @REQUIRES_PLUTIL
    def test_static_check_rejects_configuration_drift(self) -> None:
        project = self.fixture_root / "project.yml"
        contents = project.read_text().replace(
            "  Release: Config/Version.xcconfig",
            "  Release: Config/ReleaseVersion.xcconfig",
            1,
        )
        project.write_text(contents)

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release must inherit Config/Version.xcconfig", result.stderr)


class ComputedVersionTests(unittest.TestCase):
    """Published builds take their version from git, so it must rise with every commit on main."""

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.repository = self.root / "repository"
        self.repository.mkdir()
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "Crest Tests")
        self.git("config", "user.email", "crest-tests@example.invalid")

    def git(self, *arguments: str, cwd: pathlib.Path | None = None) -> str:
        return subprocess.run(
            ["git", *arguments], cwd=cwd or self.repository, check=True, capture_output=True, text=True,
        ).stdout.strip()

    def commit(self, path: str, contents: str) -> str:
        (self.repository / path).parent.mkdir(parents=True, exist_ok=True)
        (self.repository / path).write_text(contents)
        self.git("add", path)
        self.git("commit", "-m", f"Change {path}")
        return self.git("rev-parse", "HEAD")

    def version(self, *arguments: str, repository: pathlib.Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(VERSION_SCRIPT), "--repository-root", str(repository or self.repository), *arguments],
            check=False, capture_output=True, text=True,
        )

    def assert_version(self, expected: str, *arguments: str) -> None:
        result = self.version(*arguments)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), expected)

    def test_each_main_commit_counts_one_patch_past_the_anchor(self) -> None:
        anchor = self.commit("Config/Version.xcconfig", "MARKETING_VERSION = 0.5.25\n")
        documentation = self.commit("README.md", "Crest\n")
        self.git("switch", "-c", "feature")
        self.commit("feature.txt", "one\n")
        feature = self.commit("feature.txt", "two\n")
        self.git("switch", "main")
        self.commit("main.txt", "fix\n")
        # Editing the file without changing the version is not an anchor.
        self.commit("Config/Version.xcconfig", "// The release line's anchor.\nMARKETING_VERSION = 0.5.25\n")

        self.assert_version("0.5.25", "--at", anchor)
        self.assert_version("0.5.26", "--at", documentation)
        self.assert_version("0.5.28")
        self.assert_version("0.5.29", "next")
        # A branch carries its merge base's version and isn't on main.
        self.assert_version("0.5.26", "--at", feature)
        self.assertNotEqual(self.version("--at", feature, "--on-main").returncode, 0)

        self.git("merge", "--no-ff", "--no-edit", "feature")
        self.assert_version("0.5.29")
        # A commit merged in from a branch takes the version of the merge.
        self.assert_version("0.5.29", "--at", feature)

        self.commit("Config/Version.xcconfig", "MARKETING_VERSION = 0.6.0\n")
        self.assert_version("0.6.0")
        self.commit("main.txt", "next line\n")
        self.assert_version("0.6.1", "--on-main")

    def test_a_shallow_clone_is_refused_rather_than_counted_short(self) -> None:
        self.commit("Config/Version.xcconfig", "MARKETING_VERSION = 0.5.25\n")
        self.commit("main.txt", "fix\n")
        shallow = self.root / "shallow"
        self.git("clone", "--quiet", "--depth", "1", f"file://{self.repository}", str(shallow), cwd=self.root)

        result = self.version(repository=shallow)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--unshallow", result.stderr)


if __name__ == "__main__":
    unittest.main()
