#!/usr/bin/env python3
"""Repository-level contracts for Crest's Xcode Cloud release workflow."""

from __future__ import annotations

import os
import pathlib
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]


class XcodeCloudConfigurationTests(unittest.TestCase):
    @staticmethod
    def marketing_version() -> str:
        version_file = REPOSITORY_ROOT / "Config" / "Version.xcconfig"
        return version_file.read_text().split("=", maxsplit=1)[1].strip()

    def test_project_targets_os26_with_the_current_project_format(self) -> None:
        project = (REPOSITORY_ROOT / "project.yml").read_text()

        self.assertIn('xcodeVersion: "27.0"', project)
        self.assertIn('iOS: "26.1"', project)
        self.assertIn('macOS: "26.1"', project)
        self.assertIn('IPHONEOS_DEPLOYMENT_TARGET: "26.1"', project)
        self.assertIn('MACOSX_DEPLOYMENT_TARGET: "26.1"', project)
        self.assertIn("SWIFT_COMPILATION_MODE: singlefile", project)

    def test_both_app_schemes_are_shared_and_archive_enabled(self) -> None:
        for scheme_name, blueprint_name in (
            ("Crest", "Crest"),
            ("CrestMobile", "CrestMobile"),
        ):
            with self.subTest(scheme=scheme_name):
                scheme_path = (
                    REPOSITORY_ROOT
                    / "Crest.xcodeproj"
                    / "xcshareddata"
                    / "xcschemes"
                    / f"{scheme_name}.xcscheme"
                )
                root = ET.parse(scheme_path).getroot()
                archive_action = root.find("ArchiveAction")
                self.assertIsNotNone(archive_action)
                self.assertEqual(archive_action.attrib["buildConfiguration"], "Release")

                archivable_blueprints = {
                    entry.find("BuildableReference").attrib["BlueprintName"]
                    for entry in root.findall("./BuildAction/BuildActionEntries/BuildActionEntry")
                    if entry.attrib.get("buildForArchiving") == "YES"
                }
                self.assertIn(blueprint_name, archivable_blueprints)

    def test_post_clone_guard_enforces_manual_cross_platform_archives(self) -> None:
        guard = REPOSITORY_ROOT / "ci_scripts" / "ci_post_clone.sh"

        self.assertTrue(guard.is_file())
        self.assertTrue(os.access(guard, os.X_OK))
        contents = guard.read_text()
        for required in (
            "CI_START_CONDITION",
            "manual",
            "manual_rebuild",
            "CI_PRODUCT_PLATFORM",
            "CI_COMMIT",
            "https://github.com/pauljoda/Crest.git",
            "CrestMobile",
            "Crest",
            "26.1",
            "release Xcode",
            "beta or prerelease",
        ):
            self.assertIn(required, contents)

    def test_post_clone_guard_accepts_release_xcode_and_rejects_prerelease(self) -> None:
        guard = REPOSITORY_ROOT / "ci_scripts" / "ci_post_clone.sh"

        with tempfile.TemporaryDirectory() as temporary_directory:
            fake_bin = pathlib.Path(temporary_directory)
            fake_git = fake_bin / "git"
            fake_xcodebuild = fake_bin / "xcodebuild"
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)
            fake_git.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "    *' remote get-url origin')\n"
                "        printf '%s\\n' 'http://github.com/pauljoda/Crest.git'\n"
                "        ;;\n"
                "    *)\n"
                f"        exec {shlex.quote(real_git)} \"$@\"\n"
                "        ;;\n"
                "esac\n"
            )
            fake_git.chmod(0o755)
            environment = os.environ | {
                "CI_XCODE_CLOUD": "TRUE",
                "CI_START_CONDITION": "manual",
                "CI_XCODEBUILD_ACTION": "archive",
                "CI_PRODUCT_PLATFORM": "iOS",
                "CI_XCODE_SCHEME": "CrestMobile",
                "CI_PRIMARY_REPOSITORY_PATH": str(REPOSITORY_ROOT),
                "CI_COMMIT": subprocess.check_output(
                    ["git", "rev-parse", "HEAD"],
                    cwd=REPOSITORY_ROOT,
                    text=True,
                ).strip(),
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            }

            for build_version, expected_return_code in (
                ("17F113", 0),
                ("27A5228h", 64),
            ):
                with self.subTest(build_version=build_version):
                    fake_xcodebuild.write_text(
                        "#!/bin/sh\n"
                        'printf \'Xcode 26.6\\nBuild version %s\\n\'\n' % build_version
                    )
                    fake_xcodebuild.chmod(0o755)
                    result = subprocess.run(
                        [str(guard)],
                        cwd=REPOSITORY_ROOT,
                        env=environment,
                        capture_output=True,
                        text=True,
                        check=False,
                    )

                    self.assertEqual(result.returncode, expected_return_code)
                    if expected_return_code:
                        self.assertIn("beta or prerelease", result.stderr)

    def test_cloud_version_guards_are_executable(self) -> None:
        for script_name, required_environment in (
            (
                "ci_pre_xcodebuild.sh",
                (
                    "CI_XCODE_SCHEME",
                    "CI_BUILD_NUMBER",
                    "MARKETING_VERSION",
                    "CURRENT_PROJECT_VERSION",
                    "-showBuildSettings",
                ),
            ),
            (
                "ci_post_xcodebuild.sh",
                (
                    "CI_ARCHIVE_PATH",
                    "CI_BUILD_NUMBER",
                    "CFBundleShortVersionString",
                ),
            ),
        ):
            with self.subTest(script=script_name):
                script = REPOSITORY_ROOT / "ci_scripts" / script_name
                self.assertTrue(script.is_file())
                self.assertTrue(os.access(script, os.X_OK))
                contents = script.read_text()
                for required in required_environment:
                    self.assertIn(required, contents)

    def test_pre_xcodebuild_guard_rejects_resolved_version_drift(self) -> None:
        guard = REPOSITORY_ROOT / "ci_scripts" / "ci_pre_xcodebuild.sh"
        expected_version = self.marketing_version()

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = pathlib.Path(temporary_directory)
            repository = temporary_root / "repository"
            version_file = repository / "Config" / "Version.xcconfig"
            project_file = repository / "Crest.xcodeproj" / "project.pbxproj"
            version_file.parent.mkdir(parents=True)
            project_file.parent.mkdir(parents=True)
            version_file.write_text(f"MARKETING_VERSION = {expected_version}\n")
            project_file.write_text(
                "CURRENT_PROJECT_VERSION = 1;\n"
                "CURRENT_PROJECT_VERSION = 1;\n"
            )

            fake_bin = temporary_root / "bin"
            fake_bin.mkdir()
            fake_xcodebuild = fake_bin / "xcodebuild"
            environment = os.environ | {
                "CI_XCODE_CLOUD": "TRUE",
                "CI_XCODEBUILD_ACTION": "archive",
                "CI_PRODUCT_PLATFORM": "iOS",
                "CI_XCODE_SCHEME": "CrestMobile",
                "CI_PRIMARY_REPOSITORY_PATH": str(repository),
                "CI_BUILD_NUMBER": "22",
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            }

            for resolved_version, expected_return_code in (
                (expected_version, 0),
                ("0.3.0", 64),
            ):
                with self.subTest(resolved_version=resolved_version):
                    fake_xcodebuild.write_text(
                        "#!/bin/sh\n"
                        f"printf '    MARKETING_VERSION = {resolved_version}\\n'\n"
                        "printf '    CURRENT_PROJECT_VERSION = 22\\n'\n"
                    )
                    fake_xcodebuild.chmod(0o755)
                    result = subprocess.run(
                        [str(guard)],
                        cwd=REPOSITORY_ROOT,
                        env=environment,
                        capture_output=True,
                        text=True,
                        check=False,
                    )

                    self.assertEqual(result.returncode, expected_return_code)
                    self.assertNotIn(
                        "CURRENT_PROJECT_VERSION = 1;",
                        project_file.read_text(),
                    )
                    self.assertEqual(
                        project_file.read_text().count(
                            "CURRENT_PROJECT_VERSION = 22;"
                        ),
                        2,
                    )
                    if expected_return_code:
                        self.assertIn(
                            f"expected {expected_version}",
                            result.stderr,
                        )

    def test_post_xcodebuild_guard_rejects_archived_version_drift(self) -> None:
        guard = REPOSITORY_ROOT / "ci_scripts" / "ci_post_xcodebuild.sh"
        expected_version = self.marketing_version()

        with tempfile.TemporaryDirectory() as temporary_directory:
            archive = pathlib.Path(temporary_directory) / "CrestMobile.xcarchive"
            app = archive / "Products" / "Applications" / "Crest.app"
            app.mkdir(parents=True)
            with (archive / "Info.plist").open("wb") as stream:
                plistlib.dump(
                    {
                        "ApplicationProperties": {
                            "ApplicationPath": "Applications/Crest.app",
                        },
                    },
                    stream,
                )

            environment = os.environ | {
                "CI_XCODE_CLOUD": "TRUE",
                "CI_XCODEBUILD_ACTION": "archive",
                "CI_XCODEBUILD_EXIT_CODE": "0",
                "CI_PRIMARY_REPOSITORY_PATH": str(REPOSITORY_ROOT),
                "CI_ARCHIVE_PATH": str(archive),
                "CI_BUILD_NUMBER": "20",
            }

            for archived_version, expected_return_code in (
                (expected_version, 0),
                ("0.3.0", 64),
            ):
                with self.subTest(archived_version=archived_version):
                    with (app / "Info.plist").open("wb") as stream:
                        plistlib.dump(
                            {
                                "CFBundleIdentifier": "com.pauldavis.crest",
                                "CFBundleShortVersionString": archived_version,
                                "CFBundleVersion": "20",
                            },
                            stream,
                        )
                    result = subprocess.run(
                        [str(guard)],
                        cwd=REPOSITORY_ROOT,
                        env=environment,
                        capture_output=True,
                        text=True,
                        check=False,
                    )

                    self.assertEqual(result.returncode, expected_return_code)
                    if expected_return_code:
                        self.assertIn(
                            f"but Config/Version.xcconfig requires {expected_version}",
                            result.stderr,
                        )

    def test_extension_toggle_avoids_xcode_26_setter_thunk_crash(self) -> None:
        extensions_view = (
            REPOSITORY_ROOT
            / "CrestShared"
            / "Features"
            / "Extensions"
            / "BrowserExtensionsView"
            / "Components"
            / "BrowserExtensionRow.swift"
        ).read_text()

        self.assertNotIn("set: setEnabled", extensions_view)
        self.assertIn("set: { isEnabled in", extensions_view)
        self.assertIn("setEnabled(isEnabled)", extensions_view)

    def test_onboarding_bindings_avoid_xcode_26_setter_thunk_crash(self) -> None:
        component_root = (
            REPOSITORY_ROOT
            / "CrestMac"
            / "Features"
            / "Onboarding"
            / "BrowserOnboardingWindow"
            / "Components"
        )
        bindings = (
            (
                component_root / "BrowserOnboardingWindowContent.swift",
                "updatePlan",
                "plan",
            ),
            (
                component_root / "BrowserOnboardingManualSetupPage.swift",
                "updateManualPlan",
                "plan",
            ),
        )

        for path, method, parameter in bindings:
            with self.subTest(path=path.name):
                source = path.read_text()
                self.assertNotIn(f"set: flow.{method}", source)
                self.assertIn(f"set: {{ {parameter} in", source)
                self.assertIn(f"flow.{method}({parameter})", source)

    def test_release_builds_keep_batch_compilation_enabled(self) -> None:
        project = (REPOSITORY_ROOT / "project.yml").read_text()

        self.assertNotIn("SWIFT_ENABLE_BATCH_MODE: NO", project)

if __name__ == "__main__":
    unittest.main()
