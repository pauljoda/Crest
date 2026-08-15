#!/usr/bin/env python3
"""Focused source contract for the macOS onboarding window family."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-vertical-structure.py"
WINDOW_SOURCE = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/BrowserOnboardingWindow.swift"
)
COMPONENT_ROOT = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/BrowserOnboardingWindow/Components"
)
PREVIEW_FIXTURE = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/BrowserOnboardingWindow/Support/"
    "BrowserOnboardingWindowPreviewFixture.swift"
)

EXPECTED_COMPONENTS = {
    "BrowserOnboardingWindowContent": "BrowserOnboardingWindowContent.swift",
    "BrowserOnboardingStepContent": "BrowserOnboardingStepContent.swift",
    "BrowserOnboardingProgressHeader": "BrowserOnboardingProgressHeader.swift",
    "BrowserOnboardingFailureMessage": "BrowserOnboardingFailureMessage.swift",
    "BrowserOnboardingManualSetupPage": "BrowserOnboardingManualSetupPage.swift",
    "BrowserOnboardingCompletionPage": "BrowserOnboardingCompletionPage.swift",
    "BrowserOnboardingWelcomePage": (
        "BrowserOnboardingWelcomePage/BrowserOnboardingWelcomePage.swift"
    ),
    "BrowserOnboardingWelcomeCallToAction": (
        "BrowserOnboardingWelcomePage/Components/"
        "BrowserOnboardingWelcomeCallToAction.swift"
    ),
    "BrowserOnboardingImportPage": (
        "BrowserOnboardingImportPage/BrowserOnboardingImportPage.swift"
    ),
    "BrowserInstalledImportSourceGrid": (
        "BrowserOnboardingImportPage/Components/"
        "BrowserInstalledImportSourceGrid/"
        "BrowserInstalledImportSourceGrid.swift"
    ),
    "BrowserInstalledImportSourceCard": (
        "BrowserOnboardingImportPage/Components/"
        "BrowserInstalledImportSourceGrid/Components/"
        "BrowserInstalledImportSourceCard.swift"
    ),
    "BrowserOnboardingImportSelectionAction": (
        "BrowserOnboardingImportPage/Components/"
        "BrowserOnboardingImportSelectionAction.swift"
    ),
    "BrowserOnboardingReviewPage": (
        "BrowserOnboardingReviewPage/BrowserOnboardingReviewPage.swift"
    ),
    "BrowserOnboardingReviewToolbar": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewToolbar.swift"
    ),
    "BrowserOnboardingReviewSpacePage": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewSpacePage/"
        "BrowserOnboardingReviewSpacePage.swift"
    ),
    "BrowserOnboardingReviewSpaceControls": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewSpacePage/Components/"
        "BrowserOnboardingReviewSpaceControls/"
        "BrowserOnboardingReviewSpaceControls.swift"
    ),
    "BrowserOnboardingReviewSourcePicker": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewSpacePage/Components/"
        "BrowserOnboardingReviewSpaceControls/Components/"
        "BrowserOnboardingReviewSourcePicker.swift"
    ),
    "BrowserOnboardingReviewDestinationPicker": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewSpacePage/Components/"
        "BrowserOnboardingReviewSpaceControls/Components/"
        "BrowserOnboardingReviewDestinationPicker.swift"
    ),
    "BrowserOnboardingReviewSpaceStepper": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewSpaceStepper.swift"
    ),
    "BrowserOnboardingReviewFooter": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewFooter.swift"
    ),
    "BrowserOnboardingPreviewCardLabel": (
        "BrowserOnboardingReviewPage/Components/"
        "BrowserOnboardingReviewSpacePage/Components/"
        "BrowserOnboardingPreviewCardLabel.swift"
    ),
    "BrowserMacOnboardingTutorialPage": (
        "BrowserMacOnboardingTutorialPage/"
        "BrowserMacOnboardingTutorialPage.swift"
    ),
    "BrowserMacOnboardingTutorialCopy": (
        "BrowserMacOnboardingTutorialPage/Components/"
        "BrowserMacOnboardingTutorialCopy.swift"
    ),
    "BrowserMacOnboardingTutorialArtwork": (
        "BrowserMacOnboardingTutorialPage/Components/"
        "BrowserMacOnboardingTutorialArtwork.swift"
    ),
    "BrowserMacOnboardingTabsPreview": (
        "BrowserMacOnboardingTutorialPage/Components/"
        "BrowserMacOnboardingTabsPreview.swift"
    ),
    "BrowserMacOnboardingSyncPreview": (
        "BrowserMacOnboardingTutorialPage/Components/"
        "BrowserMacOnboardingSyncPreview.swift"
    ),
}

EXPECTED_TUTORIAL_MODELS = {
    "BrowserMacOnboardingTutorial": (
        "BrowserMacOnboardingTutorialPage/Models/"
        "BrowserMacOnboardingTutorial.swift"
    ),
    "BrowserMacOnboardingTutorialFeature": (
        "BrowserMacOnboardingTutorialPage/Models/"
        "BrowserMacOnboardingTutorialFeature.swift"
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


class BrowserOnboardingWindowStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def test_root_window_is_a_thin_debt_free_composition(self) -> None:
        source = WINDOW_SOURCE.read_text()
        self.assertIn("BrowserOnboardingWindowContent(", source)

        violations = [
            violation.key
            for violation in self.guard.scan_repository(REPOSITORY_ROOT)
            if violation.path
            == "CrestMac/Features/Onboarding/BrowserOnboardingWindow.swift"
        ]
        self.assertEqual(violations, [])

    def test_window_sections_are_named_previewed_component_views(self) -> None:
        for type_name, relative_path in EXPECTED_COMPONENTS.items():
            with self.subTest(type_name=type_name):
                path = COMPONENT_ROOT / relative_path
                self.assertTrue(path.is_file(), path)
                source = path.read_text()
                self.assertIn(f"struct {type_name}: View", source)
                self.assertIn("#Preview", source)
                self.assertIn(f"{type_name}(", source)

    def test_tutorial_models_are_matching_single_type_files(self) -> None:
        for type_name, relative_path in EXPECTED_TUTORIAL_MODELS.items():
            with self.subTest(type_name=type_name):
                path = COMPONENT_ROOT / relative_path
                self.assertTrue(path.is_file(), path)
                source = path.read_text()
                declarations = self.guard._named_declarations(source)
                self.assertEqual(
                    [declaration.name for declaration in declarations],
                    [type_name],
                )

    def test_tutorial_root_composes_real_views_without_fragments(self) -> None:
        path = (
            COMPONENT_ROOT
            / "BrowserMacOnboardingTutorialPage/"
            "BrowserMacOnboardingTutorialPage.swift"
        )
        source = path.read_text()

        self.assertIn("BrowserMacOnboardingTutorialCopy(", source)
        self.assertIn("BrowserMacOnboardingTutorialArtwork(", source)
        self.assertNotIn("tutorialCopy", source)
        self.assertNotIn("tutorialArtwork", source)

    def test_preview_fixture_is_fixed_and_in_memory(self) -> None:
        source = PREVIEW_FIXTURE.read_text()

        self.assertIn("UUID(\n        uuid:", source)
        self.assertIn("Date(timeIntervalSince1970:", source)
        self.assertIn("InMemoryBrowserSessionPersistence()", source)
        self.assertIn(
            "InMemoryBrowserOnboardingProgressPersistence()", source
        )
        self.assertIn("BrowserOnboardingPreviewSourceDiscovery(", source)
        self.assertNotIn("UUID()", source)
        self.assertNotIn("uuidString:", source)
        self.assertNotIn("UserDefaults", source)
        self.assertNotIn("SecurityBrowserSafeStorage", source)
        self.assertNotIn(".production(", source)
        self.assertNotIn("!", source)


if __name__ == "__main__":
    unittest.main()
