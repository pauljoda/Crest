#!/usr/bin/env python3
"""Performance contracts for the shared manual-setup preview."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VIEW_PATH = (
    REPOSITORY_ROOT / "CrestShared/Features/Onboarding/BrowserManualSetupView.swift"
)
FAMILY_ROOT = VIEW_PATH.with_suffix("")
ONBOARDING_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Onboarding"
STYLE_PATHS = [
    ONBOARDING_ROOT / "Components/BrowserOnboardingPanelModifier.swift",
    ONBOARDING_ROOT / "Components/BrowserOnboardingPrimaryButtonStyle.swift",
    ONBOARDING_ROOT / "Components/BrowserOnboardingSecondaryButtonStyle.swift",
    ONBOARDING_ROOT / "Support/View+BrowserOnboardingPanel.swift",
]


class ManualSetupPerformanceTests(unittest.TestCase):
    def test_manual_setup_uses_only_live_onboarding_style_adapters(self) -> None:
        styles = "\n".join(path.read_text() for path in STYLE_PATHS)
        manual_setup = "\n".join(
            path.read_text()
            for path in [VIEW_PATH, *sorted(FAMILY_ROOT.rglob("*.swift"))]
        )

        self.assertNotIn("BrowserOnboardingIconButtonStyle", styles)
        self.assertNotIn("BrowserOnboardingSpaceChipStyle", styles)
        self.assertNotIn("browserOnboardingField", styles)
        self.assertNotIn("BrowserOnboardingPanelModifier(tint:", styles)
        self.assertIn(".browserOnboardingPanel()", manual_setup)
        self.assertNotIn(".browserOnboardingPanel(tint:", manual_setup)

    def test_preview_session_is_built_once_per_render(self) -> None:
        source = (
            FAMILY_ROOT / "Components/BrowserManualSetupContent.swift"
        ).read_text()

        self.assertEqual(source.count("let previewSession ="), 1)
        self.assertEqual(source.count("model.previewSession("), 1)
        self.assertEqual(source.count("previewSession: previewSession"), 2)
        self.assertNotIn("plan.spaces.map(previewSpace(for:))", source)


if __name__ == "__main__":
    unittest.main()
