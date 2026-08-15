#!/usr/bin/env python3
"""Structural contracts for shared Settings view families and platform seams."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SHARED_SETTINGS = REPOSITORY_ROOT / "CrestShared/Features/Settings"


class SettingsFamilyStructureTests(unittest.TestCase):
    def test_root_files_own_only_their_root_view(self) -> None:
        roots = {
            "BrowserLinkSettingsPane/BrowserLinkSettingsPane.swift": (
                "BrowserLinkSettingsPane"
            ),
            "BrowserPrivacySettingsPane.swift": "BrowserPrivacySettingsPane",
            "BrowserExtensionSettingsPane.swift": "BrowserExtensionSettingsPane",
        }

        for file_name, expected_declaration in roots.items():
            source = (SHARED_SETTINGS / file_name).read_text()
            declarations = re.findall(
                r"^(?:@[A-Za-z0-9_() ,.]+\n)*"
                r"(?:(?:public|internal|private|fileprivate|final)\s+)*"
                r"(?:struct|class|enum|actor|protocol|extension)\s+"
                r"([A-Za-z0-9_]+)",
                source,
                flags=re.MULTILINE,
            )
            with self.subTest(file_name=file_name):
                self.assertEqual(declarations, [expected_declaration])

    def test_shared_settings_components_are_grouped_by_family(self) -> None:
        required_files = (
            "Models/BrowserSettingsSpaceDataRequest.swift",
            "Support/BrowserSettingsPrivacyPolicy.swift",
            "Components/BrowserSettingsPrivateSpaceAccess/BrowserSettingsPrivateSpaceAccessSection.swift",
            "Components/BrowserSettingsPrivateSpaceAccess/Components/BrowserSettingsPrivateSpaceAccessRow.swift",
            "Components/BrowserSettingsPrivateSpaceAccess/Components/BrowserSettingsPrivateSpaceIdentity.swift",
            "Components/BrowserSettingsPrivateSpaceAccess/Components/BrowserSettingsPrivateSpaceUnlockControl.swift",
            "Components/BrowserSettingsPrivateSpaceAccess/Support/BrowserSettingsPrivateSpaceAccessPreviewFixture.swift",
            "Components/BrowserSettingsPrivateSpaceAccess/Support/BrowserSettingsPrivateSpacePreviewAuthenticator.swift",
            "BrowserLinkSettingsPane/Models/BrowserLinkSettingsGuidanceKind.swift",
            "BrowserLinkSettingsPane/BrowserLinkSettingsPane.swift",
            "BrowserLinkSettingsPane/Components/BrowserLinkSettingsContent.swift",
            "BrowserLinkSettingsPane/Components/BrowserExternalLinkDestinationSection.swift",
            "BrowserLinkSettingsPane/Components/BrowserQuickWindowSettingsSection.swift",
            "BrowserLinkSettingsPane/Components/BrowserPeekSettingsSection.swift",
            "BrowserLinkSettingsPane/Components/BrowserLinkRoutingSection.swift",
            "BrowserLinkSettingsPane/Support/BrowserLinkSettingsPreviewAuthenticator.swift",
            "BrowserLinkSettingsPane/Support/BrowserLinkSettingsPreviewFixture.swift",
            "BrowserLinkSettingsPane/Support/BrowserLinkSettingsSpacePolicy.swift",
            "BrowserPrivacySettingsPane/Components/BrowserPrivacySpaceSection.swift",
            "BrowserPrivacySettingsPane/Support/BrowserPrivacySettingsLayout.swift",
            "BrowserPrivacySettingsPane/Components/BrowserContentBlockingSettingsSection.swift",
            "BrowserPrivacySettingsPane/Components/BrowserSavedSitePermissionSection.swift",
            "BrowserPrivacySettingsPane/Components/BrowserSitePermissionRecordRow.swift",
            "BrowserPrivacySettingsPane/Support/BrowserPrivacySettingsPreviewFixture.swift",
            "BrowserExtensionSettingsPane/Models/BrowserExtensionStatus.swift",
            "BrowserExtensionSettingsPane/Support/BrowserExtensionSettingsPreviewFixture.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((SHARED_SETTINGS / relative_path).is_file())

        self.assertFalse(
            (SHARED_SETTINGS / "BrowserSettingsPrivateSpaceAccess.swift").exists()
        )

    def test_touched_shared_families_have_no_platform_implementation(self) -> None:
        roots = (
            SHARED_SETTINGS / "BrowserLinkSettingsPane/BrowserLinkSettingsPane.swift",
            SHARED_SETTINGS / "BrowserPrivacySettingsPane.swift",
            SHARED_SETTINGS / "BrowserExtensionSettingsPane.swift",
        )
        families = tuple(
            SHARED_SETTINGS / name
            for name in (
                "BrowserLinkSettingsPane",
                "BrowserPrivacySettingsPane",
                "BrowserExtensionSettingsPane",
            )
        )
        sources = list(roots)
        for family in families:
            if family.exists():
                sources.extend(family.rglob("*.swift"))

        for path in sources:
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("#if os(", source)
                self.assertNotIn("#elseif os(", source)
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn(".menuStyle(.borderlessButton)", source)

    def test_shared_production_component_files_own_one_declaration(self) -> None:
        for family_name in (
            "BrowserLinkSettingsPane",
            "BrowserPrivacySettingsPane",
            "BrowserExtensionSettingsPane",
        ):
            family = SHARED_SETTINGS / family_name
            for path in family.rglob("*.swift"):
                declarations = re.findall(
                    r"^(?:@[A-Za-z0-9_() ,.]+\n)*"
                    r"(?:(?:public|internal|private|fileprivate|final)\s+)*"
                    r"(?:struct|class|enum|actor|protocol|extension)\s+"
                    r"([A-Za-z0-9_]+)",
                    path.read_text(),
                    flags=re.MULTILINE,
                )
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(len(declarations), 1)

    def test_platform_settings_seams_live_in_both_platform_roots(self) -> None:
        required_files = (
            "Components/BrowserPlatformPrivacyScopeFootnote.swift",
            "Components/BrowserPlatformSitePermissionMenuModifier.swift",
        )

        for platform in ("CrestMac", "CrestMobile"):
            platform_root = REPOSITORY_ROOT / platform / "Features/Settings"
            for relative_path in required_files:
                with self.subTest(platform=platform, relative_path=relative_path):
                    self.assertTrue((platform_root / relative_path).is_file())

            editor_root = (
                REPOSITORY_ROOT
                / platform
                / "Features/Settings/BrowserPlatformLinkRouteEditor"
            )
            for relative_path in (
                "BrowserPlatformLinkRouteEditor.swift",
                "Components/BrowserPlatformLinkRouteEditorContent.swift",
                "Support/BrowserPlatformLinkRouteLayout.swift",
            ):
                with self.subTest(platform=platform, relative_path=relative_path):
                    self.assertTrue((editor_root / relative_path).is_file())

            guidance = (
                REPOSITORY_ROOT
                / platform
                / "Features/Settings/BrowserPlatformLinkSettingsGuidance"
                / "BrowserPlatformLinkSettingsGuidance.swift"
            )
            self.assertTrue(guidance.is_file())

    def test_extension_settings_keeps_the_manager_inline(self) -> None:
        source = (SHARED_SETTINGS / "BrowserExtensionSettingsPane.swift").read_text()

        self.assertIn("BrowserExtensionsView(", source)
        self.assertNotIn("managedSpace", source)
        self.assertNotIn(".sheet(", source)

    def test_every_visual_family_has_deterministic_previews(self) -> None:
        preview_files = (
            "BrowserPrivacySettingsPane.swift",
            "BrowserPrivacySettingsPane/Components/BrowserPrivacySpaceSection.swift",
            "BrowserPrivacySettingsPane/Components/BrowserContentBlockingSettingsSection.swift",
            "BrowserPrivacySettingsPane/Components/BrowserSavedSitePermissionSection.swift",
            "BrowserPrivacySettingsPane/Components/BrowserSitePermissionRecordRow.swift",
            "BrowserExtensionSettingsPane.swift",
        )

        for relative_path in preview_files:
            source = (SHARED_SETTINGS / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertIn("#Preview", source)
                self.assertNotIn("UUID(uuidString:", source)
                self.assertNotRegex(source, r"(?:\)|\]|[A-Za-z0-9_])!(?![=])")

        privacy_root = SHARED_SETTINGS / "BrowserPrivacySettingsPane"
        self.assertFalse((privacy_root / "Metrics").exists())
        self.assertFalse((privacy_root / "Previews").exists())
        extension_root = SHARED_SETTINGS / "BrowserExtensionSettingsPane"
        self.assertFalse((extension_root / "Metrics").exists())
        self.assertFalse((extension_root / "Previews").exists())


if __name__ == "__main__":
    unittest.main()
