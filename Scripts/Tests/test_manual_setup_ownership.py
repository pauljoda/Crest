#!/usr/bin/env python3
"""Ownership contracts for manual-setup values and persistence."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserManualSetup"
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserManualSetup"
)


class ManualSetupOwnershipTests(unittest.TestCase):
    def test_mixed_domain_and_persistence_aggregate_is_removed(self) -> None:
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserManualSetupPlan.swift").exists()
        )

        required_files = (
            DOMAIN_ROOT / "BrowserManualSetupPlan.swift",
            DOMAIN_ROOT / "Models/BrowserManualSetupError.swift",
            DOMAIN_ROOT / "Models/BrowserManualSetupSpaceDraft.swift",
            INFRASTRUCTURE_ROOT / "BrowserManualSetupDraftStore.swift",
        )
        for path in required_files:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

    def test_domain_files_have_one_primary_type_and_no_user_defaults(self) -> None:
        declaration_pattern = re.compile(
            r"^(?:public |internal |private |fileprivate )?"
            r"(?:struct|enum|class|actor|protocol) ",
            re.MULTILINE,
        )
        for path in DOMAIN_ROOT.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(len(declaration_pattern.findall(source)), 1)
                self.assertNotIn("UserDefaults", source)

    def test_persistence_adapter_owns_the_stable_storage_key(self) -> None:
        source = (
            INFRASTRUCTURE_ROOT / "BrowserManualSetupDraftStore.swift"
        ).read_text()
        self.assertIn('private static let key = "BrowserManualSetupDraft"', source)
        self.assertIn("JSONDecoder().decode", source)
        self.assertIn("JSONEncoder().encode", source)

    def test_plan_scopes_private_helpers_inside_its_primary_type(self) -> None:
        source = (DOMAIN_ROOT / "BrowserManualSetupPlan.swift").read_text()

        self.assertNotRegex(source, r"(?m)^private extension ")
        self.assertIn("private static let setupPlacementOrder", source)
        self.assertIn("Self.setupPlacementOrder.flatMap", source)


if __name__ == "__main__":
    unittest.main()
