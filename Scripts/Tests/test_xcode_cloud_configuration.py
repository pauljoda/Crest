#!/usr/bin/env python3
"""Repository-level contracts for Crest's Xcode Cloud release workflow."""

from __future__ import annotations

import os
import pathlib
import json
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


    def test_post_clone_guard_accepts_submission_xcode_and_rejects_unknown_prerelease(self) -> None:
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

            for xcode_version, build_version, expected_return_code in (
                ("26.6", "17F113", 0),
                ("27.0", "27A266a", 0),
                ("27.0", "27A5228h", 64),
                ("27.0", "27A266b", 64),
            ):
                with self.subTest(build_version=build_version):
                    fake_xcodebuild.write_text(
                        "#!/bin/sh\n"
                        'printf \'Xcode %s\\nBuild version %s\\n\'\n'
                        % (xcode_version, build_version)
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

    def test_post_xcodebuild_uploads_app_store_export_only_without_ad_hoc_export(self) -> None:
        guard = REPOSITORY_ROOT / "ci_scripts" / "ci_post_xcodebuild.sh"

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = pathlib.Path(temporary_directory)
            archive = temporary_root / "CrestMobile.xcarchive"
            app = archive / "Products" / "Applications" / "Crest.app"
            app.mkdir(parents=True)
            with (archive / "Info.plist").open("wb") as stream:
                plistlib.dump(
                    {"ApplicationProperties": {"ApplicationPath": "Applications/Crest.app"}},
                    stream,
                )
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump(
                    {
                        "CFBundleIdentifier": "com.pauldavis.crest",
                        "CFBundleShortVersionString": self.marketing_version(),
                        "CFBundleVersion": "52",
                    },
                    stream,
                )

            app_store_export = temporary_root / "appstoreexport"
            ad_hoc_export = temporary_root / "adhocexport"
            app_store_export.mkdir()
            ad_hoc_export.mkdir()
            app_store_package = app_store_export / "Crest.ipa"
            app_store_package.write_bytes(b"ipa")

            capture = temporary_root / "capture"
            capture.mkdir()
            fake_bin = temporary_root / "bin"
            fake_bin.mkdir()
            fake_xcrun = fake_bin / "xcrun"
            fake_xcrun.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$@" > "$FAKE_XCRUN_CAPTURE/arguments"\n'
                'while [ "$#" -gt 0 ]; do\n'
                '    [ "$1" = "--p8-file-path" ] && cat "$2" > "$FAKE_XCRUN_CAPTURE/key"\n'
                "    shift\n"
                "done\n"
                "exit 0\n"
            )
            fake_xcrun.chmod(0o755)

            base_environment = {
                name: value
                for name, value in os.environ.items()
                if not name.startswith("CREST_ASC_")
            } | {
                "CI_XCODE_CLOUD": "TRUE",
                "CI_XCODEBUILD_ACTION": "archive",
                "CI_XCODEBUILD_EXIT_CODE": "0",
                "CI_PRODUCT_PLATFORM": "iOS",
                "CI_PRIMARY_REPOSITORY_PATH": str(REPOSITORY_ROOT),
                "CI_ARCHIVE_PATH": str(archive),
                "CI_BUILD_NUMBER": "52",
                "CI_AD_HOC_SIGNED_APP_PATH": str(ad_hoc_export),
                "CI_APP_STORE_SIGNED_APP_PATH": str(app_store_export),
                "FAKE_XCRUN_CAPTURE": str(capture),
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            }
            credentials = {
                "CREST_ASC_API_KEY_ID": "KEY123",
                "CREST_ASC_API_ISSUER_ID": "issuer",
                "CREST_ASC_API_PRIVATE_KEY_BASE64": "cHJpdmF0ZSBrZXk=",
            }

            def run_guard(environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    [str(guard)],
                    cwd=REPOSITORY_ROOT,
                    env=environment,
                    capture_output=True,
                    text=True,
                    check=False,
                )

            with self.subTest(export="missing credentials"):
                result = run_guard(base_environment)
                self.assertEqual(result.returncode, 64)
                self.assertIn("CREST_ASC_API_KEY_ID", result.stderr)
                self.assertFalse((capture / "arguments").exists())

            with self.subTest(export="App Store only"):
                result = run_guard(base_environment | credentials)
                self.assertEqual(result.returncode, 0, result.stderr)
                arguments = (capture / "arguments").read_text().splitlines()
                self.assertEqual(arguments[:7], [
                    "altool",
                    "--upload-package",
                    str(app_store_package),
                    "--api-key",
                    "KEY123",
                    "--api-issuer",
                    "issuer",
                ])
                self.assertEqual((capture / "key").read_text(), "private key")
                self.assertFalse(pathlib.Path(arguments[arguments.index("--p8-file-path") + 1]).exists())

            (capture / "arguments").unlink()
            (ad_hoc_export / "Crest.ipa").write_bytes(b"ipa")
            with self.subTest(export="every distribution"):
                result = run_guard(base_environment | credentials)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("TestFlight post-action", result.stdout)
                self.assertFalse((capture / "arguments").exists())


    def make_cloud_checkout(self, root: pathlib.Path) -> pathlib.Path:
        """A primary repository with history, the version and catalog
        scripts, and a generated project, as Xcode Cloud clones it."""
        repository = root / "crest"
        (repository / "Config").mkdir(parents=True)
        (repository / "Scripts").mkdir()
        (repository / "Crest.xcodeproj").mkdir()
        (repository / "Documentation" / "ReleaseNotes").mkdir(parents=True)
        for script in ("derive-version.py", "release_note_catalog.py"):
            shutil.copy2(REPOSITORY_ROOT / "Scripts" / script, repository / "Scripts" / script)
        (repository / "Crest.xcodeproj" / "project.pbxproj").write_text("CURRENT_PROJECT_VERSION = 1;\n")
        (repository / "Documentation" / "ReleaseNotes.json").write_text(json.dumps(
            {"schemaVersion": 1, "entries": {"existing-change": {"category": "fixed", "message": "Keep it reliable"}}}))
        (repository / "Config" / "Version.xcconfig").write_text("MARKETING_VERSION = 0.8.10\n")

        def git(*arguments: str) -> None:
            subprocess.run(["git", "-C", str(repository), *arguments], check=True, capture_output=True)

        git("init", "-q", "--initial-branch=main")
        git("config", "user.name", "Crest Tests")
        git("config", "user.email", "tests@crestbrowser.com")
        git("add", "-A")
        git("commit", "-q", "-m", "base")
        for identifier in ("first-change", "second-change"):
            (repository / "Documentation" / "ReleaseNotes" / f"{identifier}.json").write_text(
                json.dumps({"category": "new", "message": f"Add {identifier}"}))
            git("add", "-A")
            git("commit", "-q", "-m", identifier)
        return repository

    def run_pre_archive(self, root: pathlib.Path, repository: pathlib.Path) -> subprocess.CompletedProcess[str]:
        fake_bin = root / "bin"
        fake_bin.mkdir(exist_ok=True)
        # Reports what the checkout's files configure, as xcodebuild resolves them.
        (fake_bin / "xcodebuild").write_text(
            "#!/bin/sh\n"
            f"version=$(sed -nE 's/^MARKETING_VERSION = (.*)$/\\1/p' '{repository}/Config/Version.xcconfig')\n"
            f"build=$(sed -nE 's/^CURRENT_PROJECT_VERSION = (.*);$/\\1/p' '{repository}/Crest.xcodeproj/project.pbxproj')\n"
            'echo "    MARKETING_VERSION = $version"\n'
            'echo "    CURRENT_PROJECT_VERSION = $build"\n')
        (fake_bin / "xcodebuild").chmod(0o755)
        return subprocess.run(
            ["/bin/sh", str(REPOSITORY_ROOT / "ci_scripts" / "ci_pre_xcodebuild.sh")],
            env=os.environ | {
                "CI_XCODE_CLOUD": "TRUE",
                "CI_XCODEBUILD_ACTION": "archive",
                "CI_PRIMARY_REPOSITORY_PATH": str(repository),
                "CI_PRODUCT_PLATFORM": "macOS",
                "CI_XCODE_SCHEME": "Crest",
                "CI_BUILD_NUMBER": "1234",
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            },
            check=False, capture_output=True, text=True,
        )

    def test_pre_archive_stamps_the_derived_version_and_the_assembled_catalog(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repository = self.make_cloud_checkout(root)

            result = self.run_pre_archive(root, repository)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("version 0.8.12 (1234)", result.stdout)
            self.assertEqual((repository / "Config" / "Version.xcconfig").read_text(), "MARKETING_VERSION = 0.8.12\n")
            catalog = json.loads((repository / "Documentation" / "ReleaseNotes.json").read_text())
            self.assertEqual(list(catalog["entries"]), ["existing-change", "first-change", "second-change"])

    def test_pre_archive_refuses_a_shallow_clone(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repository = self.make_cloud_checkout(root)
            shallow = root / "shallow"
            subprocess.run(["git", "clone", "-q", "--depth", "1", f"file://{repository}", str(shallow)],
                           check=True, capture_output=True)

            result = self.run_pre_archive(root, shallow)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("full history", result.stderr)


if __name__ == "__main__":
    unittest.main()
