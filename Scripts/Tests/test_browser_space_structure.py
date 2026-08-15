#!/usr/bin/env python3
"""Structural contract for the shared BrowserSpace domain decomposition."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
SPACE_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserSpace"


class BrowserSpaceStructureTests(unittest.TestCase):
    def test_flat_browser_space_source_is_replaced_by_domain_tree(self) -> None:
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserSpace.swift").exists()
        )
        self.assertTrue((SPACE_ROOT / "BrowserSpace.swift").is_file())

    def test_domain_types_have_focused_semantic_files(self) -> None:
        expected_declarations = {
            "BrowserSpace.swift": "struct BrowserSpace",
            "Access/BrowserSpaceAccessPolicy.swift": "enum BrowserSpaceAccessPolicy",
            "Branding/SpaceAccent.swift": "enum SpaceAccent",
            "Branding/BrowserSpaceBannerPattern.swift": "enum BrowserSpaceBannerPattern",
            "Branding/BrowserSpaceBrandColor.swift": "struct BrowserSpaceBrandColor",
            "Branding/BrowserSpaceBrandColorRole.swift": "enum BrowserSpaceBrandColorRole",
            "Branding/BrowserSpaceHousePalette.swift": "enum BrowserSpaceHousePalette",
            "Branding/BrowserSpaceBranding.swift": "struct BrowserSpaceBranding",
            "Branding/BrowserSpaceIconStyle.swift": "enum BrowserSpaceIconStyle",
            "Branding/BrowserSpaceThemeMode.swift": "enum BrowserSpaceThemeMode",
            "Branding/Crest/BrowserSpaceCrest.swift": "struct BrowserSpaceCrest",
            "Branding/Crest/BrowserSpaceCrestBackplate.swift": "enum BrowserSpaceCrestBackplate",
            "Branding/Crest/BrowserSpaceCrestChargeLayout.swift": "enum BrowserSpaceCrestChargeLayout",
            "Branding/Crest/BrowserSpaceCrestFieldDivision.swift": "enum BrowserSpaceCrestFieldDivision",
            "Branding/Crest/BrowserSpaceCrestOrdinary.swift": "enum BrowserSpaceCrestOrdinary",
            "Branding/Crest/BrowserSpaceCrestSymbol.swift": "enum BrowserSpaceCrestSymbol",
            "Branding/Crest/BrowserSpaceCrestTrim.swift": "enum BrowserSpaceCrestTrim",
            "Browsing/BrowserBrowsingMode.swift": "enum BrowserBrowsingMode",
            "Browsing/BrowserContentBlockingPolicy.swift": "enum BrowserContentBlockingPolicy",
            "Browsing/BrowserCurrentTabCleanupPolicy.swift": "enum BrowserCurrentTabCleanupPolicy",
            "Browsing/BrowserCurrentTabCleanupSchedule.swift": "enum BrowserCurrentTabCleanupSchedule",
            "Browsing/BrowserPrivateBrowsingAppearance.swift": "enum BrowserPrivateBrowsingAppearance",
            "Browsing/BrowserSearchProvider.swift": "enum BrowserSearchProvider",
            "Browsing/BrowserSpaceBrowsingPreferences.swift": "struct BrowserSpaceBrowsingPreferences",
            "Credentials/BrowserCredentialPreferences.swift": "struct BrowserCredentialPreferences",
            "Folders/BrowserFolderNode.swift": "struct BrowserFolderNode",
            "Folders/BrowserFolderTree.swift": "struct BrowserFolderTree",
            "Profiles/BrowsingProfile.swift": "struct BrowsingProfile",
            "Tabs/BrowserTabSections.swift": "struct BrowserTabSections",
        }

        for relative_path, declaration in expected_declarations.items():
            with self.subTest(relative_path=relative_path):
                source_path = SPACE_ROOT / relative_path
                self.assertTrue(source_path.is_file())
                self.assertIn(declaration, source_path.read_text())

    def test_each_source_has_at_most_one_primary_declaration(self) -> None:
        declaration_pattern = re.compile(
            r"^(?:public |internal |private |fileprivate )?"
            r"(?:struct|enum|class|actor|protocol|typealias) ",
            re.MULTILINE,
        )

        for source_path in SPACE_ROOT.rglob("*.swift"):
            with self.subTest(source_path=source_path.relative_to(SPACE_ROOT)):
                declarations = declaration_pattern.findall(source_path.read_text())
                self.assertLessEqual(len(declarations), 1)

    def test_tolerant_decoder_helper_is_persistence_owned(self) -> None:
        helper_path = (
            SPACE_ROOT
            / "Persistence/KeyedDecodingContainer+TolerantRawRepresentable.swift"
        )
        self.assertTrue(helper_path.is_file())
        self.assertIn("extension KeyedDecodingContainer", helper_path.read_text())

    def test_space_color_presentation_extensions_have_individual_owners(self) -> None:
        support_root = (
            REPOSITORY_ROOT / "CrestShared/Features/Spaces/Support"
        )
        for filename, extension_owner in (
            ("BrowserTabIconAccent+Color.swift", "BrowserTabIconAccent"),
            ("SpaceAccent+Color.swift", "SpaceAccent"),
        ):
            with self.subTest(filename=filename):
                source = (support_root / filename).read_text()
                self.assertEqual(source.count("extension "), 1)
                self.assertIn(f"extension {extension_owner}", source)


if __name__ == "__main__":
    unittest.main()
