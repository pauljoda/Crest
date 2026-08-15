#!/usr/bin/env python3
"""File-scope ownership contracts for shared Settings bindings."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SETTINGS_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Settings"
LEGACY_PATH = SETTINGS_ROOT / "BrowserSettingsBindings.swift"
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
EXTENSION_PATTERN = re.compile(
    r"^extension\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\{",
    re.MULTILINE,
)


class BrowserSettingsBindingsStructureTests(unittest.TestCase):
    def test_each_file_scope_owner_has_a_matching_vertical_file(self) -> None:
        component_path = SETTINGS_ROOT / "Components/CrestSpaceSelectionRepair.swift"
        browser_path = SETTINGS_ROOT / "Support/BrowserStore+SettingsBindings.swift"
        view_path = SETTINGS_ROOT / "Support/View+CrestRepairsSpaceSelection.swift"

        self.assertTrue(component_path.is_file())
        self.assertEqual(
            DECLARATION_PATTERN.findall(component_path.read_text()),
            ["CrestSpaceSelectionRepair"],
        )

        for path, owner in ((browser_path, "BrowserStore"), (view_path, "View")):
            with self.subTest(path=path.name):
                self.assertTrue(path.is_file())
                source = path.read_text()
                self.assertEqual(DECLARATION_PATTERN.findall(source), [])
                self.assertEqual(EXTENSION_PATTERN.findall(source), [owner])

        self.assertFalse(LEGACY_PATH.exists())

    def test_selection_repair_modifier_has_a_direct_isolated_preview(self) -> None:
        source = (
            SETTINGS_ROOT / "Components/CrestSpaceSelectionRepair.swift"
        ).read_text()

        self.assertIn("#Preview", source)
        preview_source = source[source.index("#Preview"):]
        self.assertIn(".modifier(", preview_source)
        self.assertIn("CrestSpaceSelectionRepair(", preview_source)
        self.assertIn("BrowserStore.preview()", source)
        self.assertNotIn("UserDefaults", source)
        self.assertNotIn("UUID()", source)

    def test_extensions_keep_binding_and_view_responsibilities_separate(self) -> None:
        browser_source = (
            SETTINGS_ROOT / "Support/BrowserStore+SettingsBindings.swift"
        ).read_text()
        view_source = (
            SETTINGS_ROOT / "Support/View+CrestRepairsSpaceSelection.swift"
        ).read_text()

        for method in (
            "repairedSpaceSelection",
            "liveSpace",
            "spaceIdentityBinding",
            "browsingPreferenceBinding",
            "credentialPreferenceBinding",
            "spaceBrandingBinding",
            "defaultSpaceBinding",
        ):
            self.assertIn(f"func {method}", browser_source)

        self.assertNotIn("extension View", browser_source)
        self.assertIn("func crestRepairsSpaceSelection", view_source)
        self.assertIn("CrestSpaceSelectionRepair(", view_source)
        self.assertNotIn("extension BrowserStore", view_source)


if __name__ == "__main__":
    unittest.main()
