#!/usr/bin/env python3
"""Vertical ownership contracts for the shared Settings pane header family."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SETTINGS_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Settings"
HEADER_ROOT = SETTINGS_ROOT / "Components/BrowserSettingsPaneHeader"
LEGACY_PATH = SETTINGS_ROOT / "BrowserSettingsPaneHeader.swift"
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserSettingsPaneHeaderStructureTests(unittest.TestCase):
    def test_each_owner_has_one_matching_vertical_file(self) -> None:
        required = {
            SETTINGS_ROOT / "Components/BrowserSettingsPane.swift":
                "BrowserSettingsPane",
            HEADER_ROOT / "BrowserSettingsPaneHeader.swift":
                "BrowserSettingsPaneHeader",
            HEADER_ROOT / "Components/BrowserSettingsPaneHeaderIcon.swift":
                "BrowserSettingsPaneHeaderIcon",
            HEADER_ROOT / "Components/BrowserSettingsPaneHeaderCopy.swift":
                "BrowserSettingsPaneHeaderCopy",
            HEADER_ROOT / "Models/BrowserSettingsPaneHeaderLayout.swift":
                "BrowserSettingsPaneHeaderLayout",
        }

        for path, owner in required.items():
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(DECLARATION_PATTERN.findall(path.read_text()), [owner])

        self.assertFalse(LEGACY_PATH.exists())

    def test_visual_owners_have_direct_deterministic_previews(self) -> None:
        visual_owners = {
            SETTINGS_ROOT / "Components/BrowserSettingsPane.swift":
                "BrowserSettingsPane",
            HEADER_ROOT / "BrowserSettingsPaneHeader.swift":
                "BrowserSettingsPaneHeader",
            HEADER_ROOT / "Components/BrowserSettingsPaneHeaderIcon.swift":
                "BrowserSettingsPaneHeaderIcon",
            HEADER_ROOT / "Components/BrowserSettingsPaneHeaderCopy.swift":
                "BrowserSettingsPaneHeaderCopy",
        }

        for path, owner in visual_owners.items():
            source = path.read_text()
            with self.subTest(owner=owner):
                self.assertIn("#Preview", source)
                self.assertIn(f"{owner}(", source[source.index("#Preview"):])
                self.assertNotIn("UserDefaults", source)
                self.assertNotIn("UUID()", source)

    def test_header_composes_real_icon_and_copy_components(self) -> None:
        source = (HEADER_ROOT / "BrowserSettingsPaneHeader.swift").read_text()

        self.assertIn("BrowserSettingsPaneHeaderIcon(", source)
        self.assertIn("BrowserSettingsPaneHeaderCopy(", source)
        self.assertNotIn("struct Layout", source)
        self.assertNotIn("CrestIconTile(", source)

    def test_layout_is_a_top_level_model_and_platform_neutral(self) -> None:
        layout_source = (
            HEADER_ROOT / "Models/BrowserSettingsPaneHeaderLayout.swift"
        ).read_text()

        self.assertIn("static let macOSPage", layout_source)
        self.assertIn("static let mobilePage", layout_source)
        for path in HEADER_ROOT.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path.name):
                self.assertNotIn("#if os(", source)
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)


if __name__ == "__main__":
    unittest.main()
