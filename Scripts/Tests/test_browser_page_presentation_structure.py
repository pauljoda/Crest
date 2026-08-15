#!/usr/bin/env python3
"""Structural ownership contract for shared browser-page presentation."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserPagePresentation"
MAC_DETAIL = REPOSITORY_ROOT / "CrestMac/Features/Browser/BrowserDetailView.swift"
MAC_DETAIL_CONTENT = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Browser/Components/BrowserDetailContent/BrowserDetailContent.swift"
)
MOBILE_DETAIL = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Browser/MobileBrowserRootView/Components/MobileBrowserDetailView.swift"
)
MOBILE_COMPACT_TOOLBAR = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Browser/MobileBrowserRootView/Components/"
    "MobileCompactPageToolbar.swift"
)
MOBILE_HISTORY_CONTROLS = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Browser/MobileBrowserRootView/Components/"
    "MobilePageHistoryControls.swift"
)
MOBILE_PAGE_ACTION_PORT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Chrome/Components/MobilePageActions/Services/"
    "MobileSelectedPageActionPort.swift"
)
MOBILE_REGULAR_NAVIGATION = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Sidebar/MobileBrowserSidebar/Components/Navigation/"
    "MobileSidebarNavigationControls.swift"
)
MOBILE_REGULAR_ADDRESS = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Sidebar/MobileBrowserSidebar/Components/"
    "MobileSidebarAddressField.swift"
)
MOBILE_SIDEBAR = (
    REPOSITORY_ROOT / "CrestMobile/Features/Sidebar/MobileBrowserSidebar.swift"
)
MOBILE_SIDEBAR_TOP_CHROME = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Sidebar/MobileBrowserSidebar/Components/"
    "MobileBrowserSidebarContent/Components/MobileBrowserSidebarTopChrome.swift"
)
MOBILE_ROOT_VIEW = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Browser/MobileBrowserRootView/MobileBrowserRootView.swift"
)
MOBILE_ROOT_SELECTION = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Browser/MobileBrowserRootView/Models/"
    "MobileBrowserRootModel/MobileBrowserRootModel+Selection.swift"
)
MOBILE_PAGE_ACTION_CONTENT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Chrome/Components/MobilePageActions/Components/"
    "MobilePageActionsContent.swift"
)
MOBILE_CONTENT_BLOCKING_ACTION = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Chrome/Components/MobilePageActions/Services/"
    "MobileContentBlockingAction.swift"
)
MOBILE_NAVIGATION_TESTS = (
    REPOSITORY_ROOT / "CrestMobileTests/MobileBrowserNavigationTests.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserPagePresentationStructureTests(unittest.TestCase):
    def test_domain_family_uses_one_matching_owner_per_file(self) -> None:
        required_files = (
            "Models/BrowserPagePresentation.swift",
            "Models/BrowserPagePresentationInput.swift",
            "Models/BrowserPagePresentationSelection.swift",
            "Models/BrowserPageUnloadedBehavior.swift",
            "Policies/BrowserPagePresentationPolicy.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((DOMAIN_ROOT / relative_path).is_file())

        for source_path in DOMAIN_ROOT.rglob("*.swift"):
            declarations = DECLARATION_PATTERN.findall(source_path.read_text())
            with self.subTest(path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, [source_path.stem])

    def test_domain_presentation_is_framework_and_page_adapter_neutral(self) -> None:
        forbidden_imports = ("AppKit", "SwiftUI", "UIKit", "WebKit")
        forbidden_page_types = re.compile(r"\b(?:BrowserPage|MobileBrowserPage)\b")

        for source_path in DOMAIN_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(path=source_path.relative_to(REPOSITORY_ROOT)):
                for module in forbidden_imports:
                    self.assertNotIn(f"import {module}", source)
                self.assertIsNone(forbidden_page_types.search(source))

    def test_platform_details_consume_the_shared_exhaustive_route(self) -> None:
        for source_path in (MAC_DETAIL, MOBILE_DETAIL):
            source = source_path.read_text()
            with self.subTest(path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("BrowserPagePresentationPolicy.resolve(", source)

        for source_path in (MAC_DETAIL_CONTENT, MOBILE_DETAIL):
            source = source_path.read_text()
            with self.subTest(path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("switch pagePresentation", source)

        mac_source = MAC_DETAIL.read_text()
        self.assertNotIn("if let tab = browser.selectedTab", mac_source)
        self.assertNotIn("else if pages.activeTabID == tab.id", mac_source)

        mobile_source = MOBILE_DETAIL.read_text()
        self.assertNotIn("else if let page = pages.activePage", mobile_source)
        self.assertNotIn("MobileUnloadedTabPresentationPolicy.showsPlaceholder", mobile_source)
        self.assertNotIn("MobileUnloadedTabPresentationPolicy.restoresAutomatically", mobile_source)

    def test_every_production_consumer_uses_the_domain_policy(self) -> None:
        consumers = []
        for source_root in (
            REPOSITORY_ROOT / "CrestMac",
            REPOSITORY_ROOT / "CrestMobile",
        ):
            for source_path in source_root.rglob("*.swift"):
                if "BrowserPagePresentation" in source_path.read_text():
                    consumers.append(source_path.relative_to(REPOSITORY_ROOT).as_posix())

        self.assertEqual(
            sorted(consumers),
            sorted(
                (
                    "CrestMac/Features/Browser/BrowserDetailView.swift",
                    "CrestMac/Features/Browser/Components/BrowserDetailContent/"
                    "BrowserDetailContent.swift",
                    "CrestMac/Features/Browser/Components/BrowserWebContentView.swift",
                    "CrestMac/Features/Browser/Components/BrowserWebPageSurface/"
                    "BrowserWebPageSurface.swift",
                    "CrestMac/Features/Browser/Components/BrowserWebPageSurface/"
                    "Components/BrowserWebPageFailureOverlay.swift",
                    "CrestMobile/Features/Browser/MobileBrowserRootView/Components/"
                    "MobileBrowserDetailView.swift",
                )
            ),
        )

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Features/Browser/MobileBrowserRootView/Policies/"
                "MobileUnloadedTabPresentationPolicy.swift"
            ).exists()
        )

    def test_page_chrome_cannot_bypass_the_selected_assignment(self) -> None:
        toolbar_source = MOBILE_COMPACT_TOOLBAR.read_text()
        history_source = MOBILE_HISTORY_CONTROLS.read_text()
        port_source = MOBILE_PAGE_ACTION_PORT.read_text()

        self.assertNotIn("let pages: MobileBrowserPageStore", toolbar_source)
        self.assertNotIn("pages.activePage", toolbar_source)
        self.assertNotIn("pages.activePage", history_source)
        self.assertIn("let pageActions: MobileSelectedPageActionPort?", toolbar_source)
        self.assertIn("pageActions.isAvailable", history_source)

        for assignment_field in ("tabID", "spaceID", "profileID"):
            with self.subTest(assignment_field=assignment_field):
                self.assertIn(
                    f"page.{assignment_field} == expectedAssignment.{assignment_field}",
                    port_source,
                )
        self.assertIn("tab.id == expectedAssignment.tabID", port_source)
        self.assertIn("space.id == expectedAssignment.spaceID", port_source)
        self.assertIn("space.profile.id == expectedAssignment.profileID", port_source)
        reconciliation = port_source.split(
            "func reconcileContentBlocking(in session: BrowserSession) async {",
            maxsplit=1,
        )[1].split("\n    }", maxsplit=1)[0]
        self.assertNotIn("isAvailable", reconciliation)
        self.assertIn("pages.reconcileContentBlocking(in: session)", reconciliation)

        regular_navigation = MOBILE_REGULAR_NAVIGATION.read_text()
        regular_address = MOBILE_REGULAR_ADDRESS.read_text()
        sidebar = MOBILE_SIDEBAR.read_text()
        for source in (regular_navigation, regular_address):
            self.assertNotIn("let pages: MobileBrowserPageStore", source)
            self.assertIn("(any MobilePageActions)?", source)
        self.assertNotIn("progress: pages.activePage", sidebar)
        self.assertNotIn("pages.activePage?.url", sidebar)
        top_chrome = MOBILE_SIDEBAR_TOP_CHROME.read_text()
        self.assertIn("MobileSelectedPageActionPort(", top_chrome)
        self.assertIn("selectedPageActions?.activeURL", top_chrome)

        root_view = MOBILE_ROOT_VIEW.read_text()
        root_selection = MOBILE_ROOT_SELECTION.read_text()
        self.assertNotIn("pages.activePage", root_view)
        self.assertIn("var selectedPageActions: MobileSelectedPageActionPort?", root_selection)
        self.assertIn("selectedPageActions?.activePage", root_selection)

    def test_content_blocking_workflow_owns_mutation_and_snapshot_reconciliation(self) -> None:
        content = MOBILE_PAGE_ACTION_CONTENT.read_text()
        action = MOBILE_CONTENT_BLOCKING_ACTION.read_text()

        self.assertNotIn("browser.updateBrowsingPreferences", content)
        self.assertIn("Task { await contentBlockingAction.perform() }", content)
        self.assertNotIn("Task {", action)
        self.assertIn("tab.id == assignment.tabID", action)
        self.assertIn("space.id == assignment.spaceID", action)
        self.assertIn("space.profile.id == assignment.profileID", action)
        self.assertIn("let committedSession = browser.session", action)
        self.assertIn("await reconcile(committedSession)", action)

    def test_selected_mobile_page_store_fixtures_declare_safe_storage(self) -> None:
        source = MOBILE_NAVIGATION_TESTS.read_text()
        constructor_count = source.count("MobileBrowserPageStore(")
        constructor_arguments = re.findall(
            r"MobileBrowserPageStore\(\n(.*?)(?=^ {8}\))",
            source,
            flags=re.DOTALL | re.MULTILINE,
        )

        self.assertEqual(len(constructor_arguments), constructor_count)
        for arguments in constructor_arguments:
            self.assertIn("usesEphemeralWebsiteDataStores:", arguments)

        persistent_behavior_fixtures = [
            arguments
            for arguments in constructor_arguments
            if "usesEphemeralWebsiteDataStores: false" in arguments
        ]
        self.assertEqual(len(persistent_behavior_fixtures), 3)
        for arguments in persistent_behavior_fixtures:
            self.assertIn("websiteDataStoreRemover: remover", arguments)
            self.assertNotIn(".production()", arguments)

        self.assertIn(
            "let secondaryPages = MobileBrowserPageStore(\n"
            "            usesEphemeralWebsiteDataStores: true,",
            source,
        )
        self.assertIn(
            "profile: BrowsingProfile(id: fixedUUID(index * 10 + 3))",
            source,
        )
        self.assertNotIn("BrowserWebsiteDataStore.persistent(", source)
        self.assertGreaterEqual(
            source.count(".isPersistent"),
            5,
            "Every non-ephemeral behavior fixture must prove its launch-scoped store is nonpersistent.",
        )


if __name__ == "__main__":
    unittest.main()
