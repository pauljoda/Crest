#!/usr/bin/env python3
"""Structural contracts for the mobile onboarding view family."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ONBOARDING_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Onboarding"
LEGACY_ROOT = ONBOARDING_ROOT / "MobileBrowserOnboardingView.swift"
VIEW_ROOT = ONBOARDING_ROOT / "MobileBrowserOnboardingView"
ROOT_VIEW = VIEW_ROOT / "MobileBrowserOnboardingView.swift"


class MobileOnboardingStructureTests(unittest.TestCase):
    def test_legacy_monolith_is_replaced_by_a_named_view_family(self) -> None:
        self.assertFalse(LEGACY_ROOT.exists())
        self.assertTrue(ROOT_VIEW.is_file())

        source = ROOT_VIEW.read_text()
        declarations = re.findall(
            r"^(?:@[A-Za-z0-9_() ,.]+\n)*(?:(?:public|internal|private|fileprivate) )?"
            r"(?:struct|class|enum|actor|protocol|extension)\s+([A-Za-z0-9_]+)",
            source,
            flags=re.MULTILINE,
        )

        self.assertEqual(declarations, ["MobileBrowserOnboardingView"])
        self.assertLessEqual(len(source.splitlines()), 360)

    def test_components_are_grouped_by_responsibility(self) -> None:
        required_files = (
            "Models/MobileBrowserOnboardingStep.swift",
            "Models/MobileOnboardingPageContext.swift",
            "Services/MobileOnboardingDraftPersistence.swift",
            "Support/MobileBrowserOnboardingPolicy.swift",
            "Support/MobileOnboardingSpacePreviewFactory.swift",
            "Support/MobileOnboardingLayout.swift",
            "Support/Array+MobileOnboardingSafeIndex.swift",
            "Support/MobileOnboardingPreviewFixtures.swift",
            "Components/MobileOnboardingCurrentPage.swift",
            "Components/MobileOnboardingLifecycleModifier.swift",
            "Components/MobileOnboardingPage.swift",
            "Components/MobileOnboardingPageActions.swift",
            "Components/MobileOnboardingProgressIndicator.swift",
            "Components/MobileOnboardingTitle.swift",
            "Components/MobileOnboardingFeatureRow.swift",
            "Components/MobileOnboardingLayeredSpacePreview.swift",
            "Components/MobileOnboardingSpaceCard.swift",
            "Components/MobileOnboardingSpaceCardActions.swift",
            "Components/MobileOnboardingAddSpaceCard.swift",
            "Components/MobileOnboardingSpaceCustomizationSheet.swift",
            "Components/Pages/MobileOnboardingWelcomePage.swift",
            "Components/Pages/MobileOnboardingSpacesFeaturePage.swift",
            "Components/Pages/MobileOnboardingTabsFeaturePage.swift",
            "Components/Pages/MobileOnboardingSyncFeaturePage.swift",
            "Components/Pages/MobileOnboardingSpaceSetupPage.swift",
            "Components/Pages/MobileOnboardingSpaceCarousel.swift",
            "Components/Pages/MobileOnboardingMacImportPage.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((VIEW_ROOT / relative_path).is_file())

        for obsolete_bucket in ("Extensions", "Metrics", "Policies", "Previews"):
            self.assertFalse((VIEW_ROOT / obsolete_bucket).exists())

    def test_deterministic_sample_sites_live_only_in_preview_support(self) -> None:
        preview_fixture = VIEW_ROOT / "Support/MobileOnboardingPreviewFixtures.swift"
        preview_source = preview_fixture.read_text()
        production_source = "\n".join(
            path.read_text()
            for path in VIEW_ROOT.rglob("*.swift")
            if path != preview_fixture
        )

        for sample_site in (
            "mail.google.com",
            "calendar.google.com",
            "notion.so",
            "developer.apple.com",
        ):
            with self.subTest(sample_site=sample_site):
                self.assertIn(sample_site, preview_source)
                self.assertNotIn(sample_site, production_source)

        force_unwrap = re.compile(r"(?:\)|\]|[A-Za-z0-9_])!(?![=])")
        self.assertIsNone(force_unwrap.search(production_source))
        self.assertNotIn("UUID(uuidString:", production_source)

    def test_production_files_do_not_hide_secondary_type_declarations(self) -> None:
        for path in VIEW_ROOT.rglob("*.swift"):
            declarations = re.findall(
                r"^(?:@[A-Za-z0-9_() ,.]+\n)*"
                r"(?:(?:public|internal|private|fileprivate) )?"
                r"(?:struct|class|enum|actor|protocol|extension)\s+"
                r"([A-Za-z0-9_]+)",
                path.read_text(),
                flags=re.MULTILINE,
            )
            with self.subTest(path=path.relative_to(VIEW_ROOT)):
                self.assertEqual(len(declarations), 1)

    def test_root_steps_and_visual_components_have_direct_previews(self) -> None:
        previewed_paths = (
            "MobileBrowserOnboardingView.swift",
            "Components/MobileOnboardingCurrentPage.swift",
            "Components/MobileOnboardingLifecycleModifier.swift",
            "Components/MobileOnboardingPage.swift",
            "Components/MobileOnboardingPageActions.swift",
            "Components/MobileOnboardingProgressIndicator.swift",
            "Components/MobileOnboardingTitle.swift",
            "Components/MobileOnboardingFeatureRow.swift",
            "Components/MobileOnboardingLayeredSpacePreview.swift",
            "Components/MobileOnboardingSpaceCard.swift",
            "Components/MobileOnboardingSpaceCardActions.swift",
            "Components/MobileOnboardingAddSpaceCard.swift",
            "Components/MobileOnboardingSpaceCustomizationSheet.swift",
            "Components/Pages/MobileOnboardingWelcomePage.swift",
            "Components/Pages/MobileOnboardingSpacesFeaturePage.swift",
            "Components/Pages/MobileOnboardingTabsFeaturePage.swift",
            "Components/Pages/MobileOnboardingSyncFeaturePage.swift",
            "Components/Pages/MobileOnboardingSpaceSetupPage.swift",
            "Components/Pages/MobileOnboardingSpaceCarousel.swift",
            "Components/Pages/MobileOnboardingMacImportPage.swift",
        )
        for relative_path in previewed_paths:
            path = VIEW_ROOT / relative_path
            source = path.read_text()
            expected_type = path.stem
            with self.subTest(path=relative_path):
                self.assertIn("#Preview", source)
                self.assertRegex(
                    source,
                    rf"#Preview[\s\S]*\b{re.escape(expected_type)}\s*\(",
                )
                self.assertNotIn("UserDefaults.standard", source)

    def test_root_uses_injected_draft_persistence(self) -> None:
        source = ROOT_VIEW.read_text()
        persistence = (
            VIEW_ROOT / "Services/MobileOnboardingDraftPersistence.swift"
        ).read_text()
        lifecycle = (
            VIEW_ROOT / "Components/MobileOnboardingLifecycleModifier.swift"
        ).read_text()

        self.assertIn("let draftPersistence: MobileOnboardingDraftPersistence", source)
        self.assertIn("draftPersistence.load()", source)
        self.assertIn("draftPersistence.save(plan)", lifecycle)
        self.assertIn("draftPersistence.clear()", source)
        self.assertNotIn("BrowserManualSetupDraftStore", source)
        self.assertIn("static let live", persistence)
        self.assertIn("static let preview", persistence)

    def test_production_tutorial_content_is_preserved_and_previews_inject_spaces(
        self,
    ) -> None:
        source = ROOT_VIEW.read_text()
        fixtures = (
            VIEW_ROOT / "Support/MobileOnboardingPreviewFixtures.swift"
        ).read_text()

        self.assertIn(
            "MobileOnboardingPreviewFixtures.tutorialPersonalSpace",
            source,
        )
        self.assertIn(
            "MobileOnboardingPreviewFixtures.tutorialWorkSpace",
            source,
        )
        self.assertIn("BrowserSession.preview.spaces.first", fixtures)
        self.assertIn("BrowserSession.preview.spaces.dropFirst().first", fixtures)
        preview_source = source.split("#Preview", maxsplit=1)[1]
        self.assertIn("tutorialPersonalSpace: fixture.alternateSpace", preview_source)
        self.assertIn("tutorialWorkSpace: fixture.space", preview_source)

    def test_family_has_zero_debt_and_exact_repository_total(self) -> None:
        payload = json.loads(
            (REPOSITORY_ROOT / "Config/VerticalStructureDebt.json").read_text()
        )
        violations = [
            (rule, entry)
            for rule, details in payload["rules"].items()
            for entry in details["violations"]
        ]
        self.assertFalse(
            [
                violation
                for violation in violations
                if "MobileBrowserOnboardingView" in violation[1][0]
            ]
        )
        self.assertEqual(len(violations), 0)


if __name__ == "__main__":
    unittest.main()
