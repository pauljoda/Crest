#!/usr/bin/env python3
"""Ownership and file-structure contracts for keyboard shortcuts."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserShortcuts"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserShortcuts"
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserShortcuts"
)
FEATURE_ROOT = REPOSITORY_ROOT / "CrestShared/Features/BrowserShortcuts"
MAC_SETTINGS_VIEW = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Settings/BrowserShortcutSettingsView.swift"
)
MAC_SETTINGS_FAMILY = MAC_SETTINGS_VIEW.with_suffix("")
MAC_CONTENT_COMPONENTS = (
    MAC_SETTINGS_FAMILY
    / "Components/BrowserShortcutSettingsContent/Components"
)
MAC_LIST_COMPONENTS = MAC_CONTENT_COMPONENTS / "BrowserShortcutList/Components"
MAC_CONTROL_COMPONENTS = (
    MAC_CONTENT_COMPONENTS
    / "BrowserShortcutSettingsControls/Components"
)
MAC_COMMAND_SUPPORT_ROOT = (
    REPOSITORY_ROOT / "CrestMac/Features/Commands/Support"
)
MAC_INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestMac/Infrastructure/BrowserShortcuts"
)

PRIMARY_DECLARATION = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserShortcutStructureTests(unittest.TestCase):
    def test_shortcut_vertical_has_explicit_layer_owners(self) -> None:
        required_paths = (
            DOMAIN_ROOT / "Models/BrowserShortcut.swift",
            DOMAIN_ROOT / "Models/BrowserShortcutCommand.swift",
            DOMAIN_ROOT
            / "Models/BrowserShortcutCommand+DefaultShortcut.swift",
            DOMAIN_ROOT
            / "Models/BrowserShortcutCommand+NumberedSelection.swift",
            DOMAIN_ROOT / "Models/BrowserShortcutCommand+Section.swift",
            DOMAIN_ROOT / "Models/BrowserShortcutKey.swift",
            DOMAIN_ROOT / "Models/BrowserShortcutModifiers.swift",
            DOMAIN_ROOT / "Models/BrowserShortcutOverride.swift",
            DOMAIN_ROOT / "Models/BrowserShortcutSpecialKey.swift",
            DOMAIN_ROOT / "Policies/BrowserShortcutConflictPolicy.swift",
            DOMAIN_ROOT / "Policies/BrowserShortcutDefaultPolicy.swift",
            DOMAIN_ROOT / "Policies/BrowserShortcutSearchPolicy.swift",
            APPLICATION_ROOT / "BrowserShortcutStore.swift",
            APPLICATION_ROOT / "Ports/BrowserShortcutPersisting.swift",
            APPLICATION_ROOT / "Settings/BrowserShortcutSettingsModel.swift",
            APPLICATION_ROOT
            / "Settings/Ports/BrowserShortcutExtensionCommandManaging.swift",
            APPLICATION_ROOT
            / "Settings/Ports/BrowserShortcutSearchProviding.swift",
            INFRASTRUCTURE_ROOT
            / "UserDefaultsBrowserShortcutPersistence.swift",
            INFRASTRUCTURE_ROOT / "InMemoryBrowserShortcutPersistence.swift",
            INFRASTRUCTURE_ROOT / "BrowserShortcutStore+UserDefaults.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserShortcutStore+LaunchComposition.swift",
            FEATURE_ROOT
            / "Support/BrowserShortcutCommand+Presentation.swift",
            FEATURE_ROOT / "Support/BrowserShortcutLocalization.swift",
            FEATURE_ROOT / "Support/BrowserShortcutStore+Search.swift",
            MAC_SETTINGS_VIEW,
            MAC_SETTINGS_FAMILY
            / "Models/BrowserShortcutValidationIssue+Presentation.swift",
            MAC_LIST_COMPONENTS / "BrowserShortcutRow.swift",
            MAC_LIST_COMPONENTS / "BrowserExtensionShortcutRow.swift",
            MAC_SETTINGS_FAMILY
            / "Components/BrowserShortcutSettingsContent.swift",
            MAC_SETTINGS_FAMILY
            / "Support/BrowserShortcutSettingsMetrics.swift",
            MAC_CONTENT_COMPONENTS / "BrowserShortcutRecorder.swift",
            MAC_CONTENT_COMPONENTS
            / "BrowserShortcutRecorder/Support/"
            "BrowserShortcutRecorderCoordinator.swift",
            MAC_CONTENT_COMPONENTS
            / "BrowserShortcutRecorder/Support/"
            "ShortcutRecorderButton.swift",
            MAC_CONTROL_COMPONENTS
            / "BrowserShortcutSearchField/Support/"
            "BrowserShortcutSearchFieldCoordinator.swift",
            MAC_INFRASTRUCTURE_ROOT
            / "BrowserExtensionControllerPool+"
            "BrowserShortcutExtensionCommandManaging.swift",
            MAC_INFRASTRUCTURE_ROOT / "BrowserShortcut+NSEvent.swift",
            MAC_INFRASTRUCTURE_ROOT
            / "BrowserShortcutHardwareKeyCode.swift",
            MAC_COMMAND_SUPPORT_ROOT
            / "BrowserShortcutStore+KeyboardShortcut.swift",
        )
        for path in required_paths:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

    def test_legacy_shortcut_aggregate_files_are_removed(self) -> None:
        legacy_paths = (
            REPOSITORY_ROOT / "CrestShared/Application/BrowserShortcutStore.swift",
            REPOSITORY_ROOT
            / "CrestMac/Features/Settings/BrowserShortcut+SwiftUI.swift",
            REPOSITORY_ROOT
            / "CrestMac/Features/Settings/Components/BrowserShortcutSearchField.swift",
            REPOSITORY_ROOT
            / "CrestMac/Features/Settings/BrowserShortcutSettings",
            FEATURE_ROOT / "Presentation",
        )
        for path in legacy_paths:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertFalse(path.exists())

    def test_domain_and_application_stay_framework_and_transport_neutral(self) -> None:
        domain = "\n".join(
            path.read_text() for path in DOMAIN_ROOT.rglob("*.swift")
        )
        application = "\n".join(
            path.read_text() for path in APPLICATION_ROOT.rglob("*.swift")
        )

        for forbidden in (
            "LocalizedStringResource",
            "String(localized:",
            "SwiftUI",
            "AppKit",
            "UIKit",
            "UserDefaults",
            "JSONEncoder",
            "JSONDecoder",
        ):
            with self.subTest(layer="Domain", forbidden=forbidden):
                self.assertNotIn(forbidden, domain)

        for forbidden in (
            "SwiftUI",
            "AppKit",
            "UIKit",
            "UserDefaults",
            "JSONEncoder",
            "JSONDecoder",
        ):
            with self.subTest(layer="Application", forbidden=forbidden):
                self.assertNotIn(forbidden, application)

    def test_appkit_shortcut_input_stays_in_platform_owners(self) -> None:
        allowed_roots = (
            MAC_INFRASTRUCTURE_ROOT,
            MAC_SETTINGS_FAMILY / "Components",
        )
        shortcut_roots = (
            DOMAIN_ROOT,
            APPLICATION_ROOT,
            INFRASTRUCTURE_ROOT,
            FEATURE_ROOT,
            MAC_SETTINGS_FAMILY,
            MAC_INFRASTRUCTURE_ROOT,
        )
        for root in shortcut_roots:
            for path in root.rglob("*.swift"):
                source = path.read_text()
                if "AppKit" not in source and "NSEvent" not in source:
                    continue
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertTrue(
                        any(path.is_relative_to(owner) for owner in allowed_roots)
                    )

    def test_shortcut_persistence_key_has_one_typed_owner(self) -> None:
        owners = []
        for root_name in ("CrestShared", "CrestMac", "CrestMobile"):
            for path in (REPOSITORY_ROOT / root_name).rglob("*.swift"):
                if "crest.keyboard-shortcuts.v1" in path.read_text():
                    owners.append(path.relative_to(REPOSITORY_ROOT).as_posix())

        self.assertEqual(
            owners,
            [
                "CrestShared/Infrastructure/BrowserShortcuts/"
                "UserDefaultsBrowserShortcutPersistence.swift"
            ],
        )

    def test_shortcut_store_and_settings_view_are_bounded(self) -> None:
        store = APPLICATION_ROOT / "BrowserShortcutStore.swift"
        view = MAC_SETTINGS_VIEW

        self.assertLess(len(store.read_text().splitlines()), 190)
        self.assertLess(len(view.read_text().splitlines()), 180)

    def test_isolated_app_launch_composes_an_in_memory_shortcut_store(self) -> None:
        app = (REPOSITORY_ROOT / "CrestMac/App/CrestApp.swift").read_text()
        settings = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Settings/BrowserSettingsView.swift"
        ).read_text()
        composition = (
            INFRASTRUCTURE_ROOT
            / "BrowserShortcutStore+LaunchComposition.swift"
        ).read_text()

        self.assertIn("BrowserShortcutStore.launch(", app)
        self.assertIn("usesIsolatedLaunch: usesIsolatedLaunch", app)
        self.assertIn("shortcuts: .inMemory()", settings)
        isolation_guard = composition.index("guard !usesIsolatedLaunch")
        persistent_construction = composition.index("persistentPersistence()")
        self.assertLess(isolation_guard, persistent_construction)

    def test_persistent_shortcut_adapter_is_value_semantic_and_explicit(self) -> None:
        port = (
            APPLICATION_ROOT / "Ports/BrowserShortcutPersisting.swift"
        ).read_text()
        adapter = (
            INFRASTRUCTURE_ROOT
            / "UserDefaultsBrowserShortcutPersistence.swift"
        ).read_text()
        convenience = (
            INFRASTRUCTURE_ROOT / "BrowserShortcutStore+UserDefaults.swift"
        ).read_text()
        composition = (
            INFRASTRUCTURE_ROOT
            / "BrowserShortcutStore+LaunchComposition.swift"
        ).read_text()

        self.assertNotIn("AnyObject", port)
        self.assertIn(
            "struct UserDefaultsBrowserShortcutPersistence:",
            adapter,
        )
        self.assertNotIn("defaults: UserDefaults =", adapter)
        self.assertNotIn("defaults: UserDefaults =", convenience)
        self.assertIn("defaults: .standard", composition)

    def test_appkit_shortcut_bridges_follow_the_swiftui_locale(self) -> None:
        recorder = (
            MAC_CONTENT_COMPONENTS / "BrowserShortcutRecorder.swift"
        ).read_text()
        search_field = (
            MAC_CONTROL_COMPONENTS / "BrowserShortcutSearchField.swift"
        ).read_text()
        content = (
            MAC_SETTINGS_FAMILY
            / "Components/BrowserShortcutSettingsContent.swift"
        ).read_text()

        for source in (recorder, search_field):
            self.assertIn("@Environment(\\.locale)", source)
            self.assertIn("BrowserShortcutLocalization.string(", source)
        self.assertIn("messageResource(locale: locale)", content)

    def test_shortcut_production_files_have_one_matching_primary_type(self) -> None:
        roots = (
            DOMAIN_ROOT,
            APPLICATION_ROOT,
            INFRASTRUCTURE_ROOT,
            FEATURE_ROOT,
            MAC_COMMAND_SUPPORT_ROOT,
            MAC_SETTINGS_FAMILY,
            MAC_INFRASTRUCTURE_ROOT,
        )
        for root in roots:
            for path in root.rglob("*.swift"):
                if "Previews" in path.parts or "+" in path.stem:
                    continue
                declarations = PRIMARY_DECLARATION.findall(path.read_text())
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(declarations, [path.stem])

        declarations = PRIMARY_DECLARATION.findall(MAC_SETTINGS_VIEW.read_text())
        self.assertEqual(declarations, [MAC_SETTINGS_VIEW.stem])

    def test_policy_files_do_not_mix_command_or_value_extensions(self) -> None:
        policy_root = DOMAIN_ROOT / "Policies"
        for path in policy_root.glob("*.swift"):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("extension BrowserShortcutCommand", path.read_text())
                self.assertNotIn("extension BrowserShortcut {", path.read_text())

    def test_shortcut_views_have_direct_colocated_previews(self) -> None:
        visual_owners = {
            MAC_SETTINGS_VIEW: "BrowserShortcutSettingsView",
            MAC_SETTINGS_FAMILY
            / "Components/BrowserShortcutSettingsContent.swift":
                "BrowserShortcutSettingsContent",
            MAC_CONTENT_COMPONENTS
            / "BrowserShortcutList.swift": "BrowserShortcutList",
            MAC_LIST_COMPONENTS
            / "BrowserShortcutRow.swift": "BrowserShortcutRow",
            MAC_LIST_COMPONENTS
            / "BrowserExtensionShortcutRow.swift":
                "BrowserExtensionShortcutRow",
            MAC_CONTENT_COMPONENTS
            / "BrowserShortcutSettingsControls.swift":
                "BrowserShortcutSettingsControls",
            MAC_CONTENT_COMPONENTS
            / "BrowserShortcutValidationBanner.swift":
                "BrowserShortcutValidationBanner",
            MAC_CONTENT_COMPONENTS
            / "BrowserShortcutRecorder.swift":
                "BrowserShortcutRecorder",
            MAC_CONTROL_COMPONENTS
            / "BrowserShortcutSearchField.swift":
                "BrowserShortcutSearchField",
        }

        for path, owner in visual_owners.items():
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("#Preview", source)
                self.assertIn(f"{owner}(", source[source.index("#Preview") :])

    def test_shortcut_previews_use_a_deterministic_in_memory_browser(self) -> None:
        factory = (
            MAC_SETTINGS_FAMILY
            / "Support/BrowserShortcutSettingsPreviewFactory.swift"
        ).read_text()

        self.assertNotIn("BrowserStore.preview()", factory)
        self.assertNotIn("UUID()", factory)
        self.assertNotIn(".now", factory)
        self.assertRegex(factory, r"UUID\s*\(\s*uuid:")
        self.assertIn("Date(timeIntervalSince1970:", factory)
        self.assertIn("InMemoryBrowserSessionPersistence()", factory)

    def test_shortcut_input_key_codes_have_one_typed_owner(self) -> None:
        recorder = (
            MAC_CONTENT_COMPONENTS
            / "BrowserShortcutRecorder/Support/"
            "BrowserShortcutRecorderCoordinator.swift"
        ).read_text()
        key_code_owner = (
            MAC_INFRASTRUCTURE_ROOT
            / "BrowserShortcutHardwareKeyCode.swift"
        ).read_text()

        self.assertNotRegex(recorder, r"event\.keyCode\s*==")
        self.assertIn("enum BrowserShortcutHardwareKeyCode: UInt16", key_code_owner)


if __name__ == "__main__":
    unittest.main()
