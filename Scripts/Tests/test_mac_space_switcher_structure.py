#!/usr/bin/env python3
"""Vertical ownership contract for the macOS Space switcher."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Sidebar"
SWITCHER_ROOT = SIDEBAR_ROOT / "SpaceSwitcher"

PRIMARY_DECLARATION = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
VISUAL_DECLARATION = re.compile(
    r"^(?:(?:private|fileprivate|internal|public|package|final)\s+)*"
    r"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b",
    re.MULTILINE,
)


class MacSpaceSwitcherStructureTests(unittest.TestCase):
    def test_switcher_is_a_named_vertical_feature_family(self) -> None:
        self.assertFalse((SIDEBAR_ROOT / "SpaceSwitcher.swift").exists())
        required_files = (
            SWITCHER_ROOT / "SpaceSwitcher.swift",
            SWITCHER_ROOT / "Components/DesktopSpaceSelectionControl.swift",
            SWITCHER_ROOT / "Components/SpacePickerIcon.swift",
            SWITCHER_ROOT / "Components/SpacePickerSegment.swift",
            SWITCHER_ROOT / "Components/SpaceSwitcherContent.swift",
            SWITCHER_ROOT / "Components/SpaceSwitcherCommonListsButton.swift",
            SWITCHER_ROOT / "Models/BrowserSpaceSwitcherUtility.swift",
            SWITCHER_ROOT / "Support/BrowserSpaceSwitcherLayout.swift",
            SWITCHER_ROOT / "Support/SpaceSwitcherPreviewFixture.swift",
            SWITCHER_ROOT / "Support/SpaceSwitcherPreviewAuthenticator.swift",
        )
        for source_file in required_files:
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_file.is_file())

    def test_each_source_has_one_matching_primary_owner(self) -> None:
        for source_file in SWITCHER_ROOT.rglob("*.swift"):
            declarations = PRIMARY_DECLARATION.findall(source_file.read_text())
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, [source_file.stem])

    def test_each_view_has_a_direct_deterministic_preview(self) -> None:
        for source_file in SWITCHER_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            owners = VISUAL_DECLARATION.findall(source)
            if not owners:
                continue
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(owners, [source_file.stem])
                preview = source[source.index("#Preview") :]
                self.assertIn(f"{source_file.stem}(", preview)
                for forbidden in (
                    "BrowserStore.production",
                    "UserDefaults",
                    "WKWebsiteDataStore.default",
                    "UUID()",
                    "Date()",
                ):
                    self.assertNotIn(forbidden, preview)

    def test_selection_and_drop_routing_use_exact_space_ids(self) -> None:
        source = "\n".join(
            source_file.read_text()
            for source_file in SWITCHER_ROOT.rglob("*.swift")
        )
        for required in (
            "selectedSpaceID: browser.session.selectedSpaceID",
            "selectSpace: (SpaceID) -> Void",
            "destination: assignment",
            "BrowserSpaceRuntimeAssignment(space: space)",
            "BrowserTabDragAction(browser: browser, spaceAccess: spaceAccess)",
            "dragAction.move(item, into: destination)",
        ):
            self.assertIn(required, source)
        self.assertNotRegex(source, r"spaces\s*\[")
        self.assertNotIn("selectedSpaceIndex", source)

    def test_preview_uses_private_in_memory_and_ephemeral_owners(self) -> None:
        fixture = (SWITCHER_ROOT / "Support/SpaceSwitcherPreviewFixture.swift").read_text()
        self.assertRegex(fixture, r"UUID\s*\(\s*uuid:")
        for required in (
            "Date(timeIntervalSince1970:",
            "InMemoryBrowserSessionPersistence()",
            "browsingMode: .privateBrowsing",
            "usesEphemeralWebsiteDataStores: true",
            "SpaceSwitcherPreviewAuthenticator()",
        ):
            self.assertIn(required, fixture)
        for forbidden in (
            "UserDefaults",
            ".production(",
            "BrowserWebsiteDataStore.persistent",
            "WKWebsiteDataStore.default",
        ):
            self.assertNotIn(forbidden, fixture)


if __name__ == "__main__":
    unittest.main()
