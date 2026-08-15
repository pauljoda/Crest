#!/usr/bin/env python3
"""Structural contracts for identity wrappers and semantic color tokens."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class CoreIdentifierAndColorStructureTests(unittest.TestCase):
    def test_domain_identifiers_use_one_named_file_each(self) -> None:
        root = REPOSITORY_ROOT / "CrestShared/Domain/BrowserIdentifiers"
        for name in ("SpaceID.swift", "TabID.swift", "FolderID.swift", "BrowserWindowID.swift"):
            with self.subTest(name=name):
                self.assertTrue((root / name).is_file())
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserIdentifiers.swift").exists()
        )

    def test_semantic_color_roles_use_named_files(self) -> None:
        root = REPOSITORY_ROOT / "CrestShared/DesignSystem/Tokens/CrestColor"
        for name in ("CrestColor.swift", "CrestColorComponents.swift", "CrestBrandPalette.swift"):
            with self.subTest(name=name):
                self.assertTrue((root / name).is_file())
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/DesignSystem/Tokens/CrestColor.swift").exists()
        )

    def test_brand_palette_uses_semantic_opacity_tokens(self) -> None:
        palette = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Tokens/CrestColor/CrestBrandPalette.swift"
        ).read_text()
        colors = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Tokens/CrestColor/CrestColor.swift"
        ).read_text()
        self.assertIn("CrestOpacity.brandHairline", palette)
        self.assertIn("CrestOpacity.dropIndicator", colors)
        self.assertNotIn(".opacity(0.18)", palette)
        self.assertNotIn(".opacity(0.72)", colors)

    def test_space_foreground_policy_keeps_swiftui_mapping_in_design_system(self) -> None:
        domain_root = (
            REPOSITORY_ROOT
            / "CrestShared/Domain/BrowserSpace/Branding"
        )
        domain_policy_path = domain_root / "BrowserSpaceForegroundPolicy.swift"
        domain_tone_path = domain_root / "BrowserSpaceForegroundTone.swift"
        presentation_mapping = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Tokens/CrestColor/BrowserSpaceForegroundPolicy+ColorScheme.swift"
        )

        self.assertTrue(domain_policy_path.is_file())
        self.assertTrue(domain_tone_path.is_file())
        domain_policy = domain_policy_path.read_text()
        self.assertNotIn("import SwiftUI", domain_policy)
        self.assertNotIn("ColorScheme", domain_policy)
        self.assertIn("enum BrowserSpaceForegroundPolicy", domain_policy)
        self.assertIn("enum BrowserSpaceForegroundTone", domain_tone_path.read_text())
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserSpaceForegroundPolicy.swift").exists()
        )
        self.assertTrue(presentation_mapping.is_file())
        self.assertIn("import SwiftUI", presentation_mapping.read_text())
        self.assertIn("static func colorScheme", presentation_mapping.read_text())


if __name__ == "__main__":
    unittest.main()
