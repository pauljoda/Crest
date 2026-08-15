#!/usr/bin/env python3
"""Structural contracts for the decomposed shared browser chrome family."""

from __future__ import annotations

import pathlib
import runpy
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHROME_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Chrome"
RESIZE_HANDLE_ROOT = CHROME_ROOT / "Components/BrowserSidebarResizeHandle"
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

CHROME_FOUNDATION_FILES = (
    CHROME_ROOT / "Models/BrowserAddressPlacement.swift",
    CHROME_ROOT / "Models/BrowserChromeAccessibilityDirection.swift",
    CHROME_ROOT / "Models/BrowserKeyboardModifierFlags.swift",
    CHROME_ROOT / "Models/BrowserSidebarNavigationControl.swift",
    CHROME_ROOT / "Models/BrowserSidebarScrollRegion.swift",
    CHROME_ROOT / "Models/BrowserSidebarSection.swift",
    CHROME_ROOT / "Models/BrowserSidebarWidthTransaction.swift",
    CHROME_ROOT / "Models/BrowserUtilityInteractionSurface.swift",
    CHROME_ROOT / "Models/BrowserUtilityPresentationState.swift",
    CHROME_ROOT / "Models/BrowserUtilitySurface.swift",
    CHROME_ROOT / "Support/BrowserChromeAccessibility.swift",
    CHROME_ROOT / "Support/BrowserChromeAnimating+Animation.swift",
    CHROME_ROOT / "Support/BrowserChromeAnimating.swift",
    CHROME_ROOT / "Support/BrowserChromeDirectionPolicy.swift",
    CHROME_ROOT / "Support/BrowserChromeLayout.swift",
    CHROME_ROOT / "Support/BrowserPageSurfacePolicy.swift",
    CHROME_ROOT / "Support/BrowserSettingsVisualPolicy.swift",
    CHROME_ROOT / "Support/BrowserSidebarScrollLayoutPolicy.swift",
    CHROME_ROOT / "Support/BrowserSidebarWidthPreference.swift",
    CHROME_ROOT / "Support/BrowserSpaceCustomizationVisualPolicy.swift",
    CHROME_ROOT / "Support/BrowserSpaceHeaderIconPolicy.swift",
    CHROME_ROOT / "Support/BrowserTabPromotionID.swift",
    RESIZE_HANDLE_ROOT / "BrowserSidebarResizeHandle.swift",
    RESIZE_HANDLE_ROOT / "Support/BrowserSidebarResizeHandleMetrics.swift",
)


