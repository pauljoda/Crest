#!/usr/bin/env python3
"""Structural contract for the shared BrowserStore responsibility split."""

from __future__ import annotations

import pathlib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
STORE_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserStore"
LAUNCH_ISOLATION_POLICY = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserLaunch/Policies/BrowserLaunchIsolationPolicy.swift"
)


class BrowserStoreStructureTests(unittest.TestCase):
    def test_store_uses_one_root_type_and_responsibility_extensions(self) -> None:
        required_files = (
            "BrowserStore.swift",
            "Lifecycle/BrowserStore+Lifecycle.swift",
            "Navigation/BrowserStore+Selection.swift",
            "Tabs/BrowserStore+TabOpening.swift",
            "Tabs/BrowserStore+TabMetadata.swift",
            "Tabs/BrowserStore+TabOrganization.swift",
            "Folders/BrowserStore+Folders.swift",
            "History/BrowserStore+HistoryAndCleanup.swift",
            "Spaces/BrowserStore+SpacesAndImport.swift",
            "Credentials/BrowserStore+CredentialPreferences.swift",
            "Credentials/BrowserStore+CredentialLookup.swift",
            "Credentials/BrowserStore+CredentialSaving.swift",
            "Sync/BrowserStore+SyncAndPersistence.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((STORE_ROOT / relative_path).is_file())

        root_source = (STORE_ROOT / "BrowserStore.swift").read_text()
        self.assertEqual(root_source.count("final class BrowserStore"), 1)
        self.assertLess(len(root_source.splitlines()), 150)
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Application/BrowserStore.swift").exists()
        )

    def test_store_collaborators_and_policies_have_named_files(self) -> None:
        required_files = (
            "Family/BrowserStoreFamily.swift",
            "Fixtures/BrowserPerformanceSoakFixture.swift",
            "Models/BrowserCredentialSaveKey.swift",
            "Models/BrowserCredentialSaveOperation.swift",
            "Models/BrowserStoreSyncStageUrgency.swift",
            "Models/BrowserTabSelectionHistory.swift",
            "Models/BrowserRuntimeSessionProjection.swift",
            "Policies/BrowserCredentialRecencyPolicy.swift",
            "Policies/BrowserStartupBehavior.swift",
            "Policies/BrowserStartupPreference.swift",
            "Policies/BrowserStoredStringPolicy.swift",
            "Policies/BrowserTabInsertionPolicy.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((STORE_ROOT / relative_path).is_file())

        root_source = (STORE_ROOT / "BrowserStore.swift").read_text()
        self.assertIn("private(set) var sessionRevision", root_source)

    def test_launch_isolation_policy_is_owned_by_the_launch_feature(self) -> None:
        self.assertTrue(LAUNCH_ISOLATION_POLICY.is_file())
        self.assertFalse(
            (STORE_ROOT / "Policies/BrowserLaunchIsolationPolicy.swift").exists()
        )


if __name__ == "__main__":
    unittest.main()
