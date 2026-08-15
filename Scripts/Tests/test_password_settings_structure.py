#!/usr/bin/env python3
"""Structural contracts for the shared password-settings feature."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
FEATURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Features/Settings/BrowserPasswordSettingsPane"
)


class PasswordSettingsStructureTests(unittest.TestCase):
    def test_mixed_password_settings_aggregate_is_split(self) -> None:
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Features/Settings/BrowserPasswordSettingsPane.swift"
            ).exists()
        )
        required_files = (
            "BrowserPasswordSettingsPane.swift",
            "Components/BrowserPasswordDescriptorRow.swift",
            "Models/BrowserCredentialSpaceStore.swift",
            "Models/BrowserPasswordSettingsLayout.swift",
            "Support/BrowserCredentialSettingsPolicy.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((FEATURE_ROOT / relative_path).is_file())

    def test_each_file_has_one_primary_type(self) -> None:
        declaration_pattern = re.compile(
            r"^(?:public |internal |private |fileprivate )?"
            r"(?:final )?"
            r"(?:struct|enum|class|actor|protocol) ",
            re.MULTILINE,
        )
        for path in FEATURE_ROOT.rglob("*.swift"):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(
                    len(declaration_pattern.findall(path.read_text())),
                    1,
                )

    def test_space_workflow_is_an_observable_main_actor_model(self) -> None:
        source = (
            FEATURE_ROOT / "Models/BrowserCredentialSpaceStore.swift"
        ).read_text()
        self.assertIn("@Observable", source)
        self.assertIn("@MainActor", source)
        self.assertIn("final class BrowserCredentialSpaceStore", source)


if __name__ == "__main__":
    unittest.main()
