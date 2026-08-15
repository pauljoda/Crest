#!/usr/bin/env python3
"""Structural contracts for the shared address-field component family."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class BrowserAddressContentStructureTests(unittest.TestCase):
    def test_address_component_uses_named_files(self) -> None:
        root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Chrome/BrowserAddressContent"
        )
        required_files = (
            "BrowserAddressContent.swift",
            "Models/BrowserAddressPresentation.swift",
            "Services/BrowserAddressFocusDismissal.swift",
            "Components/BrowserAddressLongPressButtonStyle.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Features/Chrome/BrowserAddressContent.swift"
            ).exists()
        )
        self.assertIn("#Preview", (root / "BrowserAddressContent.swift").read_text())
        self.assertFalse((root / "Previews").exists())

    def test_shared_address_components_are_platform_neutral(self) -> None:
        root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Chrome/BrowserAddressContent"
        )
        for path in root.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

    def test_native_input_policy_lives_in_platform_roots(self) -> None:
        for platform_root in ("CrestMac", "CrestMobile"):
            path = (
                REPOSITORY_ROOT
                / platform_root
                / "Features/Chrome/Components/BrowserPlatformAddressInputModifier.swift"
            )
            with self.subTest(platform_root=platform_root):
                self.assertTrue(path.is_file())
                self.assertIn(
                    "#Preview",
                    path.read_text(),
                )

        mobile = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Chrome/Components/BrowserPlatformAddressInputModifier.swift"
        ).read_text()
        self.assertIn("BrowserAddressKeyboardPolicy.keyboardType", mobile)
        self.assertIn(".submitLabel(.go)", mobile)
        self.assertTrue(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Features/Chrome/Support/BrowserAddressKeyboardPolicy.swift"
            ).is_file()
        )
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Features/Chrome/BrowserPlatformAddressInputModifier.swift"
            ).exists()
        )

    def test_all_address_entry_points_use_the_platform_modifier(self) -> None:
        paths = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Chrome/BrowserAddressContent/BrowserAddressContent.swift",
            REPOSITORY_ROOT
            / "CrestShared/Features/Chrome/Components/BrowserCommandPalette/Components/BrowserCommandPaletteCard/Components/BrowserCommandPaletteSearchField.swift",
        )
        for path in paths:
            with self.subTest(path=path):
                self.assertIn(
                    ".modifier(BrowserPlatformAddressInputModifier())",
                    path.read_text(),
                )


if __name__ == "__main__":
    unittest.main()
