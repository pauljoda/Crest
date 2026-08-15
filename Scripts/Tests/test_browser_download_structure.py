#!/usr/bin/env python3
"""Structural contract for browser-download ownership."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOWNLOAD_DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserDownloads"
DOWNLOAD_INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/Downloads"
)
DOWNLOAD_PRESENTATION_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Features/Downloads/Support"
)
SITE_PERMISSION_CENTER = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserSitePermissions/BrowserSitePermissionCenter.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserDownloadStructureTests(unittest.TestCase):
    def test_download_domain_uses_feature_local_named_owners(self) -> None:
        required_files = (
            "AutomaticDownloads/BrowserAutomaticDownloadAction.swift",
            "AutomaticDownloads/BrowserAutomaticDownloadPolicy.swift",
            "Ledger/BrowserDownloadLedger.swift",
            "Models/BrowserDownloadItem.swift",
            "Policies/BrowserDownloadProgressPolicy.swift",
            "Risk/BrowserDownloadRiskAssessment.swift",
            "Risk/BrowserDownloadRiskReason.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((DOWNLOAD_DOMAIN_ROOT / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserDownloadCenter.swift"
            ).exists()
        )

        presentation_path = (
            DOWNLOAD_PRESENTATION_ROOT
            / "BrowserDownloadRiskReason+Presentation.swift"
        )
        self.assertTrue(presentation_path.is_file())
        self.assertIn("var message: String", presentation_path.read_text())
        self.assertIn("var warningMessage: LocalizedStringResource", presentation_path.read_text())
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserDownloadRiskAssessment.swift"
            ).exists()
        )
        self.assertFalse(
            (
                DOWNLOAD_INFRASTRUCTURE_ROOT
                / "BrowserDownloadProgressPolicy.swift"
            ).exists()
        )

        decision_path = (
            REPOSITORY_ROOT
            / "CrestShared/Domain/BrowserSitePermissions/Models/BrowserSitePermissionDecision.swift"
        )
        self.assertTrue(decision_path.is_file())
        self.assertIn(
            "enum BrowserSitePermissionDecision",
            decision_path.read_text(),
        )
        self.assertNotIn(
            "enum BrowserSitePermissionDecision",
            SITE_PERMISSION_CENTER.read_text(),
        )

    def test_each_download_source_has_one_matching_primary_declaration(self) -> None:
        source_paths = [
            source_path
            for source_root in (DOWNLOAD_DOMAIN_ROOT, DOWNLOAD_INFRASTRUCTURE_ROOT)
            for source_path in source_root.rglob("*.swift")
        ]

        for source_path in source_paths:
            declarations = DECLARATION_PATTERN.findall(source_path.read_text())
            expected_declarations = [] if "+" in source_path.stem else [source_path.stem]
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected_declarations)

    def test_download_domain_remains_framework_neutral(self) -> None:
        forbidden_imports = (
            "Combine",
            "Observation",
            "SwiftUI",
            "UniformTypeIdentifiers",
            "WebKit",
        )
        for source_path in DOWNLOAD_DOMAIN_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source_path=source_path.relative_to(DOWNLOAD_DOMAIN_ROOT)):
                for module in forbidden_imports:
                    self.assertNotIn(f"import {module}", source)

        risk_reason_source = (
            DOWNLOAD_DOMAIN_ROOT / "Risk/BrowserDownloadRiskReason.swift"
        ).read_text()
        self.assertNotIn("LocalizedStringResource", risk_reason_source)
        self.assertNotIn("This file type can install or run software.", risk_reason_source)

    def test_webkit_delegate_conformance_has_a_named_infrastructure_owner(self) -> None:
        center_path = DOWNLOAD_INFRASTRUCTURE_ROOT / "BrowserDownloadCenter.swift"
        delegate_path = (
            DOWNLOAD_INFRASTRUCTURE_ROOT
            / "BrowserDownloadCenter+WKDownloadDelegate.swift"
        )
        self.assertTrue(center_path.is_file())
        self.assertTrue(delegate_path.is_file())

        center_source = center_path.read_text()
        delegate_source = delegate_path.read_text()
        self.assertIn("final class BrowserDownloadCenter: NSObject", center_source)
        self.assertNotIn(
            "final class BrowserDownloadCenter: NSObject, WKDownloadDelegate",
            center_source,
        )
        self.assertIn(
            "extension BrowserDownloadCenter: WKDownloadDelegate",
            delegate_source,
        )
        self.assertIn("BrowserPlatformDownloadDirectory.url", center_source)
        self.assertIn("BrowserDownloadQuarantine(", center_source)

    def test_retry_registration_revalidates_after_the_webkit_await(self) -> None:
        lease_path = (
            DOWNLOAD_INFRASTRUCTURE_ROOT
            / "Models/BrowserDownloadRetryLease.swift"
        )
        policy_path = (
            DOWNLOAD_INFRASTRUCTURE_ROOT
            / "Policies/BrowserDownloadRetryRegistrationPolicy.swift"
        )
        self.assertTrue(lease_path.is_file())
        self.assertTrue(policy_path.is_file())

        center_source = (
            DOWNLOAD_INFRASTRUCTURE_ROOT / "BrowserDownloadCenter.swift"
        ).read_text()
        self.assertIn("BrowserDownloadRetryLease(", center_source)
        self.assertIn(
            "BrowserDownloadRetryRegistrationPolicy.shouldRegister(",
            center_source,
        )
        self.assertIn("retryLeases.removeValue(forKey: itemID)", center_source)
        self.assertIn(
            "isAssignmentAvailable: isAssignmentAvailable(assignment)",
            center_source,
        )
        self.assertRegex(
            center_source,
            r"guard\s+BrowserDownloadRetryRegistrationPolicy\.shouldRegister\([\s\S]*?"
            r"else \{[\s\S]*?rejectRetryRegistration",
        )
        self.assertIn("download.cancel", center_source)
        self.assertRegex(
            center_source,
            r"func cancel\(_ itemID: UUID\)[\s\S]*?"
            r"retryLeases\.removeValue\(forKey: itemID\)[\s\S]*?"
            r"ledger\.cancel\(itemID",
        )

        caller_paths = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Sidebar/BrowserSidebar/Services/BrowserSidebarUtilityCoordinator.swift",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Sidebar/MobileBrowserSidebar/Services/MobileBrowserSidebarUtilityCoordinator.swift",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Downloads/MobileDownloadsView.swift",
        )
        for caller_path in caller_paths:
            source = caller_path.read_text()
            with self.subTest(caller_path=caller_path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("retryAutomaticDownload(", source)
                self.assertIn("matching: assignment", source)
                self.assertIn("BrowserSidebarAccessPolicy.unlockedSpace(", source)
                self.assertIn("expectedAssignment", source)

    def test_download_sources_remain_bounded(self) -> None:
        for source_path in DOWNLOAD_DOMAIN_ROOT.rglob("*.swift"):
            with self.subTest(source_path=source_path.relative_to(DOWNLOAD_DOMAIN_ROOT)):
                self.assertLess(len(source_path.read_text().splitlines()), 220)

        center_path = DOWNLOAD_INFRASTRUCTURE_ROOT / "BrowserDownloadCenter.swift"
        self.assertLess(len(center_path.read_text().splitlines()), 600)


if __name__ == "__main__":
    unittest.main()
