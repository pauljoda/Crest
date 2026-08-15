#!/usr/bin/env python3
"""Vertical presentation contracts for shared manual Space setup."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
VIEW_PATH = (
    REPOSITORY_ROOT / "CrestShared/Features/Onboarding/BrowserManualSetupView.swift"
)
FAMILY_ROOT = VIEW_PATH.with_suffix("")
COMPONENT_ROOT = FAMILY_ROOT / "Components"
MODEL_ROOT = FAMILY_ROOT / "Models"
SUPPORT_ROOT = FAMILY_ROOT / "Support"

PRIMARY_DECLARATION = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
VIEW_DECLARATION = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|final)\s+)*"
    r"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b",
    re.MULTILINE,
)


class ManualSetupStructureTests(unittest.TestCase):
    def test_manual_setup_family_is_vertical_and_decomposed(self) -> None:
        required_files = (
            VIEW_PATH,
            COMPONENT_ROOT / "BrowserManualSetupContent.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupContent/Components/BrowserManualSetupCompactLayout.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupContent/Components/BrowserManualSetupWideLayout.swift",
            COMPONENT_ROOT / "BrowserManualSetupSpacePicker.swift",
            COMPONENT_ROOT / "BrowserManualSetupSidebarPreview.swift",
            COMPONENT_ROOT / "BrowserManualSetupEditor.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupEditorHeader.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupSpaceNameField.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupSiteEditor.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupSiteEditor/Components/BrowserManualSetupAddressRow.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupSiteEditor/Components/BrowserManualSetupPlacementPicker.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupSiteEditor/Components/BrowserManualSetupPopularSites.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupSiteEditor/Components/BrowserManualSetupSuggestionRow.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupSiteEditor/Components/BrowserManualSetupErrorMessage.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupAddedTabList.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupEditor/Components/BrowserManualSetupAddedTabList/Components/BrowserManualSetupAddedTabRow.swift",
            COMPONENT_ROOT / "BrowserManualSetupPlacementMenu.swift",
            COMPONENT_ROOT
            / "BrowserManualSetupPlacementMenu/Components/BrowserManualSetupPlacementMenuLabel.swift",
            COMPONENT_ROOT / "BrowserSpaceSidebarPreview.swift",
            COMPONENT_ROOT
            / "BrowserSpaceSidebarPreview/Components/BrowserSpaceSidebarSection.swift",
            COMPONENT_ROOT
            / "BrowserSpaceSidebarPreview/Components/BrowserSpaceSidebarTabRow.swift",
            MODEL_ROOT / "BrowserManualSetupLayout.swift",
            MODEL_ROOT / "BrowserManualSetupModel/BrowserManualSetupModel.swift",
            MODEL_ROOT
            / "BrowserManualSetupModel/BrowserManualSetupModel+Actions.swift",
            MODEL_ROOT
            / "BrowserManualSetupModel/BrowserManualSetupModel+Bindings.swift",
            MODEL_ROOT
            / "BrowserManualSetupModel/BrowserManualSetupModel+Projection.swift",
            SUPPORT_ROOT / "BrowserManualSetupLayoutMetrics.swift",
            SUPPORT_ROOT / "BrowserManualSetupSiteEditorMetrics.swift",
            SUPPORT_ROOT / "BrowserManualSetupPlacementMenuMetrics.swift",
            SUPPORT_ROOT / "BrowserManualSetupSidebarPreviewMetrics.swift",
            SUPPORT_ROOT / "BrowserManualSetupPlacementPresentation.swift",
            SUPPORT_ROOT / "BrowserManualSetupSitePolicy.swift",
            SUPPORT_ROOT / "BrowserManualSetupPreviewFixture.swift",
        )
        for path in required_files:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        self.assertFalse((FAMILY_ROOT / "Metrics").exists())

    def test_root_is_a_thin_model_view_composition(self) -> None:
        source = VIEW_PATH.read_text()

        self.assertLessEqual(len(source.splitlines()), 80)
        self.assertIn("@State private var model = BrowserManualSetupModel()", source)
        self.assertIn("BrowserManualSetupContent(", source)
        self.assertIn("model.repairSelection(", source)
        self.assertIn("selectedSpaceID: $selectedSpaceID", source)
        self.assertIn("#Preview", source)

        for operation in (
            "func addSpace",
            "func addTab",
            "func addSuggestion",
            "func setPlacement",
            "func previewSpace",
            "func matchingHost",
            "func placementTitle",
        ):
            with self.subTest(operation=operation):
                self.assertNotIn(operation, source)

    def test_production_files_have_one_matching_primary_type(self) -> None:
        production_files = [VIEW_PATH, *sorted(FAMILY_ROOT.rglob("*.swift"))]
        for path in production_files:
            source = path.read_text()
            declarations = PRIMARY_DECLARATION.findall(source)
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                if "+" in path.stem:
                    self.assertEqual(declarations, [])
                    self.assertEqual(source.count("extension "), 1)
                else:
                    self.assertEqual(declarations, [path.stem])

    def test_view_files_contain_one_view_and_no_computed_view_fragments(self) -> None:
        visual_files = []
        for path in [VIEW_PATH, *sorted(FAMILY_ROOT.rglob("*.swift"))]:
            source = path.read_text()
            views = VIEW_DECLARATION.findall(source)
            if not views:
                continue
            visual_files.append((path, views[0], source))
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(views, [path.stem])
                self.assertNotRegex(
                    source,
                    r"private\s+(?:@ViewBuilder\s+)?(?:var|func)\s+"
                    r"[A-Za-z_][A-Za-z0-9_() :,]*\s*(?:->|:)\s*some\s+View",
                )

        self.assertGreaterEqual(len(visual_files), 20)

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        for path in [VIEW_PATH, *sorted(FAMILY_ROOT.rglob("*.swift"))]:
            source = path.read_text()
            views = VIEW_DECLARATION.findall(source)
            if not views:
                continue
            owner = views[0]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("#Preview", source)
                preview_source = source[source.index("#Preview") :]
                self.assertIn(f"{owner}(", preview_source)
                for forbidden in (
                    "UUID()",
                    "Date()",
                    ".now",
                    "UserDefaults",
                    "BrowserStore.production",
                    "BrowserWebsiteDataStore.persistent",
                ):
                    self.assertNotIn(forbidden, preview_source)

        fixture = (SUPPORT_ROOT / "BrowserManualSetupPreviewFixture.swift").read_text()
        self.assertRegex(fixture, r"UUID\s*\(\s*uuid:")
        self.assertIn("Date(timeIntervalSinceReferenceDate:", fixture)
        self.assertNotIn("UUID()", fixture)
        self.assertNotIn("Date()", fixture)
        self.assertNotIn(".now", fixture)
        for forbidden in (
            "UserDefaults",
            "FileManager",
            "CloudKit",
            "Keychain",
            "WKWebView",
            "BrowserStore.production",
        ):
            self.assertNotIn(forbidden, fixture)

    def test_model_owns_mutation_workflow_and_preserves_exact_space_identity(self) -> None:
        model = (
            MODEL_ROOT / "BrowserManualSetupModel/BrowserManualSetupModel.swift"
        ).read_text()
        actions = (
            MODEL_ROOT / "BrowserManualSetupModel/BrowserManualSetupModel+Actions.swift"
        ).read_text()
        bindings = (
            MODEL_ROOT / "BrowserManualSetupModel/BrowserManualSetupModel+Bindings.swift"
        ).read_text()
        projection = (
            MODEL_ROOT / "BrowserManualSetupModel/BrowserManualSetupModel+Projection.swift"
        ).read_text()
        combined = "\n".join((model, actions, bindings, projection))

        self.assertIn("@MainActor", model)
        self.assertIn("@Observable", model)
        self.assertIn("address: String = \"\"", model)
        self.assertIn("placement: TabPlacement = .saved", model)
        self.assertIn("var errorMessage: String?", model)
        for operation in (
            ".addSpace()",
            ".removeSpace(",
            ".addTab(",
            ".removeTab(",
            ".setPlacement(",
            ".setSpaceIdentity(",
            ".setSpaceBranding(",
        ):
            with self.subTest(operation=operation):
                self.assertIn(operation, combined)

        self.assertIn("$0.id == selectedSpaceID", projection)
        self.assertIn("existingSession.space(id: spaceID)", projection)
        self.assertIn("profile: draft.profile", projection)
        self.assertNotIn("selectedSpaceIndex", combined)
        self.assertNotRegex(combined, r"spaces\s*\[\s*selected")

    def test_accessibility_strings_and_placement_contracts_remain_intact(self) -> None:
        presentation_source = "\n".join(
            path.read_text()
            for path in [VIEW_PATH, *sorted(COMPONENT_ROOT.rglob("*.swift"))]
        )
        for identifier in (
            ".spacePicker",
            ".addSpace",
            ".sidebarPreview",
            ".spaceName(",
            ".address",
            ".addTab",
            ".suggestion(",
            ".placement(",
            ".error",
        ):
            with self.subTest(identifier=identifier):
                self.assertIn(identifier, presentation_source)

        placement = (
            SUPPORT_ROOT / "BrowserManualSetupPlacementPresentation.swift"
        ).read_text()
        for case, title, symbol in (
            ("pinned", "Pinned", "pin.fill"),
            ("saved", "Saved", "bookmark.fill"),
            ("current", "Open", "rectangle.stack.fill"),
        ):
            with self.subTest(case=case):
                self.assertIn(f"case .{case}:", placement)
                self.assertIn(f'"{title}"', placement)
                self.assertIn(f'"{symbol}"', placement)

    def test_shared_family_stays_platform_neutral(self) -> None:
        for path in [VIEW_PATH, *sorted(FAMILY_ROOT.rglob("*.swift"))]:
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)


if __name__ == "__main__":
    unittest.main()
