#!/usr/bin/env python3
"""Regression coverage for Crest's semantic-version contract."""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECK_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-version.sh"
SET_SCRIPT = REPOSITORY_ROOT / "Scripts" / "set-version.sh"


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

        (self.fixture_root / "Crest.xcodeproj").mkdir()
        self.environment = os.environ | {
            "CREST_VERSION_REPOSITORY_ROOT": str(self.fixture_root),
        }

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

    def run_set(self, version: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SET_SCRIPT), version],
            cwd=self.fixture_root,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def install_fake_xcodebuild(self, marketing_version: str | None = None) -> None:
        fake_bin = self.fixture_root / "fake-bin"
        fake_bin.mkdir()
        fake_xcodebuild = fake_bin / "xcodebuild"

        if marketing_version is None:
            version_expression = (
                'sed -nE \'s/^[[:space:]]*MARKETING_VERSION[[:space:]]*='
                "[[:space:]]*([^[:space:]]+)[[:space:]]*$/\\1/p' "
                '"$CREST_VERSION_REPOSITORY_ROOT/Config/Version.xcconfig"'
            )
            marketing_line = f'marketing_version="$({version_expression})"'
        else:
            marketing_line = f'marketing_version="{marketing_version}"'

        fake_xcodebuild.write_text(
            "#!/bin/sh\n"
            f"{marketing_line}\n"
            'printf \'    MARKETING_VERSION = %s\\n\' "$marketing_version"\n'
            "printf '    CURRENT_PROJECT_VERSION = 1\\n'\n"
        )
        fake_xcodebuild.chmod(0o755)
        self.environment["PATH"] = f"{fake_bin}{os.pathsep}{os.environ['PATH']}"

    def test_repository_contract_passes_static_validation(self) -> None:
        result = subprocess.run(
            [str(CHECK_SCRIPT), "--static"],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0.3.0", result.stdout)

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

    def test_static_check_rejects_literal_plist_versions(self) -> None:
        plist = self.fixture_root / "CrestMac" / "Configuration" / "Crest-Info.plist"
        contents = plist.read_text().replace("$(MARKETING_VERSION)", "0.3.0")
        plist.write_text(contents)

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must substitute $(MARKETING_VERSION)", result.stderr)

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

    def test_static_check_rejects_build_number_in_marketing_version_file(self) -> None:
        version_file = self.fixture_root / "Config" / "Version.xcconfig"
        version_file.write_text(
            "MARKETING_VERSION = 0.3.0\nCURRENT_PROJECT_VERSION = 2\n"
        )

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must contain only MARKETING_VERSION", result.stderr)

    def test_set_version_rejects_non_increasing_and_shorthand_versions(self) -> None:
        for requested in ("0.2.9", "0.3.0", "0.3", "0.3.1-beta"):
            with self.subTest(version=requested):
                result = self.run_set(requested)
                self.assertNotEqual(result.returncode, 0)

        self.assertEqual(
            (self.fixture_root / "Config" / "Version.xcconfig").read_text(),
            "MARKETING_VERSION = 0.3.0\n",
        )

    def test_set_version_updates_only_the_marketing_version_source(self) -> None:
        self.install_fake_xcodebuild()
        before = {
            path: (self.fixture_root / path).read_bytes()
            for path in (
                "CrestMac/Configuration/Crest-Info.plist",
                "CrestMobile/Configuration/CrestMobile-Info.plist",
                "project.yml",
            )
        }

        result = self.run_set("0.4.0")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.fixture_root / "Config" / "Version.xcconfig").read_text(),
            "MARKETING_VERSION = 0.4.0\n",
        )
        for path, contents in before.items():
            self.assertEqual((self.fixture_root / path).read_bytes(), contents)

    def test_set_version_restores_the_previous_value_when_resolution_drifts(self) -> None:
        self.install_fake_xcodebuild(marketing_version="9.9.9")

        result = self.run_set("0.4.0")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("restored 0.3.0", result.stderr)
        self.assertEqual(
            (self.fixture_root / "Config" / "Version.xcconfig").read_text(),
            "MARKETING_VERSION = 0.3.0\n",
        )


if __name__ == "__main__":
    unittest.main()
