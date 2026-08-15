#!/usr/bin/env python3
"""Vertical ownership contract for macOS Sidebar site and extension controls."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Sidebar"
PINNED_ROOT = SIDEBAR_ROOT / "BrowserPinnedExtensionStrip"
SITE_CONTROL_ROOT = SIDEBAR_ROOT / "BrowserSiteControlButton"
ANCHOR_ROOT = REPOSITORY_ROOT / "CrestMac/Infrastructure/WebKit/BrowserExtensions"

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
    r"(?:View|ButtonStyle)\b",
    re.MULTILINE,
)


class MacSidebarControlsStructureTests(unittest.TestCase):
    def test_sidebar_controls_are_split_into_named_vertical_families(self) -> None:
        self.assertFalse((SIDEBAR_ROOT / "BrowserPinnedExtensionStrip.swift").exists())
        self.assertFalse((SIDEBAR_ROOT / "BrowserSiteControlButton.swift").exists())

        required_files = (
            PINNED_ROOT / "BrowserPinnedExtensionStrip.swift",
            PINNED_ROOT / "Components/BrowserPinnedExtensionStripContent.swift",
            PINNED_ROOT / "Components/BrowserPinnedExtensionActionList.swift",
            PINNED_ROOT / "Components/BrowserPinnedExtensionActionButton.swift",
            PINNED_ROOT / "Support/BrowserPinnedExtensionStripLayoutPolicy.swift",
            SITE_CONTROL_ROOT / "BrowserSiteControlButton.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteControlTrigger.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteControlPopover.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteControlContent.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteControlHeader.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteQuickActions.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteQuickActionButton.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteExtensionsSection.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteExtensionsHeader.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteExtensionActionButton.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteExtensionActionControl.swift",
            SITE_CONTROL_ROOT / "Components/BrowserSiteExtensionActionLabel.swift",
            SITE_CONTROL_ROOT / "Models/BrowserSiteControlConfiguration.swift",
            SITE_CONTROL_ROOT / "Support/BrowserSiteControlLayoutPolicy.swift",
            SITE_CONTROL_ROOT / "Support/BrowserSiteControlPresentationPolicy.swift",
            SIDEBAR_ROOT / "Components/BrowserExtensionActionArtwork.swift",
            SIDEBAR_ROOT / "Components/BrowserExtensionBadge.swift",
            SIDEBAR_ROOT / "Components/BrowserExtensionPinButton.swift",
            SIDEBAR_ROOT / "Models/BrowserExtensionActionPresentation.swift",
            SIDEBAR_ROOT / "Support/BrowserSidebarExtensionPreviewFixture.swift",
            ANCHOR_ROOT / "BrowserExtensionPopupAnchorReader.swift",
            ANCHOR_ROOT / "BrowserExtensionPopupAnchorView.swift",
        )
        for source_file in required_files:
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_file.is_file())

    def test_each_source_has_one_matching_primary_owner(self) -> None:
        source_files = []
        for source_root in (PINNED_ROOT, SITE_CONTROL_ROOT):
            source_files.extend(source_root.rglob("*.swift"))
        source_files.extend(
            (
                SIDEBAR_ROOT / "Components/BrowserExtensionActionArtwork.swift",
                SIDEBAR_ROOT / "Components/BrowserExtensionPinButton.swift",
                SIDEBAR_ROOT / "Models/BrowserExtensionActionPresentation.swift",
                SIDEBAR_ROOT / "Support/BrowserSidebarExtensionPreviewFixture.swift",
                ANCHOR_ROOT / "BrowserExtensionPopupAnchorReader.swift",
                ANCHOR_ROOT / "BrowserExtensionPopupAnchorView.swift",
            )
        )
        for source_file in source_files:
            declarations = PRIMARY_DECLARATION.findall(source_file.read_text())
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, [source_file.stem])

    def test_visual_feature_owners_have_direct_deterministic_previews(self) -> None:
        feature_files = list(PINNED_ROOT.rglob("*.swift"))
        feature_files.extend(SITE_CONTROL_ROOT.rglob("*.swift"))
        feature_files.extend(
            (
                SIDEBAR_ROOT / "Components/BrowserExtensionActionArtwork.swift",
                SIDEBAR_ROOT / "Components/BrowserExtensionPinButton.swift",
            )
        )
        for source_file in feature_files:
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
                    "BrowserExtensionControllerPool.production",
                    "UserDefaults",
                    "WKWebsiteDataStore.default",
                    "UUID()",
                    "Date()",
                ):
                    self.assertNotIn(forbidden, preview)

    def test_action_routing_remains_bound_to_exact_space_and_tab_ids(self) -> None:
        source = "\n".join(
            source_file.read_text()
            for source_root in (PINNED_ROOT, SITE_CONTROL_ROOT)
            for source_file in source_root.rglob("*.swift")
        )
        self.assertIn("in: spaceID", source)
        self.assertIn("tabID: selectedTabID", source)
        self.assertIn("in: configuration.space.id", source)
        self.assertIn("tabID: configuration.selectedTabID", source)
        self.assertIn("extensionControllerPool.perform(", source)
        self.assertIn("extensionControllerPool.setPinned(", source)
        self.assertNotRegex(source, r"spaces\s*\[")

    def test_preview_and_popup_anchor_adapters_are_isolated(self) -> None:
        fixture = (
            SIDEBAR_ROOT / "Support/BrowserSidebarExtensionPreviewFixture.swift"
        ).read_text()
        self.assertRegex(fixture, r"UUID\s*\(\s*uuid:")
        for required in (
            "Date(timeIntervalSince1970:",
            "InMemoryBrowserSessionPersistence()",
            "browsingMode: .privateBrowsing",
            "usesEphemeralWebsiteDataStores: true",
        ):
            self.assertIn(required, fixture)
        for forbidden in (
            "UserDefaults",
            ".production(",
            "BrowserWebsiteDataStore.persistent",
            "WKWebsiteDataStore.default",
        ):
            self.assertNotIn(forbidden, fixture)

        reader = (ANCHOR_ROOT / "BrowserExtensionPopupAnchorReader.swift").read_text()
        anchor_view = (ANCHOR_ROOT / "BrowserExtensionPopupAnchorView.swift").read_text()
        self.assertIn("NSViewRepresentable", reader)
        self.assertNotIn("final class", reader)
        self.assertIn("final class BrowserExtensionPopupAnchorView: NSView", anchor_view)


if __name__ == "__main__":
    unittest.main()
