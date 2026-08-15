#!/usr/bin/env python3
"""Focused vertical ownership contract for shared onboarding presentation."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-vertical-structure.py"
ONBOARDING_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Onboarding"

EXPECTED_TYPES = {
    "BrowserOnboardingPrimaryButtonStyle": (
        "Components/BrowserOnboardingPrimaryButtonStyle.swift",
        True,
    ),
    "BrowserOnboardingSecondaryButtonStyle": (
        "Components/BrowserOnboardingSecondaryButtonStyle.swift",
        True,
    ),
    "BrowserOnboardingPanelModifier": (
        "Components/BrowserOnboardingPanelModifier.swift",
        True,
    ),
    "BrowserOnboardingColorComponents": (
        "Models/BrowserOnboardingColorComponents.swift",
        False,
    ),
    "BrowserOnboardingPalette": (
        "Support/BrowserOnboardingPalette.swift",
        False,
    ),
    "BrowserOnboardingTypography": (
        "Support/BrowserOnboardingTypography.swift",
        False,
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


class BrowserOnboardingControlStylesStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def test_each_onboarding_presentation_owner_has_a_matching_file(self) -> None:
        for type_name, (relative_path, needs_preview) in EXPECTED_TYPES.items():
            with self.subTest(type_name=type_name):
                path = ONBOARDING_ROOT / relative_path
                self.assertTrue(path.is_file(), path)
                source = path.read_text()
                declarations = self.guard._named_declarations(source)
                self.assertEqual(
                    [declaration.name for declaration in declarations],
                    [type_name],
                )
                if needs_preview:
                    self.assertIn("#Preview", source)
                    self.assertIn(f"{type_name}(", source)

    def test_panel_view_extension_is_its_own_owner(self) -> None:
        path = ONBOARDING_ROOT / "Support/View+BrowserOnboardingPanel.swift"
        self.assertTrue(path.is_file(), path)
        source = path.read_text()
        self.assertIn("extension View", source)
        self.assertIn("func browserOnboardingPanel()", source)
        self.assertEqual(self.guard._named_declarations(source), [])

    def test_legacy_aggregate_is_removed(self) -> None:
        self.assertFalse(
            (ONBOARDING_ROOT / "BrowserOnboardingControlStyles.swift").exists()
        )


if __name__ == "__main__":
    unittest.main()
