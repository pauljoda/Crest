#!/usr/bin/env python3
"""Vertical structure and behavior seams for BrowserUtilityListContent."""

from __future__ import annotations

from pathlib import Path
import re
import runpy
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
UTILITY_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Utilities"
ROOT_VIEW = UTILITY_ROOT / "BrowserUtilityListContent.swift"
FAMILY_ROOT = UTILITY_ROOT / "BrowserUtilityListContent"
OLD_ROOT_VIEW = UTILITY_ROOT / "BrowserUtilityListView.swift"
OLD_FAMILY_ROOT = UTILITY_ROOT / "BrowserUtilityListView"
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

EXPECTED_FAMILY_SOURCES = {
    "Components/BrowserDownloadRowAction/BrowserDownloadRowAction.swift",
    "Components/BrowserDownloadRowAction/Components/BrowserDownloadFinishedAction.swift",
    "Components/BrowserDownloadStatusIcon.swift",
    "Components/BrowserUtilityFanControl/BrowserUtilityFanControl.swift",
    "Components/BrowserUtilityFanControl/Components/BrowserUtilityFanDestinationButton.swift",
    "Components/BrowserUtilityFilterMenu.swift",
    "Components/BrowserUtilityListPresentation/BrowserUtilityListPresentation.swift",
    "Components/BrowserUtilityListPresentation/Components/BrowserUtilityListBlankState.swift",
    "Components/BrowserUtilityListPresentation/Components/BrowserUtilityListEmptyState.swift",
    "Components/BrowserUtilityListPresentation/Components/BrowserUtilityListSectionList.swift",
    "Components/BrowserUtilityListRow/BrowserUtilityListRow.swift",
    "Components/BrowserUtilityListRow/Components/BrowserUtilityListRowLabel.swift",
    "Components/BrowserUtilitySearchToolbar.swift",
    "Models/BrowserUtilityDownloadAction.swift",
    "Models/BrowserUtilityDownloadPreparationIdentity.swift",
    "Models/BrowserUtilityListEmptyPresentation.swift",
    "Models/BrowserUtilityListActions.swift",
    "Models/BrowserUtilityListItem.swift",
    "Models/BrowserUtilityListItemID.swift",
    "Models/BrowserUtilityListRequest.swift",
    "Models/BrowserUtilityListSection.swift",
    "Services/BrowserUtilityListPreparation.swift",
    "Services/BrowserUtilityListClock.swift",
    "Services/BrowserUtilityListReconciliation.swift",
    "Support/BrowserUtilityListPreviewFixture.swift",
    "Support/BrowserUtilitySwitcherLayout.swift",
}

EXPECTED_FAMILY_DIRECTORIES = {
    "Components",
    "Components/BrowserDownloadRowAction",
    "Components/BrowserDownloadRowAction/Components",
    "Components/BrowserUtilityFanControl",
    "Components/BrowserUtilityFanControl/Components",
    "Components/BrowserUtilityListPresentation",
    "Components/BrowserUtilityListPresentation/Components",
    "Components/BrowserUtilityListRow",
    "Components/BrowserUtilityListRow/Components",
    "Models",
    "Services",
    "Support",
}

VISUAL_SOURCES = {
    "BrowserUtilityListContent.swift": "BrowserUtilityListContent",
    "BrowserUtilityListContent/Components/BrowserDownloadRowAction/BrowserDownloadRowAction.swift": "BrowserDownloadRowAction",
    "BrowserUtilityListContent/Components/BrowserDownloadRowAction/Components/BrowserDownloadFinishedAction.swift": "BrowserDownloadFinishedAction",
    "BrowserUtilityListContent/Components/BrowserDownloadStatusIcon.swift": "BrowserDownloadStatusIcon",
    "BrowserUtilityListContent/Components/BrowserUtilityFanControl/BrowserUtilityFanControl.swift": "BrowserUtilityFanControl",
    "BrowserUtilityListContent/Components/BrowserUtilityFanControl/Components/BrowserUtilityFanDestinationButton.swift": "BrowserUtilityFanDestinationButton",
    "BrowserUtilityListContent/Components/BrowserUtilityFilterMenu.swift": "BrowserUtilityFilterMenu",
    "BrowserUtilityListContent/Components/BrowserUtilityListPresentation/BrowserUtilityListPresentation.swift": "BrowserUtilityListPresentation",
    "BrowserUtilityListContent/Components/BrowserUtilityListPresentation/Components/BrowserUtilityListBlankState.swift": "BrowserUtilityListBlankState",
    "BrowserUtilityListContent/Components/BrowserUtilityListPresentation/Components/BrowserUtilityListEmptyState.swift": "BrowserUtilityListEmptyState",
    "BrowserUtilityListContent/Components/BrowserUtilityListPresentation/Components/BrowserUtilityListSectionList.swift": "BrowserUtilityListSectionList",
    "BrowserUtilityListContent/Components/BrowserUtilityListRow/BrowserUtilityListRow.swift": "BrowserUtilityListRow",
    "BrowserUtilityListContent/Components/BrowserUtilityListRow/Components/BrowserUtilityListRowLabel.swift": "BrowserUtilityListRowLabel",
    "BrowserUtilityListContent/Components/BrowserUtilitySearchToolbar.swift": "BrowserUtilitySearchToolbar",
}

