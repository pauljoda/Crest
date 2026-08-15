#!/usr/bin/env python3
"""Structural contracts for the macOS onboarding window family."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
ONBOARDING_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Onboarding"
WINDOW_ROOT = ONBOARDING_ROOT / "BrowserOnboardingWindow"
ROOT_VIEW = ONBOARDING_ROOT / "BrowserOnboardingWindow.swift"


class MacOnboardingLayoutTests(unittest.TestCase):
    def test_window_family_uses_named_component_boundaries(self) -> None:
        required_files = (
            "Models/BrowserOnboardingStep.swift",
            "Support/BrowserMacOnboardingPolicy.swift",
            "Components/BrowserSourceImportPreview/Models/BrowserSourceImportPreviewSections.swift",
            "Support/BrowserOnboardingAppearancePolicy.swift",
            "Support/BrowserImportReviewNavigation.swift",
            "Support/BrowserOnboardingSummary.swift",
            "Support/BrowserImportPreviewControls.swift",
            "Support/BrowserOnboardingLegacyDraftCleanup.swift",
            "Support/BrowserOnboardingWindowActivation.swift",
            "Support/BrowserOnboardingLaunchGateWindow.swift",
            "Models/BrowserOnboardingFailureText.swift",
            "Components/BrowserOnboardingBackdrop.swift",
            "Components/BrowserOnboardingHeroPreview.swift",
            "Components/BrowserOnboardingWindowConfigurator/BrowserOnboardingWindowConfigurator.swift",
            "Components/BrowserOnboardingWindowConfigurator/BrowserOnboardingWindowConfigurationView.swift",
            "Components/BrowserSourceImportPreview/BrowserSourceImportPreview.swift",
            "Components/BrowserCrestImportPreview/BrowserCrestImportPreview.swift",
            "Components/BrowserImportSidebar/BrowserImportSidebarFrame.swift",
            "Components/BrowserImportSidebar/BrowserImportSidebarFolderRow.swift",
            "Components/BrowserImportSidebar/BrowserImportSidebarResultTabRow.swift",
            "Components/BrowserImportSpaceCustomizationView/BrowserImportSpaceCustomizationView.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((WINDOW_ROOT / relative_path).is_file())

    def test_visual_families_have_deterministic_preview_companions(self) -> None:
        preview_files = (
            "Components/BrowserOnboardingBackdrop.swift",
            "Components/BrowserOnboardingHeroPreview.swift",
            "Components/BrowserImportSidebar/BrowserImportSidebarFrame.swift",
            "Components/BrowserSourceImportPreview/BrowserSourceImportPreview.swift",
            "Components/BrowserCrestImportPreview/BrowserCrestImportPreview.swift",
            "Components/BrowserImportSpaceCustomizationView/BrowserImportSpaceCustomizationView.swift",
        )

        for relative_path in preview_files:
            with self.subTest(relative_path=relative_path):
                source = (WINDOW_ROOT / relative_path).read_text()
                self.assertIn("#Preview", source)

        self.assertFalse((WINDOW_ROOT / "Persistence").exists())
        self.assertFalse((WINDOW_ROOT / "Policies").exists())
        self.assertFalse((WINDOW_ROOT / "Previews").exists())
        self.assertFalse((WINDOW_ROOT / "Window").exists())

    def test_failure_message_is_a_matching_file_scope_model(self) -> None:
        failure = (WINDOW_ROOT / "Models/BrowserOnboardingFailure.swift").read_text()
        message = (
            WINDOW_ROOT / "Models/BrowserOnboardingFailureText.swift"
        ).read_text()

        self.assertNotIn("enum Message", failure)
        self.assertIn("var message: BrowserOnboardingFailureText", failure)
        self.assertIn("enum BrowserOnboardingFailureText: Equatable", message)

    def test_root_file_owns_only_the_root_view_type(self) -> None:
        source = ROOT_VIEW.read_text()
        declarations = re.findall(
            r"^(?:@[A-Za-z0-9_() ,.]+\n)*(?:(?:public|internal|private|fileprivate) )?"
            r"(?:struct|class|enum|actor|protocol|extension)\s+([A-Za-z0-9_]+)",
            source,
            flags=re.MULTILINE,
        )

        self.assertEqual(declarations, ["BrowserOnboardingWindow"])
        self.assertNotIn("enum BrowserOnboardingDraftStore", source)
        self.assertNotIn("struct BrowserImportHoverCardModifier", source)
        self.assertNotIn("struct BrowserOnboardingWindowConfigurator", source)

    def test_space_customization_tolerates_a_removed_review_space(self) -> None:
        source = (
            WINDOW_ROOT
            / "Components/BrowserImportSpaceCustomizationView/"
            "BrowserImportSpaceCustomizationView.swift"
        ).read_text()

        self.assertIn("if review != nil", source)
        self.assertIn("guard let review else { return }", source)
        self.assertNotIn("plan.spaces.first { $0.id == spaceID }!", source)

    def test_source_preview_partitions_tabs_once_per_render(self) -> None:
        source = (
            WINDOW_ROOT
            / "Components/BrowserSourceImportPreview/BrowserSourceImportPreview.swift"
        ).read_text()

        self.assertIn("BrowserSourceImportPreviewSections(review: review)", source)
        self.assertNotIn("private func tabs(for placement:", source)
        self.assertNotIn("savedTabs.filter", source)

    def test_import_preview_controls_rely_on_accessibility_without_hover_popovers(self) -> None:
        preview_files = (
            "Components/BrowserSourceImportPreview/Components/"
            "BrowserSourceImportPinnedGrid.swift",
            "Components/BrowserSourceImportPreview/Components/"
            "BrowserSourceImportTabRow.swift",
            "Components/BrowserCrestImportPreview/Components/"
            "BrowserCrestImportPinnedGrid.swift",
            "Components/BrowserImportSidebar/BrowserImportSidebarResultTabRow.swift",
        )

        for relative_path in preview_files:
            with self.subTest(relative_path=relative_path):
                source = (WINDOW_ROOT / relative_path).read_text()
                self.assertNotIn(".browserImportHoverCard(", source)
                self.assertNotIn(".help(", source)
                self.assertIn(".accessibilityValue(", source)


if __name__ == "__main__":
    unittest.main()
