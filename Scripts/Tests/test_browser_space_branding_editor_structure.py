#!/usr/bin/env python3
"""Structural contracts for the Space-branding editor vertical family."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
EDITOR_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Spaces/Components/BrowserSpaceBrandingEditor"
)

VISUAL_OWNERS = {
    "BrowserSpaceBrandingEditor.swift": "BrowserSpaceBrandingEditor",
    "Components/BrowserSpaceForgeFoundationSteps.swift": "BrowserSpaceForgeFoundationSteps",
    "Components/BrowserSpaceForgeSection.swift": "BrowserSpaceForgeSection",
    "Components/Crest/BrowserSpaceChargeStep.swift": "BrowserSpaceChargeStep",
    "Components/Crest/BrowserSpaceFieldDivisionStep.swift": "BrowserSpaceFieldDivisionStep",
    "Components/Crest/BrowserSpaceForgeCrestSteps.swift": "BrowserSpaceForgeCrestSteps",
    "Components/Crest/BrowserSpaceOrdinaryStep.swift": "BrowserSpaceOrdinaryStep",
    "Components/Crest/BrowserSpaceShieldStep.swift": "BrowserSpaceShieldStep",
    "Components/Crest/BrowserSpaceTrimStep.swift": "BrowserSpaceTrimStep",
    "Components/Crest/LayerColor/BrowserSpaceLayerColorPicker.swift": "BrowserSpaceLayerColorPicker",
    "Components/Crest/LayerColor/BrowserSpaceTinctureChip.swift": "BrowserSpaceTinctureChip",
    "Components/Field/BrowserSpaceFieldStep.swift": "BrowserSpaceFieldStep",
    "Components/Field/BrowserSpacePaletteSlot.swift": "BrowserSpacePaletteSlot",
    "Components/Field/BrowserSpacePresetCard.swift": "BrowserSpacePresetCard",
    "Components/Gallery/BrowserSpaceCrestOptionGallery.swift": "BrowserSpaceCrestOptionGallery",
    "Components/Gallery/BrowserSpaceOptionCard.swift": "BrowserSpaceOptionCard",
    "Components/Gallery/BrowserSpaceOptionGallery.swift": "BrowserSpaceOptionGallery",
    "Components/Mark/BrowserSpaceCrestArtifactPreview.swift": "BrowserSpaceCrestArtifactPreview",
    "Components/Mark/BrowserSpaceMarkStep.swift": "BrowserSpaceMarkStep",
    "Components/Mark/BrowserSpaceSimpleSymbolPicker.swift": "BrowserSpaceSimpleSymbolPicker",
    "Components/Pattern/BrowserSpaceGradientAngleDial.swift": "BrowserSpaceGradientAngleDial",
    "Components/Pattern/BrowserSpacePatternStep.swift": "BrowserSpacePatternStep",
    "Components/Pattern/FineTuning/BrowserSpaceBannerSlider.swift": "BrowserSpaceBannerSlider",
    "Components/Pattern/FineTuning/BrowserSpaceFineTuningControl.swift": "BrowserSpaceFineTuningControl",
    "Components/Pattern/FineTuning/BrowserSpaceFineTuningFields.swift": "BrowserSpaceFineTuningFields",
    "Components/Preview/BrowserSpaceEditorIdentityPreview.swift": "BrowserSpaceEditorIdentityPreview",
    "Components/Preview/BrowserSpaceEditorPreview.swift": "BrowserSpaceEditorPreview",
}

NONVISUAL_OWNERS = {
    "Models/BrowserSpaceForgeStep.swift": "BrowserSpaceForgeStep",
    "Models/BrowserSpaceForgeStep+BrowserSpaceHeraldicTerm.swift": "BrowserSpaceForgeStep",
    "Models/BrowserSpaceSimpleSymbol.swift": "BrowserSpaceSimpleSymbol",
    "Models/BrowserSpaceSimpleSymbol+Presentation.swift": "BrowserSpaceSimpleSymbol",
    "Support/Binding+BrowserSpaceBrandingEditorValues.swift": "Binding",
    "Support/Binding+BrowserSpaceBrandingEditorCrest.swift": "Binding",
    "Support/Binding+BrowserSpaceBrandingEditorPalette.swift": "Binding",
    "Support/Binding+BrowserSpaceBrandingEditorMutation.swift": "Binding",
    "Support/BrowserSpaceForgeMetrics.swift": "BrowserSpaceForgeMetrics",
}


class BrowserSpaceBrandingEditorStructureTests(unittest.TestCase):
    def test_editor_family_uses_only_role_folders_and_one_owner_per_file(self) -> None:
        expected = {**VISUAL_OWNERS, **NONVISUAL_OWNERS}

        for relative_path, owner in expected.items():
            source_path = EDITOR_ROOT / relative_path
            with self.subTest(relative_path=relative_path):
                self.assertTrue(source_path.is_file())
                source = source_path.read_text()
                declarations = re.findall(
                    r"(?m)^(?:private\s+)?(?:struct|enum|class|actor|protocol|typealias|extension)\s+([A-Za-z_][A-Za-z0-9_]*)",
                    source,
                )
                self.assertEqual(declarations, [owner])

        self.assertEqual(
            {path.name for path in EDITOR_ROOT.iterdir() if path.is_dir()},
            {"Components", "Models", "Support"},
        )
        for obsolete in ("Extensions", "Metrics", "Previews"):
            self.assertFalse((EDITOR_ROOT / obsolete).exists())

    def test_root_composes_a_real_content_component(self) -> None:
        root = (EDITOR_ROOT / "BrowserSpaceBrandingEditor.swift").read_text()

        self.assertIn("BrowserSpaceForgeFoundationSteps(", root)
        self.assertIn("BrowserSpaceForgeCrestSteps(", root)
        self.assertNotIn("@ViewBuilder", root)
        self.assertLessEqual(len(root.splitlines()), 50)

        foundation = (
            EDITOR_ROOT / "Components/BrowserSpaceForgeFoundationSteps.swift"
        ).read_text()
        for owner in (
            "BrowserSpaceEditorPreview",
            "BrowserSpaceFieldStep",
            "BrowserSpacePatternStep",
            "BrowserSpaceMarkStep",
        ):
            self.assertIn(f"{owner}(", foundation)

        crest = (
            EDITOR_ROOT / "Components/Crest/BrowserSpaceForgeCrestSteps.swift"
        ).read_text()
        for owner in (
            "BrowserSpaceShieldStep",
            "BrowserSpaceFieldDivisionStep",
            "BrowserSpaceOrdinaryStep",
            "BrowserSpaceChargeStep",
            "BrowserSpaceTrimStep",
        ):
            self.assertIn(f"{owner}(", crest)

    def test_editor_sources_are_platform_neutral_and_tokenized(self) -> None:
        for source_path in EDITOR_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)
                self.assertNotRegex(
                    source,
                    r"\.(?:easeIn|easeOut|easeInOut|linear)\(duration:\s*[0-9]",
                )

        fine_tuning = (
            EDITOR_ROOT
            / "Components/Pattern/FineTuning/BrowserSpaceFineTuningControl.swift"
        ).read_text()
        self.assertIn("CrestMotion.pane", fine_tuning)
        self.assertIn("BrowserVisualAccessibilityPolicy.animation", fine_tuning)

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        forbidden = re.compile(
            r"UUID\(\s*\)|Date\(\s*\)|\.now\b|\.random\b|UserDefaults|@AppStorage|"
            r"WKWebView|URLSession|AsyncImage|FileManager|Data\(contentsOf:|Keychain|Security"
        )

        for relative_path, owner in VISUAL_OWNERS.items():
            source = (EDITOR_ROOT / relative_path).read_text()
            previews = source.split("#Preview", 1)
            with self.subTest(relative_path=relative_path):
                self.assertEqual(len(previews), 2)
                preview = previews[1]
                self.assertRegex(preview, rf"\b{owner}\s*(?:<[^>]+>)?\s*\(")
                if owner == "BrowserSpaceSimpleSymbolPicker":
                    self.assertIn("BrowserSpaceSimpleSymbol.work", preview)
                else:
                    self.assertIn("BrowserSpaceBrandingPreviewFixture", preview)
                self.assertIsNone(forbidden.search(preview))

    def test_obsolete_aggregate_previews_and_extension_suffix_are_absent(self) -> None:
        for path in (
            EDITOR_ROOT / "Previews/BrowserSpaceBrandingEditorPreviews.swift",
            EDITOR_ROOT / "Previews/BrowserSpaceGradientAngleDialPreviews.swift",
            EDITOR_ROOT / "Previews/BrowserSpaceOptionCardPreviews.swift",
            EDITOR_ROOT / "Extensions/BrowserSpaceForgeStep+HeraldicTerm.swift",
            REPOSITORY_ROOT
            / "CrestShared/Features/Spaces/BrowserSpaceBrandingEditor",
        ):
            self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
