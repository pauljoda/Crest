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
            'CREST_PROVISIONING_PROFILE_SPECIFIER="Crest Developer ID"',
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
