#!/usr/bin/env python3
"""Final vertical ownership and runtime-isolation contracts for pinned tabs."""

from __future__ import annotations

import pathlib
import runpy
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

SHARED_GRID_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Tabs/Components/PinnedTabGrid"
)
SHARED_SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Sidebar"
SHARED_SIDEBAR_SUPPORT_ROOT = SHARED_SIDEBAR_ROOT / "Support"
SHARED_DRAG_ROOT = (
    SHARED_SIDEBAR_ROOT / "Components/BrowserSidebarDrag"
)
SHARED_TAB_MENU_ROOT = (
    SHARED_SIDEBAR_ROOT / "Components/BrowserTabOrganizationMenu"
)
SHARED_FOLDER_MENU_ROOT = (
    SHARED_SIDEBAR_ROOT / "Components/BrowserFolderOrganizationMenu"
)
MAC_DRAG_ROOT = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Sidebar/Components/BrowserSidebarDrag"
)
MOBILE_DRAG_ROOT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Sidebar/Components/BrowserSidebarDrag"
)
MAC_MIDDLE_CLICK = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Tabs/Components/PinnedTabGrid/Support/View+BrowserPinnedTabMiddleClick.swift"
)
MOBILE_MIDDLE_CLICK = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Tabs/Components/PinnedTabGrid/Support/View+BrowserPinnedTabMiddleClick.swift"
)
MAC_PINNED_SECTION = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Sidebar/BrowserSidebar/Components/SpaceSidebarContent/SidebarTabList/DropSections/PinnedTabsDropSection.swift"
)
MOBILE_PINNED_SECTION = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Sidebar/MobileBrowserSidebar/Components/TabSections/MobilePinnedTabsDropSection.swift"
)
MAC_PINNED_PREVIEW_SUPPORT_ROOT = MAC_PINNED_SECTION.parent / "Support"

EXPECTED_GRID_FILES = (
    "PinnedTabGrid.swift",
    "Components/PinnedTabDragModifier.swift",
    "Components/PinnedTabInteractionSurface.swift",
    "Components/PinnedTabOrganizationMenu.swift",
    "Components/PinnedTabSelectionButton.swift",
    "Components/PinnedTabGridContent.swift",
    "Support/BrowserFaviconColor+Presentation.swift",
    "Support/BrowserPinnedDropTargetPolicy.swift",
    "Support/BrowserPinnedTabInteraction.swift",
    "Support/PinnedTabGridLayout.swift",
    "Support/PinnedTabGridPreviewAuthenticator.swift",
    "Support/PinnedTabGridPreviewFixture.swift",
    "Support/View+BrowserPinnedTabPromotionDestination.swift",
)

EXPECTED_SIDEBAR_PREVIEW_SUPPORT_FILES = (
    "BrowserSidebarInteractionPreviewAuthenticator.swift",
    "BrowserSidebarInteractionPreviewFixture.swift",
)

EXPECTED_MAC_PINNED_PREVIEW_SUPPORT_FILES = (
    "PinnedTabsDropSectionPreviewExtensionPackageStore.swift",
    "PinnedTabsDropSectionPreviewFixture.swift",
    "PinnedTabsDropSectionPreviewWebsiteDataStoreRemover.swift",
)

