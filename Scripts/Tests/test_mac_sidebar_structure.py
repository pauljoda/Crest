#!/usr/bin/env python3
"""Structural contracts for the macOS BrowserSidebar component family."""

from __future__ import annotations

import json
import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Sidebar"
FAMILY_ROOT = SIDEBAR_ROOT / "BrowserSidebar"
ROOT_VIEW = SIDEBAR_ROOT / "BrowserSidebar.swift"


class MacSidebarStructureTests(unittest.TestCase):
    def test_sidebar_family_is_decomposed_by_responsibility(self) -> None:
        required_files = (
            "Support/BrowserSidebarMetrics.swift",
            "Support/BrowserSidebarPreviewFixture.swift",
            "Models/BrowserSidebarInteractionActions.swift",
            "Models/BrowserSidebarTabActions.swift",
            "Services/BrowserSidebarUtilityCoordinator.swift",
            "Components/BrowserSidebarAuxiliaryMouseMonitor.swift",
            "Components/BrowserSidebarAuxiliaryMouseObserverView.swift",
            "Components/BrowserSidebarLoadedContent/BrowserSidebarLoadedContent.swift",
            "Components/BrowserSidebarLoadedContent/BrowserSidebarSpacePage.swift",
            "Components/SpaceSidebarContent/SpaceSidebarContent.swift",
            "Components/SpaceSidebarContent/SpaceSidebarBrowsingContent.swift",
            "Components/SpaceSidebarContent/SpaceSidebarUtilityContent.swift",
            "Components/SpaceSidebarContent/SidebarNavigationControls/SidebarNavigationControls.swift",
            "Components/SpaceSidebarContent/SidebarNavigationControls/BrowserNavigationHistoryMenu.swift",
            "Components/SpaceSidebarContent/SpaceHeader/SpaceHeader.swift",
            "Components/SpaceSidebarContent/SpaceHeader/SpaceHeaderActionsMenu.swift",
            "Components/SpaceSidebarContent/SidebarTabList/SidebarTabList.swift",
            "Components/SpaceSidebarContent/SidebarTabList/BrowserSidebarBackgroundInteractionView.swift",
            "Components/SpaceSidebarContent/SidebarTabList/DropSections/PinnedTabsDropSection.swift",
            "Components/SpaceSidebarContent/SidebarTabList/DropSections/SavedTabsDropSection.swift",
            "Components/SpaceSidebarContent/SidebarTabList/DropSections/CurrentTabsDropSection.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((FAMILY_ROOT / relative_path).is_file())

        for obsolete_bucket in ("Infrastructure", "Metrics", "Previews"):
            self.assertFalse((FAMILY_ROOT / obsolete_bucket).exists())

    def test_root_file_owns_only_the_root_view(self) -> None:
        source = ROOT_VIEW.read_text()
        declarations = re.findall(
            r"^(?:@[A-Za-z0-9_() ,.]+\n)*(?:(?:public|internal|private|fileprivate) )?"
            r"(?:struct|class|enum|actor|protocol|extension)\s+([A-Za-z0-9_]+)",
            source,
            flags=re.MULTILINE,
        )

        self.assertEqual(declarations, ["BrowserSidebar"])
        production_source = source.split("#Preview", maxsplit=1)[0]
        self.assertLessEqual(len(production_source.splitlines()), 260)
        self.assertIn("#Preview", source)
        for extracted_type in (
            "SpaceSidebarContent",
            "SidebarNavigationControls",
            "SpaceHeader",
            "SidebarTabList",
            "PinnedTabsDropSection",
            "SavedTabsDropSection",
            "CurrentTabsDropSection",
        ):
            self.assertNotIn(f"struct {extracted_type}", source)

    def test_sidebar_hover_rows_use_the_shared_hover_decorator(self) -> None:
        sources = (
            SIDEBAR_ROOT / "Components/NewTabRow.swift",
            SIDEBAR_ROOT
            / "SavedFolderGroup/Components/SavedFolderHeader.swift",
            FAMILY_ROOT
            / "Components/SpaceSidebarContent/SpaceHeader/SpaceHeader.swift",
        )

        for source_path in sources:
            source = source_path.read_text()
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertIn(".crestHoverSurface(", source)
                self.assertNotIn(".onHover", source)
                self.assertNotIn("@State private var isHovering", source)

    def test_utility_content_only_prepares_for_the_selected_space(self) -> None:
        source = (
            FAMILY_ROOT
            / "Components/SpaceSidebarContent/SpaceSidebarContent.swift"
        ).read_text()

        self.assertIn("if isSelected", source)
        self.assertIn("SpaceSidebarUtilityContent(", source)
        self.assertNotIn("let tabSections = space.tabSections", source)
        self.assertIn("tabSections: space.tabSections", source)

    def test_repeated_tab_operations_are_owned_by_a_sidebar_model(self) -> None:
        actions = (FAMILY_ROOT / "Models/BrowserSidebarTabActions.swift").read_text()
        self.assertIn("func pullNewIcon(for tabID: TabID)", actions)
        self.assertIn("func restoreSavedLocation(for tabID: TabID)", actions)

        drop_sections = FAMILY_ROOT / (
            "Components/SpaceSidebarContent/SidebarTabList/DropSections"
        )
        for source_path in drop_sections.glob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source=source_path.name):
                self.assertNotIn("private func pullNewIcon", source)
                self.assertNotIn("private func restoreSavedLocation", source)

    def test_utility_operations_are_outside_the_root_view(self) -> None:
        root_source = ROOT_VIEW.read_text()
        coordinator = (
            FAMILY_ROOT / "Services/BrowserSidebarUtilityCoordinator.swift"
        ).read_text()

        self.assertNotIn("import AppKit", root_source)
        self.assertNotIn("NSWorkspace.shared", root_source)
        self.assertIn("NSWorkspace.shared.activateFileViewerSelecting", coordinator)
        self.assertIn("var actions: BrowserUtilityListActions", coordinator)

    def test_root_preview_uses_only_the_isolated_sidebar_graph(self) -> None:
        fixture = (FAMILY_ROOT / "Support/BrowserSidebarPreviewFixture.swift").read_text()
        previews = ROOT_VIEW.read_text().split("#Preview", maxsplit=1)[1]

        self.assertIn("browsingMode: .privateBrowsing", fixture)
        self.assertIn("usesEphemeralWebsiteDataStores: true", fixture)
        self.assertIn("BrowserSidebarPreviewAuthenticator()", fixture)
        self.assertNotIn("BrowserSpaceAccessController()", previews)

    def test_clear_history_keeps_the_presented_space_identity(self) -> None:
        root_source = ROOT_VIEW.read_text()
        space_page = (
            FAMILY_ROOT
            / "Components/BrowserSidebarLoadedContent/BrowserSidebarSpacePage.swift"
        ).read_text()

        self.assertIn(
            "clearHistory: { actions.confirmClearHistory(space) }",
            space_page,
        )
        self.assertIn(
            "BrowserSidebarSpacePresentationPolicy.clearHistory(",
            root_source,
        )
        policy = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Sidebar/Support/BrowserSidebarSpacePresentationPolicy.swift"
        ).read_text()
        self.assertIn("selectedUnlockedSpace(", policy)
        self.assertIn("browser.clearHistory(matching: confirmation.assignment)", policy)
        self.assertIn("clearHistoryConfirmationIsLive", root_source)

    def test_sidebar_layout_values_are_named_and_platform_owned(self) -> None:
        metrics = (FAMILY_ROOT / "Support/BrowserSidebarMetrics.swift").read_text()
        for metric in (
            "lockedSpaceBlurRadius",
            "navigationControlSpacing",
            "reloadMenuControlWidth",
            "pinnedEmptyDropHeight",
            "spaceHeaderIconSize",
        ):
            self.assertIn(f"static let {metric}", metrics)

        for source_path in FAMILY_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

    def test_visual_previews_use_safe_deterministic_fixtures(self) -> None:
        fixture = (FAMILY_ROOT / "Support/BrowserSidebarPreviewFixture.swift").read_text()
        previewed_paths = (
            ROOT_VIEW,
            FAMILY_ROOT / "Components/BrowserSidebarLoadedContent/BrowserSidebarLoadedContent.swift",
            FAMILY_ROOT / "Components/BrowserSidebarLoadedContent/BrowserSidebarSpacePage.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SpaceSidebarContent.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SpaceSidebarBrowsingContent.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SpaceSidebarUtilityContent.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SidebarNavigationControls/SidebarNavigationControls.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SidebarNavigationControls/BrowserNavigationHistoryMenu.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SpaceHeader/SpaceHeader.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SpaceHeader/SpaceHeaderActionsMenu.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SidebarTabList/SidebarTabList.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SidebarTabList/BrowserSidebarBackgroundInteractionView.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SidebarTabList/DropSections/SavedTabsDropSection.swift",
            FAMILY_ROOT / "Components/SpaceSidebarContent/SidebarTabList/DropSections/CurrentTabsDropSection.swift",
        )
        for source_path in previewed_paths:
            source = source_path.read_text()
            expected_type = source_path.stem
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("#Preview", source)
                self.assertRegex(
                    source,
                    rf"#Preview[\s\S]*\b{re.escape(expected_type)}\s*\(",
                )
                self.assertNotIn("BrowserStore.production", source)
                self.assertNotIn("UserDefaults.standard", source)

        self.assertRegex(fixture, r"UUID\s*\(\s*uuid\s*:")
        self.assertNotIn("UUID()", fixture)
        self.assertNotIn("URL(string:", fixture)
        self.assertNotIn(".now", fixture)
        self.assertNotRegex(fixture, r"[A-Za-z0-9_\)\]\}]!")

    def test_family_has_zero_debt_and_exact_repository_total(self) -> None:
        payload = json.loads(
            (REPOSITORY_ROOT / "Config/VerticalStructureDebt.json").read_text()
        )
        violations = [
            (rule, entry)
            for rule, details in payload["rules"].items()
            for entry in details["violations"]
        ]
        self.assertFalse(
            [
                violation
                for violation in violations
                if violation[1][0].startswith(
                    "CrestMac/Features/Sidebar/BrowserSidebar"
                )
            ]
        )
        self.assertEqual(len(violations), 0)


if __name__ == "__main__":
    unittest.main()
