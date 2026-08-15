#!/usr/bin/env python3
"""Repository contracts for Crest's shared and platform source roots."""

from __future__ import annotations

import pathlib
import subprocess
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]


class RepositoryLayoutTests(unittest.TestCase):
    def test_sources_have_shared_mac_and_mobile_roots(self) -> None:
        for source_root in ("CrestShared", "CrestMac", "CrestMobile"):
            with self.subTest(source_root=source_root):
                self.assertTrue((REPOSITORY_ROOT / source_root).is_dir())

        self.assertFalse((REPOSITORY_ROOT / "Crest").exists())

    def test_shared_root_uses_feature_and_design_system_boundaries(self) -> None:
        required_directories = (
            "CrestShared/Application",
            "CrestShared/DesignSystem/Accessibility",
            "CrestShared/DesignSystem/Animations",
            "CrestShared/DesignSystem/Tokens",
            "CrestShared/DesignSystem/Components",
            "CrestShared/DesignSystem/Modifiers",
            "CrestShared/Domain",
            "CrestShared/Features",
            "CrestShared/Infrastructure",
            "CrestShared/Resources",
        )

        for relative_path in required_directories:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_dir())

    def test_project_uses_roots_instead_of_a_mobile_file_allowlist(self) -> None:
        project = (REPOSITORY_ROOT / "project.yml").read_text()

        self.assertIn("- path: CrestShared", project)
        self.assertIn("- path: CrestMac", project)
        self.assertIn("- path: CrestMobile", project)
        self.assertNotIn("Crest/Infrastructure/BrowserCloudRecordCodec.swift", project)
        self.assertNotIn("Crest/Presentation/BrowserChromeLayout.swift", project)

    def test_platform_design_tokens_are_platform_owned(self) -> None:
        shared_theme = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Tokens/CrestBrandTheme.swift"
        ).read_text()
        self.assertNotIn("import AppKit", shared_theme)
        self.assertNotIn("import UIKit", shared_theme)
        self.assertNotIn("#if os(macOS)", shared_theme)

        shared_layout = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Tokens/CrestLayout.swift"
        ).read_text()
        self.assertNotIn("#if os(macOS)", shared_layout)

        shared_button_interaction = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestButtonStyle/Extensions/View+CrestButtonInteraction.swift"
        ).read_text()
        self.assertNotIn("#if os(macOS)", shared_button_interaction)

        shared_settings_form = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestSettingsPresentation/Modifiers/View+CrestSettingsForm.swift"
        ).read_text()
        self.assertNotIn("#if os(macOS)", shared_settings_form)

        for relative_path in (
            "CrestMac/DesignSystem/Colors/CrestPlatformDynamicColor.swift",
            "CrestMac/DesignSystem/Metrics/CrestPlatformLayout.swift",
            "CrestMac/DesignSystem/Modifiers/CrestPlatformFocusShapeModifier.swift",
            "CrestMac/DesignSystem/Modifiers/CrestPlatformSettingsFormModifier.swift",
            "CrestMobile/DesignSystem/Colors/CrestPlatformDynamicColor.swift",
            "CrestMobile/DesignSystem/Metrics/CrestPlatformLayout.swift",
            "CrestMobile/DesignSystem/Modifiers/CrestPlatformFocusShapeModifier.swift",
            "CrestMobile/DesignSystem/Modifiers/CrestPlatformSettingsFormModifier.swift",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

    def test_component_families_use_named_folders_and_companion_previews(self) -> None:
        selector_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestSpaceSelector"
        )
        required_files = (
            "Models/CrestSpaceIdentity.swift",
            "Support/CrestSpaceSelectorPreviewFixture.swift",
            "Support/CrestSpaceSelectorPreviewVariant.swift",
            "Components/CrestSpaceChipRail/CrestSpaceChipRail.swift",
            "Components/CrestSpaceChipRail/Components/CrestSpaceAddChipSurface.swift",
            "Components/CrestSpaceChipRail/Components/CrestSpaceChipSurface.swift",
            "Components/CrestSpaceChipRail/Models/CrestSpaceChipCommand.swift",
            "Components/CrestSpaceChipRail/Models/CrestSpaceChipAddAction.swift",
            "Support/CrestSpaceChipMetrics.swift",
            "Components/CrestSpaceChipRail/Support/CrestSpaceChipStyle.swift",
            "Components/CrestSpaceChipRail/Support/CrestSpaceAddChipStyle.swift",
            "Components/CrestSpaceChipRail/Support/CrestSpaceChipCommands.swift",
            "Components/CrestSpaceIconPicker/CrestSpaceIconPicker.swift",
            "Components/CrestSpaceIconPicker/Support/CrestSpaceIconPickerMetrics.swift",
            "Components/CrestSpaceMenuPicker/CrestSpaceMenuPicker.swift",
            "Components/CrestSpaceMenuPicker/Support/CrestSpaceMenuLabelVisibility.swift",
            "Components/CrestSpaceMenuPicker/Support/CrestSpaceMenuPicker+OptionalInitializer.swift",
            "Components/CrestSpaceMenuPicker/Support/CrestSpaceMenuPicker+RequiredInitializer.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((selector_root / relative_path).is_file())

        for filename in (
            "CrestOptionalAccessibilityIdentifier.swift",
            "CrestOptionalAccessibilityValue.swift",
            "View+CrestAccessibilityIdentifier.swift",
            "View+CrestAccessibilityValue.swift",
        ):
            with self.subTest(filename=filename):
                self.assertTrue(
                    (
                        REPOSITORY_ROOT
                        / "CrestShared/DesignSystem/Modifiers"
                        / filename
                    ).is_file()
                )

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/CrestSpaceSelector.swift"
            ).exists()
        )

        reload_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/BrowserReloadControl"
        )
        reload_files = (
            "BrowserReloadControl.swift",
            "Policies/BrowserReloadFeedbackPolicy.swift",
            "Components/BrowserReloadFeedbackIcon.swift",
        )
        for relative_path in reload_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((reload_root / relative_path).is_file())

        self.assertTrue(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/BrowserChromeSymbolLabel.swift"
            ).is_file()
        )
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/BrowserReloadControl.swift"
            ).exists()
        )

        button_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestButtonStyle"
        )
        button_files = (
            "CrestButtonStyle.swift",
            "Models/CrestButtonRole.swift",
            "Metrics/CrestButtonMetrics.swift",
            "Styles/CrestButtonSurface.swift",
            "Modifiers/CrestPressFeedbackModifier.swift",
            "Extensions/ButtonStyle+Crest.swift",
            "Extensions/View+CrestButtonInteraction.swift",
        )
        for relative_path in button_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((button_root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/CrestButtonStyle.swift"
            ).exists()
        )

        form_row_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestFormRow"
        )
        form_row_files = (
            "CrestFormRowLabel.swift",
            "CrestFormActionRow.swift",
            "CrestFormControlRow.swift",
            "CrestFormDisclosureChevron.swift",
            "CrestFormFootnote.swift",
            "Metrics/CrestFormRowMetrics.swift",
            "Extensions/View+CrestFormFootnote.swift",
        )
        for relative_path in form_row_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((form_row_root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/CrestFormRow.swift"
            ).exists()
        )

        selectable_card_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestSelectableCard"
        )
        selectable_card_files = (
            "CrestSelectableCard.swift",
            "Metrics/CrestSelectableCardMetrics.swift",
            "Styles/CrestSelectableCardStyle.swift",
            "Styles/CrestSelectableCardSurface.swift",
        )
        for relative_path in selectable_card_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((selectable_card_root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/CrestSelectableCard.swift"
            ).exists()
        )

        text_field_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestTextField"
        )
        text_field_files = (
            "Metrics/CrestFieldMetrics.swift",
            "Modifiers/CrestFieldSurface.swift",
            "Extensions/View+CrestTextField.swift",
        )
        for relative_path in text_field_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((text_field_root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/CrestTextFieldStyle.swift"
            ).exists()
        )

        root_surface_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/BrowserRootContentSurface"
        )
        root_surface_files = (
            "BrowserRootContentSurface.swift",
            "Components/CrestLiftedSurfaceShadow.swift",
        )
        for relative_path in root_surface_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((root_surface_root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Components/CrestLiftedSurfaceShadow.swift"
            ).exists()
        )

        interactive_surface_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestInteractiveSurface"
        )
        interactive_surface_files = (
            "Modifiers/CrestInteractiveSurfaceModifier.swift",
            "Modifiers/CrestHoverSurfaceModifier.swift",
            "Modifiers/CrestChromeButtonSurface.swift",
            "Metrics/CrestInteractiveSurfaceMetrics.swift",
            "Styles/CrestChromeButtonStyle.swift",
            "Extensions/View+CrestInteractiveSurface.swift",
            "Extensions/View+CrestHoverSurface.swift",
        )
        for relative_path in interactive_surface_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((interactive_surface_root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Modifiers/CrestInteractiveSurface.swift"
            ).exists()
        )

        settings_presentation_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestSettingsPresentation"
        )
        settings_presentation_files = (
            "CrestSettingsDestinationLabel.swift",
            "CrestSettingsStatusRow.swift",
            "Metrics/CrestSettingsPresentationMetrics.swift",
            "Modifiers/View+CrestSettingsForm.swift",
        )
        for relative_path in settings_presentation_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((settings_presentation_root / relative_path).is_file())

        for old_relative_path in (
            "CrestShared/DesignSystem/Components/CrestSettingsDestinationLabel.swift",
            "CrestShared/DesignSystem/Components/CrestSettingsStatusRow.swift",
            "CrestShared/DesignSystem/Modifiers/CrestSettingsForm.swift",
        ):
            with self.subTest(old_relative_path=old_relative_path):
                self.assertFalse((REPOSITORY_ROOT / old_relative_path).exists())

        self.assertTrue(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Accessibility/BrowserAccessibilityID.swift"
            ).is_file()
        )

        self.assertTrue(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Animations/CrestCollectionMotion/CrestCollectionMotionModifier.swift"
            ).is_file()
        )
        self.assertTrue(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Animations/CrestCollectionMotion/Extensions/View+CrestCollectionMotion.swift"
            ).is_file()
        )
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/DesignSystem/Modifiers/CrestCollectionMotion.swift"
            ).exists()
        )

    def test_page_actions_and_scene_state_use_named_boundaries(self) -> None:
        page_action_root = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/BrowserPageActions"
        )
        for relative_path in (
            "Find/BrowserFindExecuting.swift",
            "Find/WKWebView+BrowserFindExecuting.swift",
            "Find/Models/BrowserFindDirection.swift",
            "Find/Models/BrowserFindMatchState.swift",
            "Find/Models/BrowserFindSession.swift",
            "Reload/BrowserPageReloadAction.swift",
            "Reload/BrowserPageReloadMode.swift",
            "Reload/BrowserPageReloadPolicy.swift",
            "Developer/BrowserDeveloperCapturePolicy.swift",
            "Developer/BrowserDeveloperModePolicy.swift",
            "Developer/BrowserDeveloperNavigationPolicy.swift",
            "Developer/Models/BrowserDeveloperPanel.swift",
            "Developer/Models/BrowserWebInspectorToggleResult.swift",
            "Zoom/BrowserPageZoomPolicy.swift",
            "Export/BrowserPageExportError.swift",
            "Export/BrowserPageExportPolicy.swift",
            "Models/BrowserNavigationHistoryItem.swift",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertTrue((page_action_root / relative_path).is_file())

        find_port = (page_action_root / "Find/BrowserFindExecuting.swift").read_text()
        find_adapter = (
            page_action_root / "Find/WKWebView+BrowserFindExecuting.swift"
        ).read_text()
        self.assertNotIn("extension WKWebView", find_port)
        self.assertIn("extension WKWebView: BrowserFindExecuting", find_adapter)

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserPageActions.swift"
            ).exists()
        )

    def test_favicon_capture_keeps_its_url_policy_owner_scoped(self) -> None:
        source = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/BrowserFaviconCapture.swift"
        ).read_text()

        self.assertNotIn("extension URL", source)
        self.assertIn("private static func isHTTPFamily", source)

        for relative_path in (
            "CrestShared/Application/BrowserOnboarding/Models/BrowserOnboardingRequest.swift",
            "CrestShared/Application/BrowserOnboarding/Models/BrowserOnboardingWelcomeAction.swift",
            "CrestShared/Application/BrowserOnboarding/Services/BrowserOnboardingCoordinator.swift",
            "CrestShared/Application/BrowserOnboarding/Services/BrowserOnboardingProgressPersisting.swift",
            "CrestShared/Application/BrowserOnboarding/Services/BrowserOnboardingProgressStore.swift",
            "CrestShared/Application/BrowserOnboarding/Support/BrowserOnboardingWelcomePolicy.swift",
            "CrestShared/Application/BrowserSpaceDeletion/Models/BrowserSpaceDeletionError.swift",
            "CrestShared/Application/BrowserSpaceDeletion/Services/BrowserSpaceDataDeleting.swift",
            "CrestShared/Application/BrowserSpaceDeletion/Services/BrowserSpaceDataReleaseBarrier.swift",
            "CrestShared/Application/BrowserSpaceDeletion/Support/BrowserSpaceDataReleaseProbe.swift",
            "CrestShared/Infrastructure/UserActivity/BrowserUserActivityBridge.swift",
            "CrestShared/Infrastructure/UserActivity/BrowserUserActivityScriptMessageProxy.swift",
            "CrestMac/Features/Onboarding/Models/BrowserOnboardingImportReadCoordinator.swift",
            "CrestMac/Features/Onboarding/Models/BrowserOnboardingImportReadOutput.swift",
            "CrestMac/Features/Onboarding/Services/BrowserOnboardingImportReading.swift",
            "CrestMac/Features/Onboarding/Services/LiveBrowserOnboardingImportReader.swift",
            "CrestMobile/App/MobileBrowserWindowScene/Models/MobileBrowserWindowSceneModel.swift",
            "CrestMobile/App/MobileBrowserWindowScene/Models/MobileBrowserWindowSceneRoute.swift",
            "CrestShared/Application/Credentials/Models/BrowserCredentialSuggestionModel.swift",
            "CrestShared/Application/Credentials/Models/BrowserStrongPasswordOperationModel.swift",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

    def test_identity_contract_accepts_repository_vocabulary(self) -> None:
        result = subprocess.run(
            [str(REPOSITORY_ROOT / "Scripts/validate-identity.sh")],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
