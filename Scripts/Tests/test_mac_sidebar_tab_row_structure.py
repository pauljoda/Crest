#!/usr/bin/env python3
"""Vertical ownership contract for the macOS Sidebar tab row."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Sidebar"
ROW_ROOT = SIDEBAR_ROOT / "SidebarTabRow"

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
    r"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
    r"(?:View|ViewModifier|NSGestureRecognizerRepresentable)\b",
    re.MULTILINE,
)


class MacSidebarTabRowStructureTests(unittest.TestCase):
    def test_tab_row_is_a_named_vertical_feature_family(self) -> None:
        self.assertFalse((SIDEBAR_ROOT / "SidebarTabRow.swift").exists())
        required_files = (
            ROW_ROOT / "SidebarTabRow.swift",
            ROW_ROOT / "Components/SidebarTabRowContent.swift",
            ROW_ROOT / "Components/SidebarTabRowSurface.swift",
            ROW_ROOT / "Components/SidebarTabActivationContent.swift",
            ROW_ROOT / "Components/SidebarTabRenameField.swift",
            ROW_ROOT / "Components/SidebarTabActivationButton.swift",
            ROW_ROOT / "Components/SidebarTabActivationLabel.swift",
            ROW_ROOT / "Components/SidebarTabFaviconContent.swift",
            ROW_ROOT / "Components/SidebarTabTrailingControl.swift",
            ROW_ROOT / "Components/SidebarTabUnloadButton.swift",
            ROW_ROOT / "Components/SidebarTabCloseButton.swift",
            ROW_ROOT / "Components/SidebarTabTrailingControlLabel.swift",
            ROW_ROOT / "Components/BrowserMiddleClickGesture.swift",
            ROW_ROOT / "Models/SidebarTabRowConfiguration.swift",
            ROW_ROOT / "Models/SidebarTabRowInteractionContext.swift",
            ROW_ROOT / "Models/BrowserTabMiddleClickAction.swift",
            ROW_ROOT / "Support/BrowserTabActivationPolicy.swift",
            ROW_ROOT / "Support/BrowserTabMiddleClickPolicy.swift",
            ROW_ROOT / "Support/View+BrowserOnMiddleClick.swift",
            ROW_ROOT / "Support/View+BrowserTabPromotionDestination.swift",
            ROW_ROOT / "Support/SidebarTabRowPreviewFixture.swift",
            SIDEBAR_ROOT / "Support/BrowserTabTrailingControlPolicy.swift",
        )
        for source_file in required_files:
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_file.is_file())

    def test_each_source_has_one_matching_primary_owner(self) -> None:
        source_files = list(ROW_ROOT.rglob("*.swift"))
        source_files.append(SIDEBAR_ROOT / "Support/BrowserTabTrailingControlPolicy.swift")
        for source_file in source_files:
            declarations = PRIMARY_DECLARATION.findall(source_file.read_text())
            expected = [] if "+" in source_file.stem else [source_file.stem]
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected)

    def test_each_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        for source_file in ROW_ROOT.rglob("*.swift"):
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

    def test_actions_remain_bound_to_exact_tab_and_space_ids(self) -> None:
        source = "\n".join(
            source_file.read_text()
            for source_file in ROW_ROOT.rglob("*.swift")
        )
        for required in (
            "selectTab(tabID)",
            "presentPage()",
            "browser.closeTab(\n                configuration.tab.id,\n                matching: configuration.assignment",
            "unload(configuration.tab.id)",
            "BrowserTabDragAction(",
            "profileID: configuration.profileID",
            "for: request.tabID",
            "spaceID: request.spaceID",
            "profileID: request.profileID",
            "beforeTabID: tab.id",
            'BrowserTabAccessibilityID.row(configuration.tab.id)',
            'accessibilityIdentifier("tab-rename-field")',
        ):
            self.assertIn(required, source)
        self.assertNotRegex(source, r"spaces\s*\[")
        self.assertNotIn("selectedTabIndex", source)
        self.assertIn("@State private var renameRequest: BrowserTabRuntimeAssignment?", source)
        self.assertIn(".onChange(of: runtimeAssignment)", source)
        self.assertIn(".onChange(of: configuration.isCurrentAndUnlocked)", source)

    def test_middle_click_and_trailing_control_contracts_remain_exact(self) -> None:
        source = "\n".join(
            source_file.read_text()
            for source_file in ROW_ROOT.rglob("*.swift")
        )
        trailing = (
            SIDEBAR_ROOT / "Support/BrowserTabTrailingControlPolicy.swift"
        ).read_text()
        for required in (
            "placement == .current ? .close : .unload",
            "recognizer.buttonMask = 1 << 2",
            "recognizer.numberOfClicksRequired = 1",
            "guard recognizer.state == .ended else { return }",
            "CrestLayout.minimumHitTarget",
            "static let glyphSize: CGFloat = 12",
        ):
            self.assertIn(required, source + trailing)

    def test_preview_uses_private_in_memory_owners_and_fixed_identity(self) -> None:
        fixture = (ROW_ROOT / "Support/SidebarTabRowPreviewFixture.swift").read_text()
        self.assertRegex(fixture, r"UUID\s*\(\s*uuid:")
        for required in (
            "Date(timeIntervalSince1970:",
            "InMemoryBrowserSessionPersistence()",
            "browsingMode: .privateBrowsing",
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
