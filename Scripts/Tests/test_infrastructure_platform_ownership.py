#!/usr/bin/env python3
"""Platform ownership contracts for shared WebKit and download infrastructure."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class InfrastructurePlatformOwnershipTests(unittest.TestCase):
    def test_shared_infrastructure_has_no_platform_compile_branches(self) -> None:
        for relative_path in (
            "CrestShared/Infrastructure/BrowserPageConfiguration.swift",
            "CrestShared/Infrastructure/BrowserDownloadTransfer/BrowserDownloadTransfer.swift",
            "CrestShared/Infrastructure/BrowserDownloadTransfer/Models/BrowserDownloadQuarantine.swift",
            "CrestShared/Infrastructure/Downloads/BrowserDownloadCenter.swift",
            "CrestShared/Infrastructure/Downloads/BrowserDownloadCenter+WKDownloadDelegate.swift",
            "CrestShared/Infrastructure/Downloads/BrowserDownloadRiskAssessment+Assessment.swift",
            "CrestShared/Infrastructure/CloudSync/CloudKitBrowserCloudSyncRemoteService.swift",
        ):
            source = (REPOSITORY_ROOT / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertNotIn("#if os(", source)
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("import CoreServices", source)

        extension_root = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/WebKit/BrowserExtensions"
        )
        for path in extension_root.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(relative_path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("#if os(", source)
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("import CoreServices", source)

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserDownloadTransfer.swift"
            ).exists()
        )

    def test_each_platform_owns_user_agent_and_quarantine_behavior(self) -> None:
        for platform_root in ("CrestMac", "CrestMobile"):
            for relative_path in (
                "Infrastructure/WebKit/BrowserPlatformUserAgent.swift",
                "Infrastructure/Downloads/BrowserPlatformDownloadQuarantine.swift",
                "Infrastructure/Downloads/BrowserPlatformDownloadDirectory.swift",
                "Infrastructure/CloudSync/BrowserPlatformCloudContainerEntitlementPolicy.swift",
            ):
                path = REPOSITORY_ROOT / platform_root / relative_path
                with self.subTest(path=path):
                    self.assertTrue(path.is_file())

    def test_download_center_delegates_destination_ownership_to_the_platform(self) -> None:
        shared_source = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/Downloads/BrowserDownloadCenter.swift"
        ).read_text()
        self.assertIn("BrowserPlatformDownloadDirectory.url", shared_source)
        self.assertIn("BrowserDownloadQuarantine(", shared_source)

    def test_cloud_sync_delegates_entitlement_validation_to_the_platform(self) -> None:
        shared_source = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/CloudSync/CloudKitBrowserCloudSyncRemoteService.swift"
        ).read_text()
        self.assertIn(
            "BrowserPlatformCloudContainerEntitlementPolicy.currentProcessContainsContainer",
            shared_source,
        )
        self.assertNotIn("SecTask", shared_source)

    def test_extension_page_provider_conformance_lives_with_native_page_store(self) -> None:
        shared_source = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/WebKit/BrowserExtensions/BrowserExtensionPageProviding.swift"
        ).read_text()
        self.assertNotIn("BrowserPagePool: BrowserExtensionPageProviding", shared_source)
        self.assertNotIn("MobileBrowserPageStore: BrowserExtensionPageProviding", shared_source)

        mac = (
            REPOSITORY_ROOT
            / "CrestMac/Infrastructure/WebKit/BrowserExtensionPageProviderConformance.swift"
        ).read_text()
        self.assertIn("BrowserPagePool: BrowserExtensionPageProviding", mac)
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Infrastructure/WebKit/BrowserExtensionPageProviderConformance.swift"
            ).exists(),
            "The mobile page store hosts no extensions, so it provides no pages to one.",
        )

    def test_desktop_web_view_is_owned_by_the_mac_root(self) -> None:
        self.assertTrue(
            (
                REPOSITORY_ROOT
                / "CrestMac/Infrastructure/WebKit/BrowserDesktopWebView.swift"
            ).is_file()
        )
        shared_source = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/BrowserPageConfiguration.swift"
        ).read_text()
        self.assertNotIn("class BrowserDesktopWebView", shared_source)

    def test_extension_compatibility_values_and_presentation_live_inward(self) -> None:
        domain_root = (
            REPOSITORY_ROOT
            / "CrestShared/Domain/BrowserExtensions"
        )
        required_domain_files = (
            "Models/BrowserExtensionAccessDecision.swift",
            "Models/BrowserExtensionCompatibilitySource.swift",
            "Models/BrowserExtensionCompatibilityIssueKind.swift",
            "Models/BrowserExtensionNativeMessagingCapability.swift",
            "Models/BrowserExtensionCompatibilityIssue.swift",
            "Models/BrowserExtensionCompatibilityAssessment.swift",
            "Models/BrowserExtensionCompatibilityError.swift",
            "Models/BrowserExtensionPermissionSnapshot.swift",
            "Policies/BrowserExtensionCompatibilityPolicy.swift",
            "Policies/BrowserExtensionInstallationPermissionPolicy.swift",
        )
        for relative_path in required_domain_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((domain_root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserExtensionCompatibility.swift"
            ).exists()
        )
        policy = (
            domain_root
            / "Policies/BrowserExtensionCompatibilityPolicy.swift"
        ).read_text()
        self.assertNotIn("String(localized:", policy)
        self.assertNotIn("currentBuild", policy)

        presentation_root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView/Models"
        )
        self.assertTrue(
            (
                presentation_root
                / "BrowserExtensionCompatibilityPresentation.swift"
            ).is_file()
        )
        self.assertTrue(
            (
                presentation_root
                / "BrowserExtensionCompatibilityError+LocalizedError.swift"
            ).is_file()
        )

    def test_macos_owns_native_messaging_capability_detection(self) -> None:
        relative_path = (
            "Infrastructure/WebKit/Extensions/Compatibility/"
            "BrowserPlatformExtensionNativeMessagingCapability.swift"
        )
        mac = (REPOSITORY_ROOT / "CrestMac" / relative_path).read_text()

        self.assertIn("import Security", mac)
        self.assertIn("SecTaskCreateFromSelf", mac)
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestMobile" / relative_path).exists(),
            "Native messaging serves extensions, which mobile does not host.",
        )

    def test_mobile_owns_its_icloud_passwords_capability_outside_extensions(self) -> None:
        mobile = (
            REPOSITORY_ROOT
            / "CrestMobile/Infrastructure/WebKit/Compatibility/BrowserICloudPasswordsCapability+Mobile.swift"
        )
        self.assertTrue(
            mobile.is_file(),
            "Saved-password capability detection is a credential concern, not an "
            "extension one, so it outlives the removed mobile extension tree.",
        )
        self.assertIn(".unavailableOnPlatform", mobile.read_text())
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Infrastructure/WebKit/Extensions/Compatibility"
            ).exists(),
            "Saved-password capability detection must not live under Extensions.",
        )


if __name__ == "__main__":
    unittest.main()