EXPECTED_SHARED_DRAG_FILES = (
    "Components/BrowserFolderDragPreview.swift",
    "Components/BrowserFolderDragSourceModifier.swift",
    "Components/BrowserFolderDropIndicator.swift",
    "Components/BrowserTabDragPreview.swift",
    "Components/BrowserTabDragSourceModifier.swift",
    "Components/BrowserTabDropIndicator.swift",
    "Models/BrowserDragSessionToken.swift",
    "Models/BrowserFolderDragItem.swift",
    "Models/BrowserFolderDropLocation.swift",
    "Models/BrowserTabDragItem.swift",
    "Models/BrowserTabDragPreviewMetrics.swift",
    "Models/BrowserTabDragSessionLifecyclePhase.swift",
    "Models/BrowserTabDropLocation.swift",
    "Services/BrowserFolderDragState.swift",
    "Services/BrowserSavedContentDropDelegate.swift",
    "Services/BrowserSpaceTabDropDelegate.swift",
    "Services/BrowserTabDragAction.swift",
    "Services/BrowserTabDragState.swift",
    "Services/BrowserTabLiveDropDelegate.swift",
    "Support/BrowserDragReleaseFallbackPolicy.swift",
    "Support/BrowserFolderDragPreviewLayout.swift",
    "Support/BrowserNativeDragSessionPolicy.swift",
    "Support/BrowserTabDragPreviewLayout.swift",
    "Support/BrowserTabDragPreviewUpdating.swift",
    "Support/BrowserTabDragSessionLifecyclePolicy.swift",
    "Support/BrowserTabDragSessionPolicy.swift",
    "Support/BrowserTabDragVisualPolicy.swift",
    "Support/BrowserTabDropBehavior.swift",
    "Support/BrowserTabDropIndicatorPolicy.swift",
    "Support/BrowserTabDropStabilityPolicy.swift",
    "Support/BrowserTabRowIndicatorOwnershipPolicy.swift",
    "Support/BrowserTabRowInsertionPolicy.swift",
    "Support/View+BrowserDragSources.swift",
)

EXPECTED_TAB_MENU_FILES = (
    "BrowserTabOrganizationMenu.swift",
    "Models/BrowserTabEmojiChoice.swift",
    "Support/BrowserTabEmojiChoices.swift",
)

EXPECTED_FOLDER_MENU_FILES = (
    "BrowserFolderOrganizationMenu.swift",
    "Models/BrowserFolderMoveDestination.swift",
)

EXPECTED_MAC_DRAG_FILES = (
    "Components/BrowserMacFolderDragGesture.swift",
    "Components/BrowserMacTabDragGesture.swift",
    "Components/BrowserPlatformFolderDragSourceModifier.swift",
    "Components/BrowserPlatformTabDragSourceModifier.swift",
    "Services/BrowserMacDragPreviewRenderer.swift",
    "Services/BrowserMacFolderDragGestureCoordinator.swift",
    "Services/BrowserMacNativeDraggingSession.swift",
    "Services/BrowserMacTabDragGestureCoordinator.swift",
    "Support/BrowserPlatformTabDragVisualPolicy.swift",
    "Support/BrowserPlatformTabDropExitPolicy.swift",
)

EXPECTED_MOBILE_DRAG_FILES = (
    "Components/BrowserPlatformFolderDragSourceModifier.swift",
    "Components/BrowserPlatformTabDragSourceModifier.swift",
    "Components/BrowserTabReactiveDragPreview.swift",
    "Support/BrowserPlatformTabDragVisualPolicy.swift",
    "Support/BrowserPlatformTabDropExitPolicy.swift",
)

LEGACY_ROOTS = (
    REPOSITORY_ROOT / "CrestShared/Features/Tabs/PinnedTabGrid",
    REPOSITORY_ROOT / "CrestMac/Features/Tabs/PinnedTabGrid",
    REPOSITORY_ROOT / "CrestMobile/Features/Tabs/PinnedTabGrid",
)