class BrowserChromeLayoutStructureTests(unittest.TestCase):
    def test_shared_chrome_foundations_use_standard_feature_buckets(self) -> None:
        for path in CHROME_FOUNDATION_FILES:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        feature_required_files = (
            CHROME_ROOT
            / "Components/BrowserCommandPalette/Models/BrowserCommandPaletteMode.swift",
            CHROME_ROOT / "Models/BrowserCollapsedFolderTabVisibilityState.swift",
            CHROME_ROOT / "Support/BrowserFolderRowPresentationPolicy.swift",
        )
        for path in feature_required_files:
            with self.subTest(path=path):
                self.assertTrue(path.is_file())

        self.assertFalse((CHROME_ROOT / "BrowserChromeLayout").exists())
        self.assertFalse((CHROME_ROOT / "BrowserChromeLayout.swift").exists())

    def test_shared_chrome_foundations_have_exact_file_scope_owners(self) -> None:
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_content = VERTICAL_GUARD["_top_level_global_content"]

        for path in CHROME_FOUNDATION_FILES:
            source = path.read_text()
            primaries = primary_declarations(source)
            extensions = extension_declarations(source)
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                if "+" in path.stem:
                    self.assertEqual(primaries, [])
                    self.assertEqual(len(extensions), 1)
                    self.assertEqual(extensions[0].target, path.stem.split("+", 1)[0])
                else:
                    self.assertEqual([owner.name for owner in primaries], [path.stem])
                    self.assertEqual(extensions, [])
                self.assertEqual(global_content(source), [])

    def test_shared_chrome_foundations_clear_repository_vertical_debt(self) -> None:
        owned_paths = {
            path.relative_to(REPOSITORY_ROOT).as_posix()
            for path in CHROME_FOUNDATION_FILES
        }
        violations = [
            violation.key
            for violation in VERTICAL_GUARD["scan_repository"](REPOSITORY_ROOT)
            if violation.path in owned_paths
        ]
        self.assertEqual(violations, [])

    def test_resize_handle_owns_deterministic_direct_previews(self) -> None:
        source = (RESIZE_HANDLE_ROOT / "BrowserSidebarResizeHandle.swift").read_text()

        self.assertTrue(
            VERTICAL_GUARD["_direct_preview_exists"](
                source,
                "BrowserSidebarResizeHandle",
            )
        )
        self.assertEqual(source.count("@Previewable @State var width"), 2)
        self.assertIn("BrowserChromeLayout.sidebarIdealWidth", source)
        self.assertIn(".environment(\\.layoutDirection, .rightToLeft)", source)
        self.assertNotIn("BrowserSidebarResizeHandlePreview", source)
        self.assertNotIn("UserDefaults", source)
        self.assertFalse((RESIZE_HANDLE_ROOT / "Previews").exists())

    def test_accessibility_navigation_retains_exact_space_identity(self) -> None:
        accessibility = (
            CHROME_ROOT / "Support/BrowserChromeAccessibility.swift"
        ).read_text()
        direction = (
            CHROME_ROOT / "Models/BrowserChromeAccessibilityDirection.swift"
        ).read_text()

        self.assertIn("enum BrowserChromeAccessibilityDirection", direction)
        self.assertIn("case previous", direction)
        self.assertIn("case next", direction)
        self.assertIn("$0.id == selectedSpaceID", accessibility)
        self.assertIn("return spaces[targetIndex].id", accessibility)
        self.assertNotIn("enum Direction", accessibility)

        consumers = (
            REPOSITORY_ROOT / "CrestMac/Features/Sidebar/BrowserSidebar.swift",
            REPOSITORY_ROOT
            / "CrestShared/Features/Chrome/Components/BrowserSpacePager/BrowserSpacePager.swift",
        )
        for consumer in consumers:
            with self.subTest(consumer=consumer.relative_to(REPOSITORY_ROOT)):
                self.assertIn(
                    "BrowserChromeAccessibilityDirection",
                    consumer.read_text(),
                )

    def test_shared_chrome_foundations_are_platform_neutral(self) -> None:
        for path in CHROME_FOUNDATION_FILES:
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(macOS)", source)
                self.assertNotIn("#if os(iOS)", source)

    def test_shared_visual_components_have_platform_seams_and_previews(self) -> None:
        material_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/BrowserAccessibleMaterialBackground"
        )
        settings_root = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/BrowserSettingsControls"
        )

        required_files = (
            material_root / "BrowserAccessibleMaterialBackground.swift",
            settings_root / "Policies/BrowserSettingsControlPolicy.swift",
            settings_root / "Styles/BrowserSettingsIconButtonStyle.swift",
            settings_root / "Styles/BrowserSettingsLabeledActionButtonStyle.swift",
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Accessibility/BrowserVisualAccessibilityPolicy.swift",
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Modifiers/BrowserReadableForegroundModifier.swift",
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Modifiers/View+BrowserReadableForeground.swift",
            REPOSITORY_ROOT
            / "CrestMac/DesignSystem/Colors/CrestPlatformAccessibleSurfaceColor.swift",
            REPOSITORY_ROOT
            / "CrestMobile/DesignSystem/Colors/CrestPlatformAccessibleSurfaceColor.swift",
        )

        for path in required_files:
            with self.subTest(path=path):
                self.assertTrue(path.is_file())

        shared_material = (
            material_root / "BrowserAccessibleMaterialBackground.swift"
        ).read_text()
        self.assertNotIn("import AppKit", shared_material)
        self.assertNotIn("import UIKit", shared_material)
        self.assertNotIn("#if os(", shared_material)
        self.assertIn("#Preview", shared_material)
        self.assertFalse((material_root / "Previews").exists())
        self.assertFalse((settings_root / "Previews").exists())

    def test_platform_only_chrome_declarations_live_in_platform_roots(self) -> None:
        required_mac_files = (
            "CrestMac/App/Policies/BrowserMainWindowSizingPolicy.swift",
            "CrestMac/Features/Browser/Models/BrowserChromeState.swift",
            "CrestMac/Features/Browser/Models/BrowserSidebarPresentation.swift",
            "CrestMac/Features/Browser/Models/BrowserSidebarToggleAction.swift",
            "CrestMac/Features/Browser/Support/BrowserFloatingSidebarThemePolicy.swift",
            "CrestMac/Features/Browser/Support/BrowserSidebarPresentationPolicy.swift",
            "CrestMac/Features/QuickWindow/Support/BrowserQuickWindowChromePolicy.swift",
            "CrestMac/Features/QuickWindow/Support/BrowserQuickWindowLayout.swift",
            "CrestMac/Features/Settings/Models/BrowserSpaceSettingsPresentationState.swift",
            "CrestMac/Features/Settings/Support/BrowserSettingsChromePolicy.swift",
            "CrestMac/Features/WindowAppearance/Support/BrowserWindowTransparencyPolicy.swift",
            "CrestMac/Features/Settings/Support/BrowserSettingsWindowSizing.swift",
            "CrestMac/Features/Sidebar/Models/BrowserSidebarBackgroundAction.swift",
            "CrestMac/Features/Sidebar/Support/BrowserSidebarBackgroundInteractionPolicy.swift",
            "CrestMac/Features/Window/Support/BrowserWindowAccessibility.swift",
            "CrestMac/Features/Peek/Support/BrowserKeyboardModifierFlags+NSEvent.swift",
        )

        for relative_path in required_mac_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

        modifier_bridge = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Peek/Support/BrowserKeyboardModifierFlags+NSEvent.swift"
        ).read_text()
        self.assertIn("import AppKit", modifier_bridge)
        self.assertIn("NSEvent.ModifierFlags", modifier_bridge)


if __name__ == "__main__":
    unittest.main()
