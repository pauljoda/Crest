#!/usr/bin/env python3
"""Structural contracts for passkey policy and native system bridges."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserPasskeyAccess"
APPLICATION_CONTROLLER = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserPasskeyAccess/BrowserPasskeyAccessController.swift"
)
SHARED_INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserPasskeyAccess"
)
SYSTEM_PASSWORD_AVAILABILITY = (
    DOMAIN_ROOT / "Models/BrowserSystemPasswordWriteThroughAvailability.swift"
)
SYSTEM_PASSWORD_AVAILABILITY_PRESENTATION = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Credentials/Support/BrowserSystemPasswordWriteThroughAvailability+Presentation.swift"
)


class BrowserPasskeyPlatformOwnershipTests(unittest.TestCase):
    def test_passkey_owners_use_named_layered_files(self) -> None:
        domain_files = (
            "Models/BrowserPasskeyAccessStatus.swift",
            "Models/BrowserPasskeyAuthorizationState.swift",
            "Models/BrowserPasskeyCredentialAccessScope.swift",
            "Models/BrowserPasskeyDeviceConfiguration.swift",
            "Models/BrowserPasskeyPrivacyBoundary.swift",
            "Models/BrowserPasskeyWebsiteSessionScope.swift",
            "Models/BrowserSystemPasswordWriteThroughAvailability.swift",
            "Models/BrowserSystemPasswordWriteThroughError.swift",
            "Policies/BrowserPasskeyAccessPolicy.swift",
            "Policies/BrowserSystemPasswordWriteThroughPolicy.swift",
        )
        for relative_path in domain_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((DOMAIN_ROOT / relative_path).is_file())

        for path in (
            APPLICATION_CONTROLLER,
            SHARED_INFRASTRUCTURE_ROOT / "BrowserPasskeyAuthorizationSystem.swift",
            SHARED_INFRASTRUCTURE_ROOT
            / "BrowserPasskeyAuthorizationState+AuthenticationServices.swift",
        ):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserPasskeyAccess.swift").exists()
        )
        for legacy_path in (
            DOMAIN_ROOT / "Controllers/BrowserPasskeyAccessController.swift",
            DOMAIN_ROOT
            / "Extensions/BrowserPasskeyAuthorizationState+AuthenticationServices.swift",
            DOMAIN_ROOT / "Systems/BrowserPasskeyAuthorizationSystem.swift",
        ):
            with self.subTest(legacy_path=legacy_path.relative_to(REPOSITORY_ROOT)):
                self.assertFalse(legacy_path.exists())

    def test_shared_passkey_domain_has_no_platform_compile_branches(self) -> None:
        for path in DOMAIN_ROOT.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path):
                self.assertNotIn("import AuthenticationServices", source)
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("import Security", source)
                self.assertNotIn("#if os(", source)

    def test_system_password_availability_copy_stays_in_credentials_presentation(self) -> None:
        self.assertTrue(SYSTEM_PASSWORD_AVAILABILITY_PRESENTATION.is_file())
        domain_source = SYSTEM_PASSWORD_AVAILABILITY.read_text()
        presentation_source = SYSTEM_PASSWORD_AVAILABILITY_PRESENTATION.read_text()

        self.assertNotIn("import ", domain_source)
        self.assertNotIn("LocalizedStringResource", domain_source)
        self.assertNotIn("var detail", domain_source)
        self.assertNotRegex(domain_source, r'"[^"]+"')
        self.assertNotRegex(domain_source, r"\b(?:var|func)\s+")
        self.assertIn(
            "extension BrowserSystemPasswordWriteThroughAvailability",
            presentation_source,
        )
        self.assertIn("var detail: LocalizedStringResource", presentation_source)

    def test_each_platform_owns_capability_and_write_through_systems(self) -> None:
        for platform_root in ("CrestMac", "CrestMobile"):
            root = REPOSITORY_ROOT / platform_root / "Infrastructure/BrowserPasskeyAccess"
            for name in (
                "BrowserPasskeyAccessSystem.swift",
                "BrowserSystemPasswordWriteThroughSystem.swift",
            ):
                with self.subTest(platform_root=platform_root, name=name):
                    self.assertTrue((root / name).is_file())

        mac = (
            REPOSITORY_ROOT
            / "CrestMac/Infrastructure/BrowserPasskeyAccess/BrowserPasskeyAccessSystem.swift"
        ).read_text()
        mobile = (
            REPOSITORY_ROOT
            / "CrestMobile/Infrastructure/BrowserPasskeyAccess/BrowserPasskeyAccessSystem.swift"
        ).read_text()
        self.assertIn("SecTaskCopyValueForEntitlement", mac)
        self.assertIn("CrestBrowserPasskeyManagedCapability", mobile)

        shared_infrastructure = "\n".join(
            path.read_text()
            for path in SHARED_INFRASTRUCTURE_ROOT.rglob("*.swift")
        )
        self.assertIn("import AuthenticationServices", shared_infrastructure)

    def test_status_copy_is_explicitly_localized(self) -> None:
        source = (
            REPOSITORY_ROOT
            / "CrestShared/Domain/BrowserPasskeyAccess/Models/BrowserPasskeyAccessStatus.swift"
        ).read_text()
        self.assertIn("String(localized:", source)

    def test_visual_passkey_status_has_a_named_family_and_previews(self) -> None:
        root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Credentials/BrowserPasskeyAccessView"
        )
        self.assertTrue((root / "BrowserPasskeyAccessView.swift").is_file())
        self.assertIn(
            "#Preview",
            (root / "BrowserPasskeyAccessView.swift").read_text(),
        )
        self.assertFalse((root / "Previews").exists())
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Features/Credentials/BrowserPasskeyAccessView.swift"
            ).exists()
        )


if __name__ == "__main__":
    unittest.main()
