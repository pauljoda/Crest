#!/usr/bin/env python3
"""Structural contract for Crest's shared Cloud sync ownership."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserSync/Cloud"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserCloudSync"
INFRASTRUCTURE_ROOT = REPOSITORY_ROOT / "CrestShared/Infrastructure/CloudSync"
MODEL_GATEWAY_ADAPTER = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserStore/Sync/BrowserStore+BrowserCloudSyncModelGateway.swift"
)
WORKFLOW_GATEWAY_ADAPTER = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserStore/Sync/BrowserStore+BrowserCloudSyncWorkflowGateway.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserCloudSyncStructureTests(unittest.TestCase):
    def test_cloud_sync_types_have_explicit_layer_owners(self) -> None:
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserCloudSyncEngine.swift").exists()
        )
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserCloudSyncController.swift"
            ).exists()
        )

        required_files = (
            DOMAIN_ROOT / "Models/BrowserCloudConflictResolution.swift",
            DOMAIN_ROOT / "Models/BrowserCloudReconciliationReason.swift",
            DOMAIN_ROOT / "Models/BrowserCloudAccountTransition.swift",
            DOMAIN_ROOT / "Models/BrowserCloudAccountState.swift",
            DOMAIN_ROOT / "Models/BrowserCloudAccountState+Description.swift",
            DOMAIN_ROOT / "Models/BrowserCloudSyncConflictSummary.swift",
            DOMAIN_ROOT / "Models/BrowserCloudSyncDiagnostics.swift",
            DOMAIN_ROOT / "Models/BrowserCloudSyncPhase.swift",
            DOMAIN_ROOT / "Models/BrowserCloudSyncPhase+Description.swift",
            DOMAIN_ROOT / "Policies/BrowserCloudAccountChangePolicy.swift",
            DOMAIN_ROOT / "Policies/BrowserCloudContainerEntitlementPolicy.swift",
            DOMAIN_ROOT / "Policies/BrowserCloudConflictResolutionPolicy.swift",
            APPLICATION_ROOT / "BrowserCloudSyncController.swift",
            APPLICATION_ROOT / "Models/BrowserCloudSyncStatus.swift",
            APPLICATION_ROOT / "Models/BrowserCloudSyncActivity.swift",
            APPLICATION_ROOT / "Models/BrowserCloudSyncConfiguration.swift",
            APPLICATION_ROOT / "Ports/BrowserCloudSyncModelGateway.swift",
            APPLICATION_ROOT / "Ports/BrowserCloudSyncPreferences.swift",
            APPLICATION_ROOT / "Ports/BrowserCloudSyncRemoteService.swift",
            APPLICATION_ROOT / "Ports/BrowserCloudSyncTransport.swift",
            APPLICATION_ROOT / "Ports/BrowserCloudSyncTransportFactory.swift",
            APPLICATION_ROOT / "Ports/BrowserCloudSyncWorkflowGateway.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncState.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncStatePersisting.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncStatePersistenceError.swift",
            INFRASTRUCTURE_ROOT / "UserDefaultsBrowserCloudSyncStatePersistence.swift",
            INFRASTRUCTURE_ROOT / "UserDefaultsBrowserCloudSyncPreferences.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncConfiguration+Bundle.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncController+Production.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncEngine.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncEngine+BrowserCloudSyncTransport.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncEngine+CKSyncEngineDelegate.swift",
            INFRASTRUCTURE_ROOT / "BrowserCloudSnapshotLoader.swift",
            INFRASTRUCTURE_ROOT / "CloudKitBrowserCloudSyncRemoteService.swift",
            INFRASTRUCTURE_ROOT / "CloudKitBrowserCloudSyncTransportFactory.swift",
            MODEL_GATEWAY_ADAPTER,
            WORKFLOW_GATEWAY_ADAPTER,
        )
        for source_path in required_files:
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_path.is_file())

    def test_domain_and_application_cloud_sync_types_are_framework_neutral(self) -> None:
        forbidden_imports = ("CloudKit", "SwiftUI", "WebKit")

        for source_root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for source_path in source_root.rglob("*.swift"):
                source = source_path.read_text()
                with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                    for module in forbidden_imports:
                        self.assertNotIn(f"import {module}\n", source)

        controller_source = (APPLICATION_ROOT / "BrowserCloudSyncController.swift").read_text()
        self.assertNotIn("UserDefaults", controller_source)
        self.assertNotIn("CKContainer", controller_source)
        self.assertNotIn("CKDatabase", controller_source)
        self.assertNotIn("CKError", controller_source)
        self.assertNotIn("Bundle", controller_source)

    def test_each_cloud_sync_source_has_one_matching_primary_declaration(self) -> None:
        source_paths = [
            source_path
            for source_root in (DOMAIN_ROOT, APPLICATION_ROOT, INFRASTRUCTURE_ROOT)
            for source_path in source_root.rglob("*.swift")
        ]
        source_paths.append(MODEL_GATEWAY_ADAPTER)
        source_paths.append(WORKFLOW_GATEWAY_ADAPTER)

        for source_path in source_paths:
            declarations = DECLARATION_PATTERN.findall(source_path.read_text())
            expected_declarations = [] if "+" in source_path.stem else [source_path.stem]
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected_declarations)

    def test_cloudkit_delegate_conformance_stays_in_its_named_adapter_file(self) -> None:
        engine_source = (INFRASTRUCTURE_ROOT / "BrowserCloudSyncEngine.swift").read_text()
        delegate_source = (
            INFRASTRUCTURE_ROOT / "BrowserCloudSyncEngine+CKSyncEngineDelegate.swift"
        ).read_text()

        self.assertIn("actor BrowserCloudSyncEngine", engine_source)
        self.assertNotIn("CKSyncEngineDelegate", engine_source)
        self.assertIn(
            "extension BrowserCloudSyncEngine: CKSyncEngineDelegate",
            delegate_source,
        )

        transport_source = (
            INFRASTRUCTURE_ROOT
            / "BrowserCloudSyncEngine+BrowserCloudSyncTransport.swift"
        ).read_text()
        self.assertIn(
            "extension BrowserCloudSyncEngine: BrowserCloudSyncTransport",
            transport_source,
        )


if __name__ == "__main__":
    unittest.main()
