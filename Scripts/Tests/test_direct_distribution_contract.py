#!/usr/bin/env python3
"""Regression coverage for Crest's direct macOS release signing path."""

from __future__ import annotations

import pathlib
import plistlib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
EXPORT_OPTIONS = REPOSITORY_ROOT / "Config" / "DeveloperIDExportOptions.plist"
RELEASE_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "release.yml"


class DirectDistributionContractTests(unittest.TestCase):
    def test_unchanged_nightly_stops_before_the_release_job(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("preflight:", workflow)
        self.assertIn('release_tag="nightly"', workflow)
        self.assertIn(
            'if [[ "$channel" == "nightly" && "$previous_commit" == "$GITHUB_SHA" ]]',
            workflow,
        )
        self.assertIn("should_publish=false", workflow)
        self.assertIn(
            "if: needs.preflight.outputs.should_publish == 'true'",
            workflow,
        )

    def test_rolling_channels_publish_one_clearly_named_asset_set(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn('release_tag="nightly"', workflow)
        self.assertIn("maximum_versions=1", workflow)
        self.assertIn('installer_name="Installer-${RELEASE_ASSET_BASE}.dmg"', workflow)
        self.assertIn('checksum_name="Checksum-${RELEASE_ASSET_BASE}.dmg.sha256"', workflow)
        self.assertIn('symbols_name="Debug-Symbols-${RELEASE_ASSET_BASE}.dSYM.zip"', workflow)
        self.assertIn('release_notes_name="Installer-${RELEASE_ASSET_BASE}.md"', workflow)
        self.assertIn("generate-release-notes.py", workflow)

    def test_interrupted_rolling_release_uses_the_last_published_appcast(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("resolve-published-release.py", workflow)
        self.assertIn('appcast_filename="appcast-development.xml"', workflow)
        self.assertIn('appcast_filename="appcast.xml"', workflow)
        self.assertIn('git show "FETCH_HEAD:${appcast_filename}"', workflow)
        self.assertIn("reconcile-release-assets.py", workflow)
        self.assertIn("--prune-other-assets", workflow)
        self.assertNotIn("gh release delete-asset", workflow)
        self.assertNotIn("--clobber", workflow)
        self.assertIn("local attempt delay exit_code", workflow)
        self.assertNotIn("local attempt delay status", workflow)

    def test_release_note_cursor_advances_atomically_with_the_signed_appcast(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("release_note_marker:", workflow)
        self.assertIn('release_note_state_filename="release-note-publication.json"', workflow)
        self.assertIn('--previous-entry "$RELEASE_NOTE_MARKER"', workflow)
        self.assertIn("release_note_publication.py advance", workflow)
        self.assertIn(
            'git -C "$updates_checkout" add "$appcast_filename" README.md '
            '"$release_note_state_filename"',
            workflow,
        )
        self.assertEqual(workflow.count("release_note_publication.py advance"), 1)
        self.assertLess(
            workflow.index("release_note_publication.py advance"),
            workflow.index('git -C "$updates_checkout" push origin HEAD:updates'),
        )

    def test_release_build_number_survives_the_public_repository_epoch(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("build_epoch=1000", workflow)
        self.assertIn(
            'build_number="$((build_epoch + GITHUB_RUN_NUMBER))"',
            workflow,
        )
        self.assertNotIn('build_number="$GITHUB_RUN_NUMBER"', workflow)

    def test_export_uses_the_named_developer_id_profile(self) -> None:
        with EXPORT_OPTIONS.open("rb") as stream:
            options = plistlib.load(stream)

        self.assertEqual(options["method"], "developer-id")
        self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(options["signingCertificate"], "Developer ID Application")
        self.assertEqual(options["teamID"], "3U2R97HLXF")
        self.assertEqual(
            options["provisioningProfiles"],
            {"com.pauldavis.crest": "Crest Developer ID"},
        )

    def test_release_workflow_preserves_production_entitlements(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        for required in (
            "DEVELOPER_ID_PROVISIONING_PROFILE_BASE64",
            'CODE_SIGN_STYLE=Manual',
            'CODE_SIGN_IDENTITY="Developer ID Application"',
            'PROVISIONING_PROFILE_SPECIFIER="Crest Developer ID"',
            "com.apple.application-identifier",
            "com.apple.developer.aps-environment",
            "com.apple.developer.icloud-container-identifiers:0",
            "keychain-access-groups:0",
            "diskutil image create from",
            "--volumeName Crest",
            "--format ULFO",
        ):
            with self.subTest(required=required):
                self.assertIn(required, workflow)

        self.assertNotIn("CODE_SIGNING_ALLOWED=NO", workflow)
        self.assertNotIn("CODE_SIGN_STYLE=Automatic", workflow)
        self.assertNotIn("hdiutil create", workflow)


if __name__ == "__main__":
    unittest.main()
