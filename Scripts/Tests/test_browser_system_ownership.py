#!/usr/bin/env python3
"""Ownership contracts for default-browser and passkey application systems."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class BrowserSystemOwnershipTests(unittest.TestCase):
    def test_observable_controllers_live_in_application(self) -> None:
        controller_paths = (
            "CrestShared/Application/BrowserDefaultBrowser/BrowserDefaultBrowserController.swift",
            "CrestShared/Application/BrowserPasskeyAccess/BrowserPasskeyAccessController.swift",
        )

        for relative_path in controller_paths:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

        old_paths = (
            "CrestShared/Domain/BrowserDefaultBrowser/BrowserDefaultBrowserController.swift",
            "CrestShared/Domain/BrowserPasskeyAccess/Controllers/BrowserPasskeyAccessController.swift",
        )
        for relative_path in old_paths:
            with self.subTest(relative_path=relative_path):
                self.assertFalse((REPOSITORY_ROOT / relative_path).exists())

    def test_controllers_retain_injected_system_seams(self) -> None:
        expectations = {
            "CrestShared/Application/BrowserDefaultBrowser/BrowserDefaultBrowserController.swift": (
                "typealias StatusCheck",
                "typealias DefaultRequest",
                "typealias SettingsOpener",
                "statusCheck: @escaping StatusCheck",
                "defaultRequest: @escaping DefaultRequest",
                "settingsOpener: @escaping SettingsOpener",
            ),
            "CrestShared/Application/BrowserPasskeyAccess/BrowserPasskeyAccessController.swift": (
                "typealias CapabilityCheck",
                "typealias DeviceConfigurationCheck",
                "typealias AuthorizationCheck",
                "typealias AuthorizationRequester",
                "capabilityCheck: @escaping CapabilityCheck",
                "deviceConfigurationCheck: @escaping DeviceConfigurationCheck",
                "authorizationCheck: @escaping AuthorizationCheck",
                "authorizationRequester: @escaping AuthorizationRequester",
            ),
        }

        for relative_path, required_fragments in expectations.items():
            path = REPOSITORY_ROOT / relative_path
            self.assertTrue(path.is_file())
            source = path.read_text()
            for fragment in required_fragments:
                with self.subTest(relative_path=relative_path, fragment=fragment):
                    self.assertIn(fragment, source)

    def test_framework_neutral_values_and_policies_remain_in_domain(self) -> None:
        domain_paths = (
            "CrestShared/Domain/BrowserDefaultBrowser/Models/BrowserDefaultBrowserRequestStyle.swift",
            "CrestShared/Domain/BrowserDefaultBrowser/Models/BrowserDefaultBrowserStatus.swift",
            "CrestShared/Domain/BrowserDefaultBrowser/Policies/BrowserExternalURLPolicy.swift",
            "CrestShared/Domain/BrowserPasskeyAccess/Models/BrowserPasskeyAccessStatus.swift",
            "CrestShared/Domain/BrowserPasskeyAccess/Models/BrowserPasskeyAuthorizationState.swift",
            "CrestShared/Domain/BrowserPasskeyAccess/Models/BrowserPasskeyDeviceConfiguration.swift",
            "CrestShared/Domain/BrowserPasskeyAccess/Policies/BrowserPasskeyAccessPolicy.swift",
            "CrestShared/Domain/BrowserPasskeyAccess/Policies/BrowserSystemPasswordWriteThroughPolicy.swift",
        )

        for relative_path in domain_paths:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

    def test_authentication_services_adapters_live_in_shared_infrastructure(self) -> None:
        required_paths = (
            "CrestShared/Infrastructure/BrowserPasskeyAccess/BrowserPasskeyAuthorizationSystem.swift",
            "CrestShared/Infrastructure/BrowserPasskeyAccess/BrowserPasskeyAuthorizationState+AuthenticationServices.swift",
        )
        for relative_path in required_paths:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

        old_paths = (
            "CrestShared/Domain/BrowserPasskeyAccess/Systems/BrowserPasskeyAuthorizationSystem.swift",
            "CrestShared/Domain/BrowserPasskeyAccess/Extensions/BrowserPasskeyAuthorizationState+AuthenticationServices.swift",
        )
        for relative_path in old_paths:
            with self.subTest(relative_path=relative_path):
                self.assertFalse((REPOSITORY_ROOT / relative_path).exists())

    def test_platform_systems_live_in_platform_infrastructure(self) -> None:
        system_files = (
            "BrowserDefaultBrowser/BrowserPlatformDefaultBrowserSystem.swift",
            "BrowserDefaultBrowser/BrowserPlatformDefaultBrowserErrorPolicy.swift",
            "BrowserPasskeyAccess/BrowserPasskeyAccessSystem.swift",
            "BrowserPasskeyAccess/BrowserSystemPasswordWriteThroughSystem.swift",
        )

        for platform_root in ("CrestMac", "CrestMobile"):
            for relative_path in system_files:
                with self.subTest(platform_root=platform_root, relative_path=relative_path):
                    self.assertTrue(
                        (
                            REPOSITORY_ROOT
                            / platform_root
                            / "Infrastructure"
                            / relative_path
                        ).is_file()
                    )
                    self.assertFalse(
                        (
                            REPOSITORY_ROOT
                            / platform_root
                            / "Domain"
                            / relative_path
                        ).exists()
                    )

    def test_domain_roots_do_not_import_platform_frameworks(self) -> None:
        forbidden_imports = (
            "import AuthenticationServices",
            "import AppKit",
            "import UIKit",
            "import WebKit",
        )

        for domain_root in (
            "CrestShared/Domain",
            "CrestMac/Domain",
            "CrestMobile/Domain",
        ):
            for path in (REPOSITORY_ROOT / domain_root).rglob("*.swift"):
                source = path.read_text()
                for forbidden_import in forbidden_imports:
                    with self.subTest(
                        path=path.relative_to(REPOSITORY_ROOT),
                        forbidden_import=forbidden_import,
                    ):
                        self.assertNotIn(forbidden_import, source)


if __name__ == "__main__":
    unittest.main()
