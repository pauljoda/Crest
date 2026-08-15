#!/usr/bin/env python3
"""Vertical and data-safety contract for onboarding import previews."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts/check-vertical-structure.py"
WINDOW_ROOT = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/BrowserOnboardingWindow"
)
COMPONENT_ROOT = WINDOW_ROOT / "Components"
SUPPORT_ROOT = WINDOW_ROOT / "Support"

EXPECTED_VIEWS = {
    "BrowserSourceImportPreview": (
        "BrowserSourceImportPreview/BrowserSourceImportPreview.swift"
    ),
    "BrowserSourceImportContent": (
        "BrowserSourceImportPreview/Components/BrowserSourceImportContent.swift"
    ),
    "BrowserSourceImportChrome": (
        "BrowserSourceImportPreview/Components/BrowserSourceImportChrome.swift"
    ),
    "BrowserSourceImportSpaceHeader": (
        "BrowserSourceImportPreview/Components/"
        "BrowserSourceImportSpaceHeader.swift"
    ),
    "BrowserSourceImportPinnedGrid": (
        "BrowserSourceImportPreview/Components/BrowserSourceImportPinnedGrid.swift"
    ),
    "BrowserSourceImportSavedTabs": (
        "BrowserSourceImportPreview/Components/BrowserSourceImportSavedTabs.swift"
    ),
    "BrowserSourceImportSectionHeader": (
        "BrowserSourceImportPreview/Components/"
        "BrowserSourceImportSectionHeader.swift"
    ),
    "BrowserSourceImportTabRow": (
        "BrowserSourceImportPreview/Components/BrowserSourceImportTabRow.swift"
    ),
    "BrowserSourceImportTabPlacementMenu": (
        "BrowserSourceImportPreview/Components/"
        "BrowserSourceImportTabPlacementMenu.swift"
    ),
    "BrowserSourceImportFooter": (
        "BrowserSourceImportPreview/Components/BrowserSourceImportFooter.swift"
    ),
    "BrowserCrestImportPreview": (
        "BrowserCrestImportPreview/BrowserCrestImportPreview.swift"
    ),
    "BrowserCrestImportContent": (
        "BrowserCrestImportPreview/Components/BrowserCrestImportContent.swift"
    ),
    "BrowserCrestImportChrome": (
        "BrowserCrestImportPreview/Components/BrowserCrestImportChrome.swift"
    ),
    "BrowserCrestImportPinnedGrid": (
        "BrowserCrestImportPreview/Components/BrowserCrestImportPinnedGrid.swift"
    ),
    "BrowserCrestImportSpaceHeader": (
        "BrowserCrestImportPreview/Components/BrowserCrestImportSpaceHeader.swift"
    ),
    "BrowserCrestImportTabList": (
        "BrowserCrestImportPreview/Components/BrowserCrestImportTabList.swift"
    ),
    "BrowserCrestImportSpaceSwitcher": (
        "BrowserCrestImportPreview/Components/BrowserCrestImportSpaceSwitcher.swift"
    ),
    "BrowserImportSpaceCustomizationView": (
        "BrowserImportSpaceCustomizationView/"
        "BrowserImportSpaceCustomizationView.swift"
    ),
    "BrowserImportSpaceCustomizationContent": (
        "BrowserImportSpaceCustomizationView/Components/"
        "BrowserImportSpaceCustomizationContent.swift"
    ),
    "BrowserImportSpaceCustomizationHeader": (
        "BrowserImportSpaceCustomizationView/Components/"
        "BrowserImportSpaceCustomizationHeader.swift"
    ),
    "BrowserImportSpaceCustomizationEditor": (
        "BrowserImportSpaceCustomizationView/Components/"
        "BrowserImportSpaceCustomizationEditor.swift"
    ),
    "BrowserImportSpaceCustomizationPreviewPane": (
        "BrowserImportSpaceCustomizationView/Components/"
        "BrowserImportSpaceCustomizationPreviewPane.swift"
    ),
    "BrowserImportSidebarFrame": (
        "BrowserImportSidebar/BrowserImportSidebarFrame.swift"
    ),
    "BrowserImportSidebarFolderRow": (
        "BrowserImportSidebar/BrowserImportSidebarFolderRow.swift"
    ),
    "BrowserImportSidebarResultTabRow": (
        "BrowserImportSidebar/BrowserImportSidebarResultTabRow.swift"
    ),
}


def load_guard_module():
    spec = importlib.util.spec_from_file_location(
        "crest_vertical_structure_guard", GUARD_SCRIPT
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load vertical structure guard")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BrowserImportPreviewStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def test_import_preview_views_are_named_colocated_components(self) -> None:
        for type_name, relative_path in EXPECTED_VIEWS.items():
            with self.subTest(type_name=type_name):
                path = COMPONENT_ROOT / relative_path
                self.assertTrue(path.is_file(), path)
                source = path.read_text()
                self.assertRegex(
                    source,
                    rf"struct {type_name}(?:<[^>]+>)?: View",
                )
                self.assertIn("#Preview", source)
                self.assertIn(f"{type_name}(", source)

    def test_source_and_result_roots_compose_real_view_types(self) -> None:
        source = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserSourceImportPreview"]
        ).read_text()
        result = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserCrestImportPreview"]
        ).read_text()
        source_content = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserSourceImportContent"]
        ).read_text()
        result_content = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserCrestImportContent"]
        ).read_text()

        self.assertIn("BrowserSourceImportContent(", source)
        self.assertIn("BrowserCrestImportContent(", result)

        for component in (
            "BrowserSourceImportChrome(",
            "BrowserSourceImportSpaceHeader(",
            "BrowserSourceImportPinnedGrid(",
            "BrowserSourceImportSavedTabs(",
            "BrowserSourceImportFooter(",
        ):
            self.assertIn(component, source_content)
        for component in (
            "BrowserCrestImportChrome(",
            "BrowserCrestImportPinnedGrid(",
            "BrowserCrestImportSpaceHeader(",
            "BrowserCrestImportTabList(",
            "BrowserCrestImportSpaceSwitcher(",
        ):
            self.assertIn(component, result_content)

        self.assertNotIn("private var sourceChrome", source)
        self.assertNotIn("private func sourceTabRow", source)
        self.assertNotIn("private func crestChrome", result)

    def test_import_preview_identity_stays_bound_to_space_and_profile_ids(self) -> None:
        source_grid = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserSourceImportPinnedGrid"]
        ).read_text()
        source_row = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserSourceImportTabRow"]
        ).read_text()
        result_grid = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserCrestImportPinnedGrid"]
        ).read_text()
        customization = (
            COMPONENT_ROOT
            / EXPECTED_VIEWS["BrowserImportSpaceCustomizationView"]
        ).read_text()

        self.assertIn("profileID: review.sourceSpace.profile.id", source_grid)
        self.assertIn("profileID: review.sourceSpace.profile.id", source_row)
        self.assertIn("profileID: space.profile.id", result_grid)
        self.assertIn("plan.spaces.first { $0.id == spaceID }", customization)
        self.assertIn("for: spaceID", customization)
        self.assertNotIn("selectedSpaceIndex", customization)

    def test_preview_fixture_is_fixed_and_has_no_live_dependencies(self) -> None:
        path = SUPPORT_ROOT / "BrowserImportPreviewFixture.swift"
        self.assertTrue(path.is_file(), path)
        source = path.read_text()

        self.assertIn("UUID(\n            uuid:", source)
        self.assertIn("Date(timeIntervalSince1970:", source)
        self.assertIn("BrowserImportReviewPlan(", source)
        for forbidden in (
            "UUID()",
            "Date()",
            "Date.now",
            "UserDefaults",
            "FileManager",
            "URLSession",
            "BrowserStore.production",
            "WKWebView",
            "BrowserSession.showcase",
        ):
            self.assertNotIn(forbidden, source)

    def test_family_has_no_vertical_debt_or_legacy_preview_buckets(self) -> None:
        self.assertFalse((WINDOW_ROOT / "Previews/BrowserImportPreviewPreviews.swift").exists())
        self.assertFalse(
            (
                COMPONENT_ROOT
                / "BrowserImportSidebar/Previews/BrowserImportSidebarPreviews.swift"
            ).exists()
        )
        self.assertTrue(
            (SUPPORT_ROOT / "BrowserImportPreviewControls.swift").is_file()
        )

        family_paths = {
            str((COMPONENT_ROOT / relative_path).relative_to(REPOSITORY_ROOT))
            for relative_path in EXPECTED_VIEWS.values()
        }
        family_paths.update(
            {
                str(
                    (
                        SUPPORT_ROOT / "BrowserImportPreviewControls.swift"
                    ).relative_to(REPOSITORY_ROOT)
                ),
                str(
                    (
                        SUPPORT_ROOT / "BrowserImportPreviewFixture.swift"
                    ).relative_to(REPOSITORY_ROOT)
                ),
            }
        )
        violations = [
            violation.key
            for violation in self.guard.scan_repository(REPOSITORY_ROOT)
            if violation.path in family_paths
        ]
        self.assertEqual(violations, [])


if __name__ == "__main__":
    unittest.main()
