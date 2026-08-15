#!/usr/bin/env python3
"""Direct-preview contracts for the shared design-system component families."""

from pathlib import Path
import json
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
COMPONENT_ROOT = REPOSITORY_ROOT / "CrestShared/DesignSystem/Components"


class DesignSystemPreviewStructureTests(unittest.TestCase):
    def test_visible_components_have_colocated_direct_previews(self) -> None:
        expected_sources = {
            "BrowserAccessibleMaterialBackground/BrowserAccessibleMaterialBackground.swift": "BrowserAccessibleMaterialBackground",
            "BrowserChromeSymbolLabel.swift": "BrowserChromeSymbolLabel",
            "BrowserReloadControl/BrowserReloadControl.swift": "BrowserReloadControl",
            "BrowserReloadControl/Components/BrowserReloadFeedbackIcon.swift": "BrowserReloadFeedbackIcon",
            "BrowserRootContentSurface/BrowserRootContentSurface.swift": "BrowserRootContentSurface",
            "BrowserRootContentSurface/Components/CrestLiftedSurfaceShadow.swift": "CrestLiftedSurfaceShadow",
            "BrowserSettingsControls/Styles/BrowserSettingsIconButtonStyle.swift": "BrowserSettingsIconButtonStyle",
            "BrowserSettingsControls/Styles/BrowserSettingsLabeledActionButtonStyle.swift": "BrowserSettingsLabeledActionButtonStyle",
            "CrestButtonStyle/CrestButtonStyle.swift": "CrestButtonStyle",
            "CrestFormRow/CrestFormActionRow.swift": "CrestFormActionRow",
            "CrestFormRow/CrestFormControlRow.swift": "CrestFormControlRow",
            "CrestFormRow/CrestFormDisclosureChevron.swift": "CrestFormDisclosureChevron",
            "CrestFormRow/CrestFormFootnote.swift": "CrestFormFootnote",
            "CrestFormRow/CrestFormRowLabel.swift": "CrestFormRowLabel",
            "CrestIconTile.swift": "CrestIconTile",
            "CrestInteractiveSurface/Styles/CrestChromeButtonStyle.swift": "CrestChromeButtonStyle",
            "CrestSelectableCard/CrestSelectableCard.swift": "CrestSelectableCard",
            "CrestSelectableCard/Styles/CrestSelectableCardStyle.swift": "CrestSelectableCardStyle",
            "CrestSettingsPresentation/CrestSettingsDestinationLabel.swift": "CrestSettingsDestinationLabel",
            "CrestSettingsPresentation/CrestSettingsStatusRow.swift": "CrestSettingsStatusRow",
        }
        for relative_path, expected_type in expected_sources.items():
            source = (COMPONENT_ROOT / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertIn("#Preview", source)
                self.assertRegex(
                    source,
                    rf"#Preview[\s\S]*\b{re.escape(expected_type)}\s*\(",
                )

    def test_aggregate_preview_wrappers_are_removed(self) -> None:
        for previews in COMPONENT_ROOT.glob("*/Previews"):
            with self.subTest(previews=previews):
                self.assertFalse(previews.exists())

    def test_gallery_placement_is_a_matching_file_scope_model(self) -> None:
        gallery = (COMPONENT_ROOT / "CrestControlsGallery.swift").read_text()
        placement = (
            COMPONENT_ROOT / "CrestControlsGalleryPlacement.swift"
        ).read_text()
        self.assertNotIn("enum Placement", gallery)
        self.assertIn("enum CrestControlsGalleryPlacement", placement)

    def test_design_system_has_zero_debt_and_exact_repository_total(self) -> None:
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
                if violation[1][0].startswith(
                    "CrestShared/DesignSystem/Components/"
                )
            ]
        )
        self.assertEqual(len(violations), 0)


if __name__ == "__main__":
    unittest.main()
