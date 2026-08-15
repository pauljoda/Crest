#!/usr/bin/env python3
"""Vertical ownership contracts for the shared Advanced Settings pane."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FEATURE_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Settings/BrowserAdvancedSettingsPane"
)
LEGACY_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Settings/BrowserAdvancedSettingsPane.swift"
)
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserAdvancedSettingsStructureTests(unittest.TestCase):
    def test_each_owner_has_a_matching_vertical_file(self) -> None:
        required = {
            "BrowserAdvancedSettingsPane.swift": "BrowserAdvancedSettingsPane",
            "Components/BrowserAdvancedSetupActionButton.swift":
                "BrowserAdvancedSetupActionButton",
            "Components/BrowserAdvancedSetupSection.swift":
                "BrowserAdvancedSetupSection",
            "Models/BrowserAdvancedSetupAction.swift": "BrowserAdvancedSetupAction",
        }

        for relative_path, owner in required.items():
            path = FEATURE_ROOT / relative_path
            with self.subTest(path=relative_path):
                self.assertTrue(path.is_file())
                self.assertEqual(DECLARATION_PATTERN.findall(path.read_text()), [owner])

        self.assertFalse(LEGACY_ROOT.exists())

    def test_root_composes_real_components_and_has_a_direct_preview(self) -> None:
        source = (FEATURE_ROOT / "BrowserAdvancedSettingsPane.swift").read_text()

        self.assertIn("BrowserAdvancedSetupSection(", source)
        self.assertIn("BrowserDataPortabilitySection(", source)
        self.assertIn("#Preview", source)
        self.assertIn("BrowserAdvancedSettingsPane(", source[source.index("#Preview"):])
        self.assertNotIn("extension View", source)
        self.assertNotIn("struct SetupAction", source)

    def test_setup_components_have_direct_deterministic_previews(self) -> None:
        for name in (
            "BrowserAdvancedSetupActionButton",
            "BrowserAdvancedSetupSection",
        ):
            source = (FEATURE_ROOT / f"Components/{name}.swift").read_text()
            with self.subTest(name=name):
                self.assertIn("#Preview", source)
                self.assertIn(f"{name}(", source[source.index("#Preview"):])
                self.assertNotIn("UUID()", source)
                self.assertNotIn("UserDefaults", source)

    def test_platform_shells_consume_the_shared_setup_action(self) -> None:
        for relative_path in (
            "CrestMac/Features/Settings/Components/BrowserSettingsDestinationView.swift",
            "CrestMobile/Features/Settings/MobileBrowserSettingsView/Components/"
            "MobileBrowserSettingsDestinationView.swift",
        ):
            source = (REPOSITORY_ROOT / relative_path).read_text()
            with self.subTest(path=relative_path):
                self.assertIn("[BrowserAdvancedSetupAction]", source)
                self.assertNotIn("BrowserAdvancedSettingsPane.SetupAction", source)


if __name__ == "__main__":
    unittest.main()