LIVE_PREVIEW_PATTERNS = (
    r"\bBrowserSession\.preview\b",
    r"\b(?:UserDefaults|AppStorage)\b",
    r"\bFileManager\b",
    r"\bFileHandle\b",
    r"\bURLSession\w*\b",
    r"\bAsyncImage\b",
    r"\bWKWebView\b",
    r"\bWKWebsiteDataStore\b",
    r"\bWKContentRuleListStore\b",
    r"\b(?:SecItem\w*|Keychain\w*)\b",
    r"\bBrowserStore\.production\b",
    r"\bBrowserWebsiteDataStore\.persistent\b",
    r"\bData\s*\(\s*contentsOf\s*:",
    r"\bUUID\s*\(\s*\)",
    r"\bDate\s*\(\s*\)",
    r"\.now\b",
    r"\.random(?:Element)?\s*\(",
    r"\.shuffled\s*\(",
)


class BrowserUtilityListLayoutTests(unittest.TestCase):
    def source(self, relative_path: str) -> str:
        path = UTILITY_ROOT / relative_path
        self.assertTrue(path.is_file(), relative_path)
        return path.read_text()

    def test_final_vertical_topology_is_exact_and_old_paths_are_absent(self) -> None:
        self.assertTrue(ROOT_VIEW.is_file())
        self.assertTrue(FAMILY_ROOT.is_dir())
        self.assertFalse(OLD_ROOT_VIEW.exists())
        self.assertFalse(OLD_FAMILY_ROOT.exists())
        self.assertFalse((FAMILY_ROOT / "Previews").exists())

        actual_sources = {
            str(path.relative_to(FAMILY_ROOT))
            for path in FAMILY_ROOT.rglob("*.swift")
        }
        self.assertEqual(actual_sources, EXPECTED_FAMILY_SOURCES)
        actual_directories = {
            str(path.relative_to(FAMILY_ROOT))
            for path in FAMILY_ROOT.rglob("*")
            if path.is_dir()
        }
        self.assertEqual(actual_directories, EXPECTED_FAMILY_DIRECTORIES)

    def test_every_source_owns_one_matching_file_scope_declaration(self) -> None:
        sources = [ROOT_VIEW, *sorted(FAMILY_ROOT.rglob("*.swift"))]
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_declarations = VERTICAL_GUARD["_top_level_global_content"]

        for path in sources:
            source = path.read_text()
            primaries = primary_declarations(source)
            extensions = extension_declarations(source)
            globals_ = global_declarations(source)
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(
                    len(primaries) + len(extensions) + len(globals_),
                    1,
                )
                self.assertEqual(extensions, [])
                self.assertEqual(globals_, [])
                self.assertEqual(len(primaries), 1)
                self.assertEqual(primaries[0].name, path.stem)

    def test_root_composes_the_presentation_component_and_owns_preparation(self) -> None:
        root = ROOT_VIEW.read_text()

        self.assertIn("struct BrowserUtilityListContent: View", root)
        self.assertIn("BrowserUtilityListPresentation(", root)
        self.assertIn("@State private var preparedRequest", root)
        self.assertIn("@State private var sections", root)
        self.assertIn(".task(id: request)", root)
        self.assertIn("refreshSections(for: request)", root)
        self.assertIn("Task.detached(priority: .userInitiated)", root)
        self.assertIn("transaction.disablesAnimations = true", root)
        self.assertNotIn("ContentUnavailableView(", root)
        self.assertNotIn("List {", root)
        self.assertNotIn("ForEach(sections)", root)
        self.assertNotRegex(root, r"@ViewBuilder\s+private")
        self.assertNotRegex(root, r"private\s+(?:var|func)\s+\w+[^\n]*some\s+View")

    def test_large_view_helpers_are_real_component_types(self) -> None:
        expected_composition = {
            "Components/BrowserDownloadRowAction/BrowserDownloadRowAction.swift": "BrowserDownloadFinishedAction(",
            "Components/BrowserUtilityFanControl/BrowserUtilityFanControl.swift": "BrowserUtilityFanDestinationButton(",
            "Components/BrowserUtilityListRow/BrowserUtilityListRow.swift": "BrowserUtilityListRowLabel(",
        }
        forbidden_helpers = {
            "Components/BrowserDownloadRowAction/BrowserDownloadRowAction.swift": "finishedAction",
            "Components/BrowserUtilityFanControl/BrowserUtilityFanControl.swift": "destinationButton(",
            "Components/BrowserUtilityListRow/BrowserUtilityListRow.swift": "rowLabel(",
        }

        for relative_path, invocation in expected_composition.items():
            source = (FAMILY_ROOT / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertIn(invocation, source)
                self.assertNotIn(forbidden_helpers[relative_path], source)

    def test_every_visual_owner_has_a_direct_colocated_preview(self) -> None:
        direct_preview_exists = VERTICAL_GUARD["_direct_preview_exists"]
        self.assertEqual(len(VISUAL_SOURCES), 14)
        for relative_path, owner in VISUAL_SOURCES.items():
            source = self.source(relative_path)
            with self.subTest(relative_path=relative_path, owner=owner):
                self.assertTrue(
                    direct_preview_exists(source, owner),
                    f"No colocated #Preview directly invokes {owner}",
                )

        for relative_path in (
            "BrowserUtilityListContent/Components/BrowserUtilityFilterMenu.swift",
            "BrowserUtilityListContent/Components/BrowserUtilitySearchToolbar.swift",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertIn("@Previewable @State", self.source(relative_path))

    def test_preview_fixture_is_fixed_non_http_and_has_no_live_dependencies(self) -> None:
        fixture = self.source(
            "BrowserUtilityListContent/Support/BrowserUtilityListPreviewFixture.swift"
        )
        preview_sources = fixture + "\n" + "\n".join(
            self.source(relative_path).split("#Preview", 1)[-1]
            for relative_path in VISUAL_SOURCES
        )

        self.assertIn("enum BrowserUtilityListPreviewFixture", fixture)
        self.assertIn("Date(timeIntervalSince", fixture)
        self.assertRegex(fixture, r"UUID\s*\(\s*uuid\s*:")
        self.assertIn("SpaceID(rawValue:", fixture)
        self.assertIn("BrowsingProfile(id:", fixture)
        self.assertRegex(
            fixture,
            r"(?:crest-preview://|URL\s*\(\s*file(?:Path|URLWithPath):)",
        )
        self.assertNotRegex(fixture, r"https?://")
        root_preview = self.source("BrowserUtilityListContent.swift").split(
            "#Preview", 1
        )[-1]
        self.assertIn(
            "preparationClock: .fixed(",
            root_preview,
        )
        self.assertIn(
            "BrowserUtilityListPreviewFixture.referenceDate",
            root_preview,
        )
        self.assertIn(
            "preparationCalendar: BrowserUtilityListPreviewFixture.fixedCalendar",
            root_preview,
        )

        for pattern in LIVE_PREVIEW_PATTERNS:
            with self.subTest(pattern=pattern):
                self.assertNotRegex(preview_sources, pattern)

    def test_preparation_preserves_exact_space_profile_ownership_and_cancellation(self) -> None:
        root = ROOT_VIEW.read_text()
        request = self.source(
            "BrowserUtilityListContent/Models/BrowserUtilityListRequest.swift"
        )
        preparation = self.source(
            "BrowserUtilityListContent/Services/BrowserUtilityListPreparation.swift"
        )
        reconciliation = self.source(
            "BrowserUtilityListContent/Services/BrowserUtilityListReconciliation.swift"
        )

        self.assertIn("let assignment: BrowserSpaceRuntimeAssignment", request)
        self.assertIn(
            "assignment: BrowserSpaceRuntimeAssignment(space: space)",
            request,
        )
        self.assertIn("&& lhs.assignment == rhs.assignment", request)
        self.assertIn("surface == other.surface && assignment == other.assignment", request)
        self.assertIn("hasSamePresentationOwnership", root)
        self.assertIn(
            "private var preparedPresentationRequest: BrowserUtilityListRequest?",
            root,
        )
        self.assertIn("presentationRequest: preparedPresentationRequest", root)
        self.assertIn("space: space", root)
        self.assertNotIn("preparedRequest != request", root)
        self.assertNotRegex(root + request, r"\b(?:firstIndex|enumerated)\b")
        self.assertIn("searchDebounce", root)
        self.assertIn("BrowserUtilityDownloadPreparationIdentity", request)
        self.assertIn("nonisolated static func sections", preparation)
        self.assertIn("nextRefreshDate", preparation)
        self.assertIn("Task.isCancelled", preparation)
        self.assertIn("item.profileID == assignment.profileID", reconciliation)
        self.assertIn("preparedSections.compactMap", reconciliation)
        self.assertIn("filter.normalized(for: .downloads)", reconciliation)

    def test_rows_forward_captured_exact_assignment_to_every_mutating_action(self) -> None:
        actions = self.source(
            "BrowserUtilityListContent/Models/BrowserUtilityListActions.swift"
        )
        presentation = self.source(
            "BrowserUtilityListContent/Components/BrowserUtilityListPresentation/BrowserUtilityListPresentation.swift"
        )
        section_list = self.source(
            "BrowserUtilityListContent/Components/BrowserUtilityListPresentation/Components/BrowserUtilityListSectionList.swift"
        )
        row = self.source(
            "BrowserUtilityListContent/Components/BrowserUtilityListRow/BrowserUtilityListRow.swift"
        )

        self.assertIn("assignment: presentationRequest.assignment", presentation)
        self.assertIn("let assignment: BrowserSpaceRuntimeAssignment", section_list)
        self.assertIn("assignment: assignment", section_list)
        self.assertGreaterEqual(
            actions.count("BrowserSpaceRuntimeAssignment"),
            3,
        )
        self.assertIn("let assignment: BrowserSpaceRuntimeAssignment", row)
        self.assertIn(
            "actions.restoreArchivedTab(archived.id, assignment)",
            row,
        )
        self.assertIn("actions.openHistoryEntry(entry, assignment)", row)
        self.assertIn("actions.performDownloadAction($0, assignment)", row)

    def test_list_item_identity_is_a_standalone_model(self) -> None:
        item = self.source(
            "BrowserUtilityListContent/Models/BrowserUtilityListItem.swift"
        )
        identity = self.source(
            "BrowserUtilityListContent/Models/BrowserUtilityListItemID.swift"
        )

        self.assertNotRegex(item, r"\benum\s+ID\b")
        self.assertIn("enum BrowserUtilityListItemID", identity)
        self.assertIn("var id: BrowserUtilityListItemID", item)

    def test_shared_utility_list_still_replaces_legacy_platform_views(self) -> None:
        for relative_path in (
            "CrestMac/Features/Archive/BrowserArchiveView.swift",
            "CrestMac/Features/History/BrowserHistoryView.swift",
        ):
            self.assertFalse((REPOSITORY_ROOT / relative_path).exists(), relative_path)

        consumers = (
            "CrestMac/Features/Sidebar/BrowserSidebar/Components/SpaceSidebarContent/SpaceSidebarUtilityContent.swift",
            "CrestMobile/Features/Archive/MobileArchiveView/Components/MobileArchiveList.swift",
            "CrestMobile/Features/History/MobileHistoryView/Components/MobileHistoryList.swift",
        )
        for relative_path in consumers:
            with self.subTest(relative_path=relative_path):
                source = (REPOSITORY_ROOT / relative_path).read_text()
                self.assertIn("BrowserUtilityListContent(", source)

    def test_platform_menu_styling_remains_explicit(self) -> None:
        shared_menu = self.source(
            "BrowserUtilityListContent/Components/BrowserUtilityFilterMenu.swift"
        )
        self.assertNotIn("#if os(", shared_menu)

        for relative_path in (
            "CrestMac/Features/Utilities/BrowserPlatformUtilityFilterMenuStyle.swift",
            "CrestMobile/Features/Utilities/BrowserPlatformUtilityFilterMenuStyle.swift",
        ):
            self.assertTrue((REPOSITORY_ROOT / relative_path).is_file(), relative_path)

    def test_rows_keep_the_shared_full_width_hover_surface(self) -> None:
        row = self.source(
            "BrowserUtilityListContent/Components/BrowserUtilityListRow/BrowserUtilityListRow.swift"
        )

        self.assertIn(".crestHoverSurface(", row)
        self.assertNotIn("@State private var isHovering", row)
        self.assertNotIn(".onHover", row)

    def test_time_section_period_remains_a_standalone_model(self) -> None:
        time_section = (UTILITY_ROOT / "Models/BrowserUtilityTimeSection.swift").read_text()
        period = UTILITY_ROOT / "Models/BrowserUtilityTimePeriod.swift"

        self.assertNotIn("private extension BrowserUtilityTimeSection", time_section)
        self.assertTrue(period.is_file())
        self.assertIn("enum BrowserUtilityTimePeriod", period.read_text())


if __name__ == "__main__":
    unittest.main()
