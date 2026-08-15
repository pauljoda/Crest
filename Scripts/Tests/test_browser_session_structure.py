#!/usr/bin/env python3
"""Structural contract for the shared BrowserSession responsibility split."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
SESSION_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserSession"


class BrowserSessionStructureTests(unittest.TestCase):
    def test_flat_session_source_is_replaced_by_responsibility_tree(self) -> None:
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserSession.swift").exists()
        )

        required_files = (
            "BrowserSession.swift",
            "Models/BrowserTabRuntimeAssignment.swift",
            "Queries/BrowserSession+Queries.swift",
            "Selection/BrowserSession+Selection.swift",
            "Tabs/BrowserSession+TabLifecycle.swift",
            "Tabs/BrowserTabDismissalAction.swift",
            "Tabs/BrowserTabDismissalPolicy.swift",
            "Tabs/BrowserSession+TabAppearance.swift",
            "Tabs/BrowserSession+TabPlacement.swift",
            "Tabs/BrowserTabPlacementPlan.swift",
            "Tabs/BrowserTabPlacementDestinationSection.swift",
            "History/BrowserSession+History.swift",
            "Folders/BrowserSession+FolderManagement.swift",
            "Cleanup/BrowserSession+Cleanup.swift",
            "Spaces/BrowserSession+SpaceManagement.swift",
            "Integrity/BrowserSession+Integrity.swift",
            "Persistence/BrowserSession+Helpers.swift",
            "Factories/BrowserSession+Factories.swift",
            "Fixtures/BrowserSession+CleanupFixture.swift",
            "Fixtures/BrowserSession+Preview.swift",
            "Fixtures/BrowserPreviewSessionFactory.swift",
            "Fixtures/BrowserSession+Showcase.swift",
            "Fixtures/BrowserShowcaseSessionFactory.swift",
            "Fixtures/BrowserShowcasePageStyle.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((SESSION_ROOT / relative_path).is_file())

    def test_root_is_small_and_owns_only_the_session_type(self) -> None:
        root_source = (SESSION_ROOT / "BrowserSession.swift").read_text()
        declarations = re.findall(
            r"^(?:public |internal |private |fileprivate )?"
            r"(?:struct|enum|class|actor|protocol|typealias) ",
            root_source,
            re.MULTILINE,
        )

        self.assertEqual(root_source.count("struct BrowserSession"), 1)
        self.assertEqual(len(declarations), 1)
        self.assertLess(len(root_source.splitlines()), 40)

    def test_runtime_assignment_is_isolated_from_the_session_root(self) -> None:
        root_source = (SESSION_ROOT / "BrowserSession.swift").read_text()
        assignment_source = (
            SESSION_ROOT / "Models/BrowserTabRuntimeAssignment.swift"
        ).read_text()

        self.assertNotIn("struct BrowserTabRuntimeAssignment", root_source)
        self.assertIn("struct BrowserTabRuntimeAssignment", assignment_source)

    def test_cleanup_fixture_is_separate_from_factories_and_core(self) -> None:
        root_source = (SESSION_ROOT / "BrowserSession.swift").read_text()
        factory_source = (
            SESSION_ROOT / "Factories/BrowserSession+Factories.swift"
        ).read_text()
        fixture_source = (
            SESSION_ROOT / "Fixtures/BrowserSession+CleanupFixture.swift"
        ).read_text()

        self.assertNotIn("cleanupFixture", root_source)
        self.assertNotIn("cleanupFixture", factory_source)
        self.assertIn("static func cleanupFixture", fixture_source)

    def test_tab_placement_plan_and_section_have_matching_files(self) -> None:
        plan_source = (
            SESSION_ROOT / "Tabs/BrowserTabPlacementPlan.swift"
        ).read_text()
        section_source = (
            SESSION_ROOT / "Tabs/BrowserTabPlacementDestinationSection.swift"
        ).read_text()

        self.assertIn("struct BrowserTabPlacementPlan", plan_source)
        self.assertNotIn("struct DestinationSection", plan_source)
        self.assertIn(
            "struct BrowserTabPlacementDestinationSection",
            section_source,
        )

    def test_tab_dismissal_types_have_matching_files(self) -> None:
        lifecycle_source = (
            SESSION_ROOT / "Tabs/BrowserSession+TabLifecycle.swift"
        ).read_text()
        expected_declarations = {
            "BrowserTabDismissalAction.swift": "enum BrowserTabDismissalAction",
            "BrowserTabDismissalPolicy.swift": "enum BrowserTabDismissalPolicy",
        }

        self.assertIn("extension BrowserSession", lifecycle_source)
        for file_name, declaration in expected_declarations.items():
            with self.subTest(file_name=file_name):
                source = (SESSION_ROOT / "Tabs" / file_name).read_text()
                self.assertIn(declaration, source)
                self.assertNotIn("extension BrowserSession", source)
                self.assertNotIn(declaration, lifecycle_source)

        self.assertFalse(
            (SESSION_ROOT / "Tabs/BrowserTabDismissalSelectionPolicy.swift").exists()
        )

    def test_preview_and_showcase_fixtures_have_one_matching_owner_per_file(
        self,
    ) -> None:
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserPreviewSession.swift").exists()
        )
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserShowcaseSession.swift").exists()
        )

        preview_extension = (
            SESSION_ROOT / "Fixtures/BrowserSession+Preview.swift"
        ).read_text()
        preview_factory = (
            SESSION_ROOT / "Fixtures/BrowserPreviewSessionFactory.swift"
        ).read_text()
        showcase_extension = (
            SESSION_ROOT / "Fixtures/BrowserSession+Showcase.swift"
        ).read_text()
        showcase_factory = (
            SESSION_ROOT / "Fixtures/BrowserShowcaseSessionFactory.swift"
        ).read_text()
        showcase_style = (
            SESSION_ROOT / "Fixtures/BrowserShowcasePageStyle.swift"
        ).read_text()

        self.assertIn("extension BrowserSession", preview_extension)
        self.assertNotIn("enum BrowserPreviewSessionFactory", preview_extension)
        self.assertIn("enum BrowserPreviewSessionFactory", preview_factory)
        self.assertNotIn("extension BrowserSession", preview_factory)
        self.assertIn("extension BrowserSession", showcase_extension)
        self.assertNotIn("enum BrowserShowcaseSessionFactory", showcase_extension)
        self.assertIn("enum BrowserShowcaseSessionFactory", showcase_factory)
        self.assertNotIn("enum PageStyle", showcase_factory)
        self.assertIn("enum BrowserShowcasePageStyle", showcase_style)


if __name__ == "__main__":
    unittest.main()
