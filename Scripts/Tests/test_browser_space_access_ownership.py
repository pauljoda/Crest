#!/usr/bin/env python3

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class BrowserSpaceAccessOwnershipTests(unittest.TestCase):
    def test_space_access_types_have_matching_layer_owners(self) -> None:
        owners = {
            "CrestShared/Application/BrowserSpaceAccess/BrowserSpaceAccessController.swift":
                "final class BrowserSpaceAccessController",
            "CrestShared/Application/BrowserSpaceAccess/Models/BrowserSpaceAccessFailure.swift":
                "enum BrowserSpaceAccessFailure",
            "CrestShared/Application/BrowserSpaceAccess/Services/BrowserDeviceAuthenticating.swift":
                "protocol BrowserDeviceAuthenticating",
            "CrestShared/Infrastructure/BrowserSpaceAccess/SystemBrowserDeviceAuthenticator.swift":
                "final class SystemBrowserDeviceAuthenticator",
        }
        for relative_path, declaration in owners.items():
            with self.subTest(relative_path=relative_path):
                source = (REPOSITORY_ROOT / relative_path).read_text()
                self.assertIn(declaration, source)

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserDeviceAuthentication.swift"
            ).exists()
        )

    def test_unlock_grants_are_exact_profile_assignments(self) -> None:
        source = (
            REPOSITORY_ROOT
            / "CrestShared/Application/BrowserSpaceAccess/BrowserSpaceAccessController.swift"
        ).read_text()

        self.assertIn(
            "Set<BrowserSpaceRuntimeAssignment>",
            source,
        )
        self.assertIn("BrowserSpaceRuntimeAssignment(space: space)", source)
        self.assertNotIn("unlockedSpaceIDs", source)


if __name__ == "__main__":
    unittest.main()