class PinnedTabGridStructureTests(unittest.TestCase):
    def assert_files_exist(
        self,
        root: pathlib.Path,
        relative_paths: tuple[str, ...],
    ) -> None:
        for relative_path in relative_paths:
            with self.subTest(
                root=root.relative_to(REPOSITORY_ROOT),
                relative_path=relative_path,
            ):
                self.assertTrue((root / relative_path).is_file())

    def slice_sources(self) -> list[pathlib.Path]:
        roots = (
            SHARED_GRID_ROOT,
            SHARED_DRAG_ROOT,
            SHARED_TAB_MENU_ROOT,
            SHARED_FOLDER_MENU_ROOT,
            MAC_DRAG_ROOT,
            MOBILE_DRAG_ROOT,
        )
        sources = {
            source
            for root in roots
            if root.is_dir()
            for source in root.rglob("*.swift")
        }
        sources.update(
            source
            for source in (
                SHARED_SIDEBAR_ROOT
                / "Components/BrowserTabSavedLocationIndicator.swift",
                MAC_MIDDLE_CLICK,
                MOBILE_MIDDLE_CLICK,
                MAC_PINNED_SECTION,
                MOBILE_PINNED_SECTION,
                *(SHARED_SIDEBAR_SUPPORT_ROOT / relative_path
                  for relative_path in EXPECTED_SIDEBAR_PREVIEW_SUPPORT_FILES),
                *(MAC_PINNED_PREVIEW_SUPPORT_ROOT / relative_path
                  for relative_path in EXPECTED_MAC_PINNED_PREVIEW_SUPPORT_FILES),
            )
            if source.is_file()
        )
        return sorted(sources)

    def assert_preview_fixture_is_isolated(self, path: pathlib.Path) -> None:
        source = path.read_text()
        patterns = (
            *VERTICAL_GUARD["LIVE_PREVIEW_PATTERNS"],
            *VERTICAL_GUARD["NONDETERMINISTIC_PREVIEW_PATTERNS"],
        )
        for subject, pattern in patterns:
            with self.subTest(path=path.name, subject=subject):
                self.assertIsNone(pattern.search(source))

    def test_final_vertical_topology_is_complete(self) -> None:
        self.assert_files_exist(SHARED_GRID_ROOT, EXPECTED_GRID_FILES)
        self.assert_files_exist(
            SHARED_SIDEBAR_SUPPORT_ROOT,
            EXPECTED_SIDEBAR_PREVIEW_SUPPORT_FILES,
        )
        self.assert_files_exist(
            MAC_PINNED_PREVIEW_SUPPORT_ROOT,
            EXPECTED_MAC_PINNED_PREVIEW_SUPPORT_FILES,
        )
        self.assert_files_exist(SHARED_DRAG_ROOT, EXPECTED_SHARED_DRAG_FILES)
        self.assert_files_exist(SHARED_TAB_MENU_ROOT, EXPECTED_TAB_MENU_FILES)
        self.assert_files_exist(
            SHARED_FOLDER_MENU_ROOT,
            EXPECTED_FOLDER_MENU_FILES,
        )
        self.assert_files_exist(MAC_DRAG_ROOT, EXPECTED_MAC_DRAG_FILES)
        self.assert_files_exist(MOBILE_DRAG_ROOT, EXPECTED_MOBILE_DRAG_FILES)

        for path in (
            SHARED_SIDEBAR_ROOT
            / "Components/BrowserTabSavedLocationIndicator.swift",
            MAC_MIDDLE_CLICK,
            MOBILE_MIDDLE_CLICK,
            MAC_PINNED_SECTION,
            MOBILE_PINNED_SECTION,
        ):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        self.assertFalse(
            (
                SHARED_DRAG_ROOT
                / "Support/BrowserSidebarDropPolicy.swift"
            ).exists(),
            "The unused test-only policy is not part of the final production family.",
        )

    def test_legacy_roots_and_aggregate_previews_are_absent(self) -> None:
        for root in LEGACY_ROOTS:
            with self.subTest(root=root.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(list(root.rglob("*.swift")), [])

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Features/Tabs/PinnedTabGrid.swift"
            ).exists()
        )
        for source in self.slice_sources():
            relative_path = source.relative_to(REPOSITORY_ROOT)
            with self.subTest(source=relative_path):
                self.assertNotIn("Previews", relative_path.parts)
                self.assertFalse(source.name.endswith("Previews.swift"))

    def test_each_swift_file_has_exactly_one_matching_file_scope_declaration(self) -> None:
        sources = self.slice_sources()
        self.assertGreater(len(sources), 60)

        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_declarations = VERTICAL_GUARD["_top_level_global_content"]
        for source_file in sources:
            source = source_file.read_text()
            primaries = primary_declarations(source)
            extensions = extension_declarations(source)
            globals_ = global_declarations(source)
            with self.subTest(source=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(
                    len(primaries) + len(extensions) + len(globals_),
                    1,
                )
                if "+" in source_file.stem:
                    self.assertEqual(primaries, [])
                    self.assertEqual(len(extensions), 1)
                    self.assertEqual(
                        extensions[0].target,
                        source_file.stem.split("+", maxsplit=1)[0],
                    )
                else:
                    self.assertEqual(len(primaries), 1)
                    self.assertEqual(primaries[0].name, source_file.stem)

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        direct_preview_exists = VERTICAL_GUARD["_direct_preview_exists"]

        preview_owner_count = 0
        for source_file in self.slice_sources():
            source = source_file.read_text()
            owners = [
                declaration.name
                for declaration in primary_declarations(source)
                if declaration.requires_preview
            ] + [
                declaration.target
                for declaration in extension_declarations(source)
                if declaration.requires_preview
            ]
            preview_owner_count += len(owners)
            for owner in owners:
                with self.subTest(
                    source=source_file.relative_to(REPOSITORY_ROOT),
                    owner=owner,
                ):
                    self.assertTrue(direct_preview_exists(source, owner))

        self.assertGreaterEqual(preview_owner_count, 18)
        fixtures = (
            SHARED_GRID_ROOT / "Support/PinnedTabGridPreviewFixture.swift",
            SHARED_SIDEBAR_SUPPORT_ROOT
            / "BrowserSidebarInteractionPreviewFixture.swift",
        )
        for fixture in fixtures:
            with self.subTest(fixture=fixture.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(fixture.is_file())
                fixture_source = fixture.read_text()
                self.assertRegex(fixture_source, r"UUID\(\s*uuid:\s*\(")
                self.assertIn("Date(timeIntervalSince1970:", fixture_source)
                self.assert_preview_fixture_is_isolated(fixture)

        pinned_section_fixture = (
            MAC_PINNED_PREVIEW_SUPPORT_ROOT
            / "PinnedTabsDropSectionPreviewFixture.swift"
        ).read_text()
        for required in (
            "browsingMode: .privateBrowsing",
            "usesEphemeralWebsiteDataStores: true",
            "usesEphemeralWebKitStorage: true",
            "InMemoryBrowserExtensionRegistryPersistence()",
            "InMemoryBrowserSitePermissionPersistence()",
            "defaults: nil",
            "ruleListStore: nil",
            "Date(timeIntervalSince1970:",
        ):
            self.assertIn(required, pinned_section_fixture)

    def test_slice_has_no_repository_vertical_structure_violations(self) -> None:
        owned_paths = {
            source.relative_to(REPOSITORY_ROOT).as_posix()
            for source in self.slice_sources()
        }
        violations = [
            violation.key
            for violation in VERTICAL_GUARD["scan_repository"](REPOSITORY_ROOT)
            if violation.path in owned_paths
        ]
        self.assertEqual(violations, [])

    def test_drag_payloads_and_space_drop_keep_exact_runtime_assignments(self) -> None:
        tab_item = (
            SHARED_DRAG_ROOT / "Models/BrowserTabDragItem.swift"
        ).read_text()
        folder_item = (
            SHARED_DRAG_ROOT / "Models/BrowserFolderDragItem.swift"
        ).read_text()
        action = (
            SHARED_DRAG_ROOT / "Services/BrowserTabDragAction.swift"
        ).read_text()
        space_drop = (
            SHARED_DRAG_ROOT / "Services/BrowserSpaceTabDropDelegate.swift"
        ).read_text()

        for source in (tab_item, folder_item):
            self.assertIn("let spaceID: SpaceID", source)
            self.assertIn("let profileID: UUID", source)
            self.assertIn("BrowserSpaceRuntimeAssignment", source)

        self.assertGreaterEqual(action.count("unlockedSpace("), 2)
        self.assertIn("matching: item.spaceAssignment", action)
        self.assertIn("matching: destination", action)
        self.assertIn("browser.moveTab(", action)
        self.assertIn("selectedUnlockedSpace(", action)

        self.assertIn(
            "let destination: BrowserSpaceRuntimeAssignment",
            space_drop,
        )
        self.assertNotIn("destinationSpaceID", space_drop)
        self.assertRegex(
            space_drop,
            r"validateDrop[\s\S]*?canMove\([\s\S]*?destination",
        )
        self.assertRegex(
            space_drop,
            r"dropEntered[\s\S]*?selectDestination\([\s\S]*?destination",
        )
        self.assertRegex(
            space_drop,
            r"performDrop[\s\S]*?(?:move|moveTab)\([\s\S]*?destination",
        )

        for picker_path in (
            REPOSITORY_ROOT
            / "CrestMac/Features/Sidebar/SpaceSwitcher/Components/SpacePickerSegment.swift",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Sidebar/MobileBrowserSidebar/Components/SpacePicker/MobileSpacePickerSegment.swift",
        ):
            picker = picker_path.read_text()
            with self.subTest(picker=picker_path.relative_to(REPOSITORY_ROOT)):
                self.assertIn(
                    "BrowserSpaceRuntimeAssignment(space: space)",
                    picker,
                )
                self.assertIn("BrowserTabDragAction(", picker)
                self.assertNotIn("destinationSpaceID:", picker)

    def test_deferred_tab_actions_re_resolve_the_exact_live_tab(self) -> None:
        menu_sources = [
            source.read_text()
            for source in sorted(SHARED_TAB_MENU_ROOT.rglob("*.swift"))
        ]
        menu = "\n".join(menu_sources)
        grid = "\n".join(
            source.read_text()
            for source in sorted(SHARED_GRID_ROOT.rglob("*.swift"))
        )

        self.assertNotIn("let canClose", menu)
        self.assertIn("BrowserTabRuntimeAssignment", menu)
        self.assertIn("if tab.placement == .current", menu)
        self.assertGreaterEqual(
            menu.count("expectedPlacement: tab.placement"),
            2,
        )
        self.assertNotIn("expectedPlacement: liveTab.placement", menu)
        self.assertRegex(
            menu,
            r"(?:private\s+)?func performIfCurrent\("
            r"[\s\S]*?\(BrowserTab\)\s*->\s*Void",
        )
        self.assertIn("selectedUnlockedSpace(", menu)
        self.assertIn("matching:", menu)

        self.assertIn("BrowserTabRuntimeAssignment", grid)
        self.assertIn("renamingAssignmentIsLive", grid)
        self.assertIn(".onChange(of: renamingAssignmentIsLive)", grid)
        self.assertIn("isCurrentAndUnlocked(renamingAssignment)", grid)
        self.assertIn("matching:", grid)

    def test_drag_completion_is_bound_to_a_session_token(self) -> None:
        token = (
            SHARED_DRAG_ROOT / "Models/BrowserDragSessionToken.swift"
        ).read_text()
        self.assertRegex(
            token,
            r"struct BrowserDragSessionToken\s*:\s*(?:Equatable|Hashable)[\s\S]*?Sendable",
        )
        self.assertIn("let rawValue: UUID", token)

        for state_name in ("BrowserTabDragState", "BrowserFolderDragState"):
            state = (
                SHARED_DRAG_ROOT / f"Services/{state_name}.swift"
            ).read_text()
            with self.subTest(state=state_name):
                self.assertIn(
                    "private(set) var sessionToken: BrowserDragSessionToken?",
                    state,
                )
                self.assertRegex(
                    state,
                    r"func begin\([\s\S]*?\)\s*->\s*BrowserDragSessionToken",
                )
                self.assertIn(
                    "func end(session token: BrowserDragSessionToken)",
                    state,
                )
                self.assertNotRegex(state, r"func end\(ifDragging (?:tabID|folderID)")

        for coordinator_name in (
            "BrowserMacTabDragGestureCoordinator",
            "BrowserMacFolderDragGestureCoordinator",
        ):
            coordinator = (
                MAC_DRAG_ROOT / f"Services/{coordinator_name}.swift"
            ).read_text()
            with self.subTest(coordinator=coordinator_name):
                self.assertIn("let sessionToken = dragState.begin(", coordinator)
                self.assertIn("dragState?.sessionToken == sessionToken", coordinator)
                self.assertIn("end(session: sessionToken)", coordinator)

        for modifier_name in (
            "BrowserPlatformTabDragSourceModifier",
            "BrowserPlatformFolderDragSourceModifier",
        ):
            modifier = (
                MOBILE_DRAG_ROOT / f"Components/{modifier_name}.swift"
            ).read_text()
            with self.subTest(modifier=modifier_name):
                self.assertIn(
                    "@State private var sessionToken: BrowserDragSessionToken?",
                    modifier,
                )
                self.assertIn("sessionToken = dragState.begin(", modifier)
                self.assertIn("end(session: sessionToken)", modifier)

    def test_live_drop_reports_failure_when_no_exact_move_succeeded(self) -> None:
        delegate = (
            SHARED_DRAG_ROOT / "Services/BrowserTabLiveDropDelegate.swift"
        ).read_text()
        self.assertIn("recordLiveMove()", delegate)
        self.assertRegex(
            delegate,
            r"performsLiveMove[\s\S]*?return\s+dragState\.liveMoveCount\s*>\s*0",
        )

    def test_platform_adapters_remain_explicit(self) -> None:
        mac_tab_source = (
            MAC_DRAG_ROOT
            / "Components/BrowserPlatformTabDragSourceModifier.swift"
        ).read_text()
        mac_folder_source = (
            MAC_DRAG_ROOT
            / "Components/BrowserPlatformFolderDragSourceModifier.swift"
        ).read_text()
        mobile_tab_source = (
            MOBILE_DRAG_ROOT
            / "Components/BrowserPlatformTabDragSourceModifier.swift"
        ).read_text()
        for mac_source in (mac_tab_source, mac_folder_source):
            self.assertIn("onGeometryChange", mac_source)
            self.assertIn(".gesture(", mac_source)
        self.assertIn("BrowserMacTabDragGesture", mac_tab_source)
        self.assertIn("BrowserMacFolderDragGesture", mac_folder_source)
        self.assertIn(".onDrag", mobile_tab_source)
        self.assertIn(".onDragSessionUpdated", mobile_tab_source)

        native_session = (
            MAC_DRAG_ROOT
            / "Services/BrowserMacNativeDraggingSession.swift"
        ).read_text()
        self.assertNotIn("NSDraggingSource {", native_session)
        self.assertRegex(
            native_session,
            r"beginDraggingSession\(\s*with:\s*\[draggingItem\],\s*event:\s*event,\s*source:\s*source",
        )
        self.assertIn("source: any NSDraggingSource", native_session)
        self.assertNotIn("beginDraggingSession(\n                    items:", native_session)
        self.assertNotIn("gesture: NSGestureRecognizer", native_session)

        for coordinator_name in (
            "BrowserMacTabDragGestureCoordinator",
            "BrowserMacFolderDragGestureCoordinator",
        ):
            coordinator = (
                MAC_DRAG_ROOT / f"Services/{coordinator_name}.swift"
            ).read_text()
            with self.subTest(coordinator=coordinator_name):
                self.assertIn("NSDraggingSource", coordinator)
                self.assertIn("source: self", coordinator)
                self.assertIn("sourceOperationMaskFor", coordinator)
                self.assertIn("endedAt screenPoint", coordinator)

        mac_drop_exit = (
            MAC_DRAG_ROOT / "Support/BrowserPlatformTabDropExitPolicy.swift"
        ).read_text()
        mobile_drop_exit = (
            MOBILE_DRAG_ROOT
            / "Support/BrowserPlatformTabDropExitPolicy.swift"
        ).read_text()
        self.assertIn("dragState.leavePinnedZone()", mac_drop_exit)
        self.assertIn("dragState.deferPinnedZoneExit()", mobile_drop_exit)

        self.assertIn("browserOnMiddleClick", MAC_MIDDLE_CLICK.read_text())
        self.assertNotIn(
            "browserOnMiddleClick",
            MOBILE_MIDDLE_CLICK.read_text(),
        )

        for source in (
            list(SHARED_GRID_ROOT.rglob("*.swift"))
            + list(SHARED_DRAG_ROOT.rglob("*.swift"))
            + list(SHARED_TAB_MENU_ROOT.rglob("*.swift"))
            + list(SHARED_FOLDER_MENU_ROOT.rglob("*.swift"))
        ):
            text = source.read_text()
            with self.subTest(source=source.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import AppKit", text)
                self.assertNotIn("#if", text)
                self.assertNotIn("#else", text)
                self.assertNotIn("#endif", text)


if __name__ == "__main__":
    unittest.main()
