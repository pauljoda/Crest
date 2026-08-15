#!/usr/bin/env python3

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class SettingsPlatformOwnershipTests(unittest.TestCase):
    def test_shared_settings_shells_have_no_platform_compile_branches(self) -> None:
        for relative_path in (
            "CrestShared/Features/Settings/Models/BrowserSettingsDestination.swift",
            "CrestShared/Features/Settings/BrowserGeneralSettingsPane.swift",
            "CrestShared/Features/Settings/Components/BrowserSettingsPane.swift",
            "CrestShared/Features/Settings/Components/BrowserSettingsPaneHeader/BrowserSettingsPaneHeader.swift",
        ):
            source = (REPOSITORY_ROOT / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertNotIn("#if os(", source)
                self.assertNotIn("#elseif os(", source)

    def test_platform_settings_implementations_live_in_platform_roots(self) -> None:
        relative_paths = (
            "CrestMac/Features/Settings/Support/BrowserPlatformSettingsDestinationCatalog.swift",
            "CrestMac/Features/WindowAppearance/Components/BrowserPlatformAppearanceSettingsSection.swift",
            "CrestMac/Features/Settings/Components/BrowserPlatformSettingsPaneContainer.swift",
            "CrestMobile/Features/Settings/Support/BrowserPlatformSettingsDestinationCatalog.swift",
            "CrestMobile/Features/Settings/Support/BrowserPlatformAppearanceSettingsSection.swift",
            "CrestMobile/Features/Settings/Components/BrowserPlatformSettingsPaneContainer.swift",
        )
        for relative_path in relative_paths:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

    def test_shared_settings_shells_delegate_platform_behavior(self) -> None:
        destination = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Settings/Models/BrowserSettingsDestination.swift"
        ).read_text()
        general = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Settings/BrowserGeneralSettingsPane.swift"
        ).read_text()
        container = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Settings/Components/BrowserSettingsPane.swift"
        ).read_text()

        self.assertIn("BrowserPlatformSettingsDestinationCatalog.cases", destination)
        self.assertIn(
            "BrowserPlatformSettingsDestinationCatalog.isAvailable(self)",
            destination,
        )
        self.assertIn("BrowserPlatformAppearanceSettingsSection()", general)
        self.assertIn("BrowserPlatformSettingsPaneContainer", container)

    def test_platform_catalogs_preserve_destination_availability(self) -> None:
        mac = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Settings/Support/BrowserPlatformSettingsDestinationCatalog.swift"
        ).read_text()
        mobile = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Settings/Support/BrowserPlatformSettingsDestinationCatalog.swift"
        ).read_text()

        self.assertIn("BrowserSettingsDestination.allCases", mac)
        self.assertIn("true", mac)
        self.assertIn("BrowserSettingsDestination.allCases.filter(isAvailable)", mobile)
        self.assertIn("destination != .shortcuts", mobile)

    def test_platform_panes_preserve_native_form_contracts(self) -> None:
        mac_root = REPOSITORY_ROOT / "CrestMac/Features/Settings/Components"
        mobile_root = REPOSITORY_ROOT / "CrestMobile/Features/Settings/Components"
        mac_appearance = (
            REPOSITORY_ROOT
            / "CrestMac/Features/WindowAppearance/Components/BrowserPlatformAppearanceSettingsSection.swift"
        ).read_text()
        mac_controls = (
            REPOSITORY_ROOT
            / "CrestMac/Features/WindowAppearance/Components/BrowserWindowTransparencyControls.swift"
        ).read_text()
        mobile_appearance = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Settings/Support/BrowserPlatformAppearanceSettingsSection.swift"
        ).read_text()
        mac_container = (
            mac_root / "BrowserPlatformSettingsPaneContainer.swift"
        ).read_text()
        mobile_container = (
            mobile_root / "BrowserPlatformSettingsPaneContainer.swift"
        ).read_text()

        self.assertIn('Section("Appearance")', mac_appearance)
        self.assertIn(
            "@Environment(BrowserWindowTransparencyStore.self)",
            mac_controls,
        )
        self.assertNotIn("@AppStorage", mac_appearance + mac_controls)
        self.assertIn(
            "typealias BrowserPlatformAppearanceSettingsSection = EmptyView",
            mobile_appearance,
        )
        self.assertIn(".crestSettingsForm()", mac_container)
        self.assertIn("layout: .mobilePage", mobile_container)
        for source in (mac_container, mobile_container):
            self.assertIn('"settings-form-\\(destination.rawValue)"', source)

    def test_platform_shells_are_flat_and_preview_visible_content(self) -> None:
        visible_components = (
            "CrestMac/Features/Settings/Components/BrowserPlatformExtensionAddSection.swift",
            "CrestMac/Features/Settings/Components/BrowserPlatformPrivacyScopeFootnote.swift",
            "CrestMobile/Features/Settings/Components/BrowserPlatformPrivacyScopeFootnote.swift",
        )
        for relative_path in visible_components:
            source = (REPOSITORY_ROOT / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertIn("#Preview", source)

        # Extensions are a macOS-only feature, so mobile's add section renders
        # nothing and has no preview to keep. It exists only so the shared
        # extensions view compiles for the mobile target.
        mobile_add_section = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Settings/Components/BrowserPlatformExtensionAddSection.swift"
        ).read_text()
        self.assertIn("macOS-only feature", mobile_add_section)
        self.assertIn("EmptyView()", mobile_add_section)
        self.assertIn("Intentionally Empty", mobile_add_section)
        self.assertNotIn("Button", mobile_add_section)

        for platform in ("CrestMac", "CrestMobile"):
            root = REPOSITORY_ROOT / platform / "Features/Settings"
            with self.subTest(platform=platform):
                self.assertFalse((root / "Platform").exists())

        mac_root = REPOSITORY_ROOT / "CrestMac/Features/Settings"
        self.assertFalse((mac_root / "Policies").exists())
        self.assertFalse((mac_root / "Window").exists())
        bridge = (
            mac_root / "Components/BrowserSettingsWindowSizingBridge.swift"
        ).read_text()
        host = (
            mac_root / "Components/BrowserSettingsWindowSizingHostView.swift"
        ).read_text()
        self.assertNotIn("class HostView", bridge)
        self.assertIn("final class BrowserSettingsWindowSizingHostView", host)


if __name__ == "__main__":
    unittest.main()
