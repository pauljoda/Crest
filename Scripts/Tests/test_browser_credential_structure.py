#!/usr/bin/env python3
"""Structural contracts for the credential domain family."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DECLARATION = re.compile(
    r"^(?:(?:private|fileprivate|public|internal)\s+)*"
    r"(?:final\s+)?(?:struct|class|enum|protocol|extension|actor)\s+",
    re.MULTILINE,
)


class BrowserCredentialStructureTests(unittest.TestCase):
    def test_credential_suggestion_port_and_store_gateway_are_separate(self) -> None:
        port = (
            REPOSITORY_ROOT
            / "CrestShared/Application/Credentials/BrowserCredentialSuggestionLoading.swift"
        )
        gateway = (
            REPOSITORY_ROOT
            / "CrestShared/Application/BrowserStore/Credentials/BrowserStore+BrowserCredentialSuggestionLoading.swift"
        )

        self.assertTrue(port.is_file())
        self.assertTrue(gateway.is_file())
        self.assertNotIn("extension BrowserStore", port.read_text())
        self.assertIn(
            "extension BrowserStore: BrowserCredentialSuggestionLoading",
            gateway.read_text(),
        )

    def test_credential_domain_uses_named_files(self) -> None:
        root = REPOSITORY_ROOT / "CrestShared/Domain/BrowserCredential"
        required_files = (
            "Capture/BrowserCredentialSaveCandidate.swift",
            "Capture/BrowserCredentialSaveDisposition.swift",
            "Capture/BrowserCredentialSavePlan.swift",
            "Capture/BrowserCredentialSaveResult.swift",
            "Generation/BrowserStrongPasswordGenerationError.swift",
            "Generation/BrowserStrongPasswordGenerator.swift",
            "Messages/BrowserCredentialFillRequest.swift",
            "Messages/BrowserCredentialFormEvent.swift",
            "Messages/BrowserCredentialFormMessage.swift",
            "Messages/BrowserCredentialUsernameHint.swift",
            "Models/BrowserCredential.swift",
            "Models/BrowserCredentialPasswordKind.swift",
            "Models/BrowserCredentialScope.swift",
            "Models/CredentialDescriptor.swift",
            "Models/CredentialID.swift",
            "Models/CredentialOrigin.swift",
            "Policies/BrowserCredentialCapturePolicy.swift",
            "Vaults/CredentialVault.swift",
            "Vaults/CredentialVaultError.swift",
            "Vaults/InMemoryCredentialVault.swift",
            "Vaults/PrivateBrowsingCredentialVault.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((root / relative_path).is_file())

        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserCredential.swift").exists()
        )

    def test_each_credential_file_owns_one_top_level_declaration(self) -> None:
        root = REPOSITORY_ROOT / "CrestShared/Domain/BrowserCredential"
        for path in root.rglob("*.swift"):
            declaration_count = len(DECLARATION.findall(path.read_text()))
            with self.subTest(path=path):
                self.assertEqual(declaration_count, 1)

    def test_password_bearing_values_remain_non_codable_and_redacted(self) -> None:
        models = REPOSITORY_ROOT / "CrestShared/Domain/BrowserCredential"
        credential = (models / "Models/BrowserCredential.swift").read_text()
        candidate = (
            models / "Capture/BrowserCredentialSaveCandidate.swift"
        ).read_text()
        message = (
            models / "Messages/BrowserCredentialFormMessage.swift"
        ).read_text()

        for source in (credential, candidate, message):
            declaration = next(
                line for line in source.splitlines() if line.startswith("struct ")
            )
            self.assertNotIn("Codable", declaration)
            self.assertIn("<redacted>", source)


if __name__ == "__main__":
    unittest.main()
