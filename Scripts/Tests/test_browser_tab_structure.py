#!/usr/bin/env python3
"""Structural contracts for the core browser-tab domain family."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DECLARATION = re.compile(
    r"^(?:(?:private|fileprivate|public|internal)\s+)*"
    r"(?:final\s+)?(?:struct|class|enum|protocol|extension|actor)\s+",
    re.MULTILINE,
)


class BrowserTabStructureTests(unittest.TestCase):
    def test_browser_tab_domain_uses_named_files(self) -> None:
        root = REPOSITORY_ROOT / "CrestShared/Domain/BrowserTab"
        required_files = (
            "BrowserTab.swift",
            "Archive/ArchivedTab.swift",
            "Archive/TabArchiveReason.swift",
            "Folders/SavedFolder.swift",
            "Icons/BrowserTabIconAccent.swift",
            "Icons/BrowserTabIconAccentResolver.swift",
            "Icons/BrowserTabIconMode.swift",
            "Icons/BrowserTabIconSessionItem.swift",
            "Icons/BrowserTabIconSessionState.swift",
            "Models/TabPlacement.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((root / relative_path).is_file())

        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserTab.swift").exists()
        )

    def test_each_browser_tab_file_owns_one_top_level_declaration(self) -> None:
        root = REPOSITORY_ROOT / "CrestShared/Domain/BrowserTab"
        for path in root.rglob("*.swift"):
            with self.subTest(path=path):
                self.assertEqual(len(DECLARATION.findall(path.read_text())), 1)

    def test_icon_session_item_is_not_nested_in_snapshot(self) -> None:
        source = (
            REPOSITORY_ROOT
            / "CrestShared/Domain/BrowserTab/Icons/BrowserTabIconSessionState.swift"
        ).read_text()
        self.assertIn("typealias Item = BrowserTabIconSessionItem", source)
        self.assertNotIn("struct Item", source)


if __name__ == "__main__":
    unittest.main()
