#!/usr/bin/env python3
"""Vertical composition and preview contracts for the mobile Sidebar."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Sidebar"
ROOT_VIEW = SIDEBAR_ROOT / "MobileBrowserSidebar.swift"
FAMILY_ROOT = SIDEBAR_ROOT / "MobileBrowserSidebar"
CHROME_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Chrome/Components"
DOWNLOADS_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Downloads"
PREVIEW_ROOT = REPOSITORY_ROOT / "CrestMobile/PreviewSupport"
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class MobileBrowserSidebarLayoutTests(unittest.TestCase):
    def test_sidebar_root_only_owns_and_composes_the_root_view(self) -> None:
        source = ROOT_VIEW.read_text()

        self.assertEqual(DECLARATION_PATTERN.findall(source), ["MobileBrowserSidebar"])
        self.assertIn("MobileBrowserSidebarPresentation(", source)
        self.assertIn("MobileBrowserSidebarContent(", source)
        self.assertNotRegex(source, r"private\s+var\s+\w+\s*:\s*some\s+View")
        self.assertNotIn("@ViewBuilder", source)
        for state in (
            "showsPasswords",
            "showsSettings",
            "presentedSpaceSheet",
            "pendingPageSelection",
            "utilitySearchText",
            "utilityFilter",
            "clearHistoryConfirmation",
        ):
            self.assertIn(f"@State private var {state}", source)

    def test_sidebar_uses_vertical_component_ownership(self) -> None:
        required = {
            FAMILY_ROOT / "Models/MobileBrowserSidebarContentConfiguration.swift",
            FAMILY_ROOT / "Models/MobileBrowserSidebarPresentationConfiguration.swift",
            FAMILY_ROOT / "Components/MobileBrowserSidebarPresentation.swift",
            FAMILY_ROOT / "Components/MobileBrowserSidebarContent/MobileBrowserSidebarContent.swift",
            FAMILY_ROOT / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarPager.swift",
            FAMILY_ROOT / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarTopChrome.swift",
            FAMILY_ROOT / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarBottomChrome.swift",
            FAMILY_ROOT / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarSpaceSurface.swift",
            FAMILY_ROOT / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarSpaceContent.swift",
            FAMILY_ROOT / "Components/MobileSpaceActions/MobileSpaceActions.swift",
            FAMILY_ROOT / "Components/MobileSpaceActions/Components/MobileSpaceArchiveButton.swift",
            FAMILY_ROOT / "Components/MobileSpaceActions/Components/MobileSpaceDownloadsButton.swift",
            FAMILY_ROOT / "Components/MobileSpaceActions/Components/MobileSpacePrivateBrowsingButton.swift",
            FAMILY_ROOT / "Components/MobileSpaceActions/Components/MobileSpaceSettingsButton.swift",
            FAMILY_ROOT / "Components/SavedFolders/Components/MobileSavedFolderHeader/MobileSavedFolderHeader.swift",
            FAMILY_ROOT / "Components/TabSections/Components/MobileCurrentTabsEndDropTarget.swift",
            FAMILY_ROOT / "Components/TabSections/Components/MobileSavedTabsEndDropTarget.swift",
            FAMILY_ROOT / "Components/Tabs/Components/MobileSidebarTabActivationButton.swift",
            FAMILY_ROOT / "Support/MobileBrowserSidebarBackdropStyle.swift",
            FAMILY_ROOT / "Support/MobileBrowserSidebarPreviewFixture.swift",
            CHROME_ROOT / "MobileCompactAddressBar/MobileCompactAddressBar.swift",
            CHROME_ROOT / "MobilePageActions/Components/MobilePageActionsContent.swift",
            CHROME_ROOT / "MobilePageActions/Services/MobilePageActions.swift",
            CHROME_ROOT / "MobileNavigationHistoryMenu.swift",
            DOWNLOADS_ROOT / "MobileDownloadsView.swift",
            DOWNLOADS_ROOT / "Components/MobileDownloadsContent.swift",
        }
        for path in sorted(required):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        removed = {
            FAMILY_ROOT / "Policies",
            FAMILY_ROOT / "Gestures",
            FAMILY_ROOT / "Previews",
            FAMILY_ROOT / "Components/MobileCompactAddressBar",
            FAMILY_ROOT / "Components/PageActions",
            FAMILY_ROOT / "Components/MobileDownloadsView.swift",
            FAMILY_ROOT / "Components/MobileSpaceActions.swift",
        }
        for path in sorted(removed):
            with self.subTest(removed=path.relative_to(REPOSITORY_ROOT)):
                self.assertFalse(path.exists())

    def test_visual_composition_preserves_exact_assignment_boundaries(self) -> None:
        root = ROOT_VIEW.read_text()
        pager = (
            FAMILY_ROOT
            / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarPager.swift"
        ).read_text()
        top_chrome = (
            FAMILY_ROOT
            / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarTopChrome.swift"
        ).read_text()
        bottom_chrome = (
            FAMILY_ROOT
            / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarBottomChrome.swift"
        ).read_text()
        space_surface = (
            FAMILY_ROOT
            / "Components/MobileBrowserSidebarContent/Components/MobileBrowserSidebarSpaceSurface.swift"
        ).read_text()
        folder = (
            FAMILY_ROOT / "Components/SavedFolders/MobileSavedFolderGroup.swift"
        ).read_text()
        actions = (
            FAMILY_ROOT / "Components/MobileSpaceActions/MobileSpaceActions.swift"
        ).read_text()

        self.assertIn("BrowserSpaceRuntimeAssignment", root)
        self.assertIn("canSettlePageSelection", root)
        self.assertIn("BrowserSpacePager(", pager)
        self.assertIn("BrowserSidebarAccessPolicy.availableSpaces", pager)
        self.assertIn("MobileSelectedPageActionPort(", top_chrome)
        self.assertNotIn("configuration.pages.activePage", top_chrome)
        self.assertIn("case .reservedSpace:", bottom_chrome)
        self.assertIn(".frame(height: 60)", bottom_chrome)
        for contract in (
            ".blur(radius: isLocked ? 12 : 0)",
            ".redacted(reason: isLocked ? .placeholder : [])",
            ".allowsHitTesting(!isLocked)",
            "browser.space(matching: assignment)",
        ):
            self.assertIn(contract, space_surface)
        self.assertIn("@Binding var editingFolderRequest", folder)
        self.assertIn("clearUnavailableDeferredActions", folder)
        self.assertRegex(
            folder,
            r"contextMenuDidOpen[\s\S]*?spaceID: spaceID,[\s\S]*?profileID: profileID",
        )
        self.assertRegex(
            folder,
            r"contextMenuDidClose[\s\S]*?spaceID: spaceID,[\s\S]*?profileID: profileID",
        )
        for component in (
            "MobileSpacePrivateBrowsingButton(",
            "MobileSpaceArchiveButton(",
            "MobileSpaceDownloadsButton(",
            "MobileSpaceSettingsButton(",
        ):
            self.assertIn(component, actions)

    def test_tab_sections_prepare_following_ids_once(self) -> None:
        sources = (
            FAMILY_ROOT / "Components/TabSections/MobileCurrentTabsDropSection.swift",
            FAMILY_ROOT / "Components/TabSections/MobileSavedTabsDropSection.swift",
            FAMILY_ROOT / "Components/SavedFolders/MobileSavedFolderGroup.swift",
        )

        for source_path in sources:
            source = source_path.read_text()
            with self.subTest(source=source_path.name):
                self.assertIn("followingTabIDs", source)
                self.assertNotIn("followingTabID(\n", source)

    def test_sidebar_visual_owners_have_direct_deterministic_previews(self) -> None:
        visual_files = [ROOT_VIEW]
        visual_files.extend(FAMILY_ROOT.rglob("*.swift"))
        visual_files.extend(DOWNLOADS_ROOT.rglob("*.swift"))
        visual_files.extend(
            (CHROME_ROOT / "MobileCompactAddressBar").rglob("*.swift")
        )
        visual_files.extend((CHROME_ROOT / "MobilePageActions").rglob("*.swift"))
        visual_files.append(CHROME_ROOT / "MobileNavigationHistoryMenu.swift")

        for path in sorted(set(visual_files)):
            source = path.read_text()
            declarations = DECLARATION_PATTERN.findall(source)
            is_visual = re.search(r":\s*(?:View|ViewModifier)\b", source)
            if not declarations or not is_visual:
                continue
            owner = declarations[0]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("#Preview", source)
                preview = source[source.index("#Preview"):]
                self.assertIn(f"{owner}(", preview)
                self.assertNotIn("BrowserStore.preview()", preview)
                self.assertNotIn("BrowserSession.preview", preview)
                self.assertNotIn("UUID()", preview)
                self.assertNotIn(".now", preview)
                self.assertNotIn("UserDefaults", preview)
                self.assertNotIn("WKWebsiteDataStore.default", preview)
                self.assertNotIn("pages.select(session:", preview)
                self.assertNotIn("MobileBrowserPage(", preview)
                self.assertNotIn("WKWebView(", preview)

    def test_sidebar_preview_fixtures_use_fixed_local_isolated_data(self) -> None:
        sidebar_fixture = (
            FAMILY_ROOT / "Support/MobileBrowserSidebarPreviewFixture.swift"
        ).read_text()
        global_fixture = (
            PREVIEW_ROOT / "MobileBrowserPreviewFixture.swift"
        ).read_text()
        page_actions_stub = (
            CHROME_ROOT
            / "MobilePageActions/Support/MobilePageActionsPreviewStub.swift"
        ).read_text()

        self.assertRegex(sidebar_fixture, r"UUID\(\s*uuid:")
        self.assertIn("Date(timeIntervalSince1970: 0)", sidebar_fixture)
        self.assertIn("URL(filePath:", sidebar_fixture)
        self.assertIn("InMemoryBrowserSessionPersistence()", sidebar_fixture)
        self.assertIn("browsingMode: .privateBrowsing", sidebar_fixture)
        for forbidden in (
            "BrowserSession.preview",
            "BrowserStore.preview()",
            "UUID()",
            ".now",
            "https://",
            "http://",
            "UserDefaults",
            "FileManager",
            "URLSession",
        ):
            self.assertNotIn(forbidden, sidebar_fixture)

        self.assertIn("browsingMode: .privateBrowsing", global_fixture)
        self.assertIn("usesEphemeralWebsiteDataStores: true", global_fixture)
        self.assertIn("InMemoryBrowserSessionPersistence()", global_fixture)
        self.assertIn("ruleListStore: nil", global_fixture)
        self.assertIn("defaults: nil", global_fixture)
        self.assertNotIn("Extension", global_fixture)
        self.assertNotIn("UserDefaults", global_fixture)
        self.assertNotIn("FileManager", global_fixture)
        self.assertFalse(
            (PREVIEW_ROOT / "MobileBrowserPreviewExtensionPackageStore.swift").exists()
        )
        self.assertIn("var isAvailable: Bool { true }", page_actions_stub)
        self.assertIn("var activePage: MobileBrowserPage? { nil }", page_actions_stub)
        self.assertIn("URL(filePath:", page_actions_stub)


if __name__ == "__main__":
    unittest.main()
