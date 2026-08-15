#!/usr/bin/env python3
"""Vertical ownership contract for the macOS saved-folder row family."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Sidebar"
LEGACY_AGGREGATE = SIDEBAR_ROOT / "SavedFolderGroup.swift"
FAMILY_ROOT = SIDEBAR_ROOT / "SavedFolderGroup"
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts/check-vertical-structure.py"
PROJECT = REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj"

EXPECTED_OWNERS = {
    "SavedFolderGroup.swift": "SavedFolderGroup",
    "Components/SavedFolderGroupSurface.swift": "SavedFolderGroupSurface",
    "Components/SavedFolderHeader.swift": "SavedFolderHeader",
    "Components/SavedFolderHeaderControl.swift": "SavedFolderHeaderControl",
    "Components/SavedFolderIcon.swift": "SavedFolderIcon",
    "Components/SavedFolderTabRow.swift": "SavedFolderTabRow",
    "Components/SavedFolderTabRows.swift": "SavedFolderTabRows",
    "Models/SavedFolderGroupConfiguration.swift": (
        "SavedFolderGroupConfiguration"
    ),
    "Models/SavedFolderGroupInteractionContext.swift": (
        "SavedFolderGroupInteractionContext"
    ),
    "Support/BrowserFolderLiveDropDelegate.swift": (
        "BrowserFolderLiveDropDelegate"
    ),
    "Support/SavedFolderGroupPreviewFixture.swift": (
        "SavedFolderGroupPreviewFixture"
    ),
}


def load_guard_module():
    spec = importlib.util.spec_from_file_location(
        "crest_vertical_structure_guard", GUARD_SCRIPT
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load the vertical structure guard")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MacSavedFolderGroupStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def test_legacy_aggregate_is_replaced_by_named_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        for relative_path in EXPECTED_OWNERS:
            self.assertTrue((FAMILY_ROOT / relative_path).is_file(), relative_path)
        self.assertTrue(
            (FAMILY_ROOT / "Support/View+SavedFolderHeaderLayout.swift").is_file()
        )

    def test_each_source_has_exactly_one_file_scope_declaration(self) -> None:
        for source_path in FAMILY_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            primary = self.guard._primary_declarations(source)
            extensions = self.guard._top_level_extensions(source)
            declarations = [item.name for item in primary] + [
                f"extension {item.target}" for item in extensions
            ]
            self.assertEqual(
                len(declarations),
                1,
                f"{source_path.relative_to(FAMILY_ROOT)}: {declarations}",
            )

    def test_primary_names_match_their_files_and_extension_is_isolated(self) -> None:
        for relative_path, owner in EXPECTED_OWNERS.items():
            source = (FAMILY_ROOT / relative_path).read_text()
            primary = self.guard._primary_declarations(source)
            self.assertEqual([item.name for item in primary], [owner], relative_path)

        extension_source = (
            FAMILY_ROOT / "Support/View+SavedFolderHeaderLayout.swift"
        ).read_text()
        extensions = self.guard._top_level_extensions(extension_source)
        self.assertEqual([item.target for item in extensions], ["View"])
        self.assertEqual(self.guard._primary_declarations(extension_source), [])

    def test_root_composes_a_real_surface_without_view_fragments(self) -> None:
        root = (FAMILY_ROOT / "SavedFolderGroup.swift").read_text()
        self.assertIn("SavedFolderGroupSurface(", root)
        self.assertNotIn("@ViewBuilder", root)
        self.assertNotIn("private var folderHeaderControl: some View", root)
        self.assertNotIn("private var folderIcon: some View", root)

    def test_folder_actions_keep_exact_space_and_item_identity(self) -> None:
        root = (FAMILY_ROOT / "SavedFolderGroup.swift").read_text()
        header = (FAMILY_ROOT / "Components/SavedFolderHeader.swift").read_text()
        configuration = (
            FAMILY_ROOT / "Models/SavedFolderGroupConfiguration.swift"
        ).read_text()
        tab_rows = (
            FAMILY_ROOT / "Components/SavedFolderTabRows.swift"
        ).read_text()

        for operation in (
            "browser.renameFolder(\n            request.folderID,\n            matching: request.spaceAssignment",
            "browser.deleteFolder(request.folderID, matching: request.spaceAssignment)",
            "browser.setFolderColor(\n                    request.folderID,\n                    matching: request.spaceAssignment",
        ):
            self.assertIn(operation, root)
        self.assertIn("@Binding var editingFolderRequest", root)
        self.assertIn("@State private var colorRequest", root)
        self.assertIn("@State private var deletionRequest", root)
        self.assertIn("clearUnavailableDeferredActions", root)
        self.assertIn("BrowserSidebarTabActions(", configuration)
        self.assertIn("spaceID: spaceID", configuration)
        self.assertIn("BrowserTabDragAction(", header)
        self.assertIn("item,\n                        to:", header)
        self.assertIn("profileID: profileID", configuration)
        self.assertIn("guard configuration.isCurrentAndUnlocked", header)
        self.assertIn("matching: configuration.assignment", header)
        self.assertIn(
            "matching: configuration.assignment",
            tab_rows,
        )
        self.assertIn(
            "unload: interaction.unloadKeptCollapsedTab",
            tab_rows,
        )

    def test_visual_owners_have_direct_isolated_previews(self) -> None:
        visual_paths = [
            FAMILY_ROOT / "SavedFolderGroup.swift",
            *sorted((FAMILY_ROOT / "Components").glob("*.swift")),
        ]
        for source_path in visual_paths:
            source = source_path.read_text()
            owner = source_path.stem
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("#Preview", source)
                self.assertIn(f"{owner}(", source[source.index("#Preview") :])

        fixture = (
            FAMILY_ROOT / "Support/SavedFolderGroupPreviewFixture.swift"
        ).read_text()
        self.assertIn("usesEphemeralWebsiteDataStores: true", fixture)
        self.assertIn("browsingMode: .privateBrowsing", fixture)
        self.assertIn("InMemoryBrowserSessionPersistence", fixture)
        for forbidden in (
            "UUID()",
            "Date()",
            "UserDefaults",
            ".production(",
            "BrowserWebsiteDataStore.persistent",
        ):
            self.assertNotIn(forbidden, fixture)

    def test_split_owners_are_in_the_mac_app_target(self) -> None:
        project = PROJECT.read_text()
        filenames = [
            Path(relative_path).name for relative_path in EXPECTED_OWNERS
        ] + ["View+SavedFolderHeaderLayout.swift"]
        for filename in filenames:
            self.assertGreater(
                project.count(f"/* {filename} in Sources */"),
                0,
                filename,
            )


if __name__ == "__main__":
    unittest.main()
