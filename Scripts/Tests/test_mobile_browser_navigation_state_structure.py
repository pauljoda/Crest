#!/usr/bin/env python3
"""Ownership contracts for mobile browser navigation presentation state."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LEGACY_FILE = (
    REPOSITORY_ROOT
    / "CrestMobile/Infrastructure/WebKit/MobileBrowserNavigationState.swift"
)
FAMILY_ROOT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Browser/MobileBrowserRootView"
)
MODELS_ROOT = FAMILY_ROOT / "Models"
SUPPORT_ROOT = FAMILY_ROOT / "Support"
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class MobileBrowserNavigationStateStructureTests(unittest.TestCase):
    def test_framework_neutral_aggregate_leaves_webkit_infrastructure(self) -> None:
        self.assertFalse(LEGACY_FILE.exists())

    def test_each_navigation_owner_has_one_matching_file(self) -> None:
        required = {
            MODELS_ROOT / "MobileBrowserNavigationState.swift":
                "MobileBrowserNavigationState",
            MODELS_ROOT / "MobileBrowserPresentation.swift":
                "MobileBrowserPresentation",
            MODELS_ROOT / "MobileBrowserSpaceSwitchDestination.swift":
                "MobileBrowserSpaceSwitchDestination",
            MODELS_ROOT / "MobileCompactChromeTransition.swift":
                "MobileCompactChromeTransition",
            MODELS_ROOT / "MobileCompactPagePresentationPhase.swift":
                "MobileCompactPagePresentationPhase",
            MODELS_ROOT / "MobileRegularWindowLayout.swift":
                "MobileRegularWindowLayout",
            MODELS_ROOT / "MobileTabPromotionTarget.swift":
                "MobileTabPromotionTarget",
            SUPPORT_ROOT / "MobileBrowserSpaceSwitchPolicy.swift":
                "MobileBrowserSpaceSwitchPolicy",
            SUPPORT_ROOT / "MobileCompactTabViewerLayout.swift":
                "MobileCompactTabViewerLayout",
            SUPPORT_ROOT / "MobileTabPromotionPolicy.swift":
                "MobileTabPromotionPolicy",
            SUPPORT_ROOT / "MobileCompactChromeTransitionPolicy.swift":
                "MobileCompactChromeTransitionPolicy",
            SUPPORT_ROOT / "MobileRegularWindowLayoutPolicy.swift":
                "MobileRegularWindowLayoutPolicy",
        }

        for path, owner in required.items():
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(
                    DECLARATION_PATTERN.findall(path.read_text()),
                    [owner],
                )

    def test_navigation_state_uses_a_matching_phase_owner(self) -> None:
        source = (MODELS_ROOT / "MobileBrowserNavigationState.swift").read_text()

        self.assertIn(
            "private var compactPagePresentationPhase: "
            "MobileCompactPagePresentationPhase",
            source,
        )
        self.assertNotIn("enum MobileCompactPagePresentationPhase", source)
        self.assertIn("@Observable", source)
        self.assertIn("@MainActor", source)
        self.assertNotIn("CoreGraphics", source)
        self.assertNotIn("WebKit", source)

    def test_tab_promotion_target_is_not_a_nested_declaration(self) -> None:
        policy = (SUPPORT_ROOT / "MobileTabPromotionPolicy.swift").read_text()
        target = (MODELS_ROOT / "MobileTabPromotionTarget.swift").read_text()

        self.assertNotIn("struct Target", policy)
        self.assertIn(") -> MobileTabPromotionTarget?", policy)
        self.assertIn("let tabID: TabID", target)
        self.assertIn("let placement: TabPlacement", target)

    def test_behavior_constants_and_exhaustive_branches_remain_explicit(self) -> None:
        transition = (
            SUPPORT_ROOT / "MobileCompactChromeTransitionPolicy.swift"
        ).read_text()
        regular = (SUPPORT_ROOT / "MobileRegularWindowLayoutPolicy.swift").read_text()
        switch = (SUPPORT_ROOT / "MobileBrowserSpaceSwitchPolicy.swift").read_text()

        for token in ("64", "1.2", "220"):
            self.assertIn(token, transition)
        for token in ("minimumDetailWidth", "320", "overlayEdgeClearance", "44"):
            self.assertIn(token, regular)
        self.assertIn(".compact ? .tabViewer : .selectedPage", switch)


if __name__ == "__main__":
    unittest.main()
