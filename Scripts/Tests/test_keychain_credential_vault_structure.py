#!/usr/bin/env python3
"""Recursive ownership contracts for Crest's Keychain credential vault."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserCredential/Keychain"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/Credentials/Keychain"
INFRASTRUCTURE_ROOT = REPOSITORY_ROOT / "CrestShared/Infrastructure/Credentials/Keychain"
LEGACY_SOURCE = REPOSITORY_ROOT / "CrestShared/Infrastructure/KeychainCredentialVault.swift"

PRIMARY_DECLARATION = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class KeychainCredentialVaultStructureTests(unittest.TestCase):
    def test_keychain_owners_are_unique_across_the_shared_source_tree(self) -> None:
        expected_owners = {
            "CredentialKeychainDescriptorItem": DOMAIN_ROOT
            / "Models/CredentialKeychainDescriptorItem.swift",
            "CredentialKeychainItem": DOMAIN_ROOT / "Models/CredentialKeychainItem.swift",
            "CredentialKeychainStoring": APPLICATION_ROOT
            / "Ports/CredentialKeychainStoring.swift",
            "CredentialKeychainNamespace": APPLICATION_ROOT
            / "Policies/CredentialKeychainNamespace.swift",
            "CredentialKeychainCodec": APPLICATION_ROOT
            / "Services/CredentialKeychainCodec.swift",
            "KeychainCredentialVault": APPLICATION_ROOT / "KeychainCredentialVault.swift",
            "SecurityCredentialKeychainClient": INFRASTRUCTURE_ROOT
            / "SecurityCredentialKeychainClient.swift",
            "SecurityCredentialKeychainError": INFRASTRUCTURE_ROOT
            / "SecurityCredentialKeychainError.swift",
            "SecurityCredentialKeychainStore": INFRASTRUCTURE_ROOT
            / "SecurityCredentialKeychainStore.swift",
            "SystemSecurityCredentialKeychainClient": INFRASTRUCTURE_ROOT
            / "SystemSecurityCredentialKeychainClient.swift",
        }
        discovered: dict[str, list[Path]] = {
            declaration: [] for declaration in expected_owners
        }
        for source_path in (REPOSITORY_ROOT / "CrestShared").rglob("*.swift"):
            for declaration in PRIMARY_DECLARATION.findall(source_path.read_text()):
                if declaration in discovered:
                    discovered[declaration].append(source_path)

        for declaration, expected_path in expected_owners.items():
            with self.subTest(declaration=declaration):
                self.assertEqual(discovered[declaration], [expected_path])

    def test_keychain_vault_has_explicit_layer_owners(self) -> None:
        self.assertFalse(LEGACY_SOURCE.exists())

        required_files = (
            DOMAIN_ROOT / "Models/CredentialKeychainDescriptorItem.swift",
            DOMAIN_ROOT / "Models/CredentialKeychainItem.swift",
            APPLICATION_ROOT / "KeychainCredentialVault.swift",
            APPLICATION_ROOT / "Policies/CredentialKeychainNamespace.swift",
            APPLICATION_ROOT / "Ports/CredentialKeychainStoring.swift",
            APPLICATION_ROOT / "Services/CredentialKeychainCodec.swift",
            INFRASTRUCTURE_ROOT / "KeychainCredentialVault+Production.swift",
            INFRASTRUCTURE_ROOT / "SecurityCredentialKeychainClient.swift",
            INFRASTRUCTURE_ROOT / "SecurityCredentialKeychainError.swift",
            INFRASTRUCTURE_ROOT / "SecurityCredentialKeychainStore.swift",
            INFRASTRUCTURE_ROOT
            / "SecurityCredentialKeychainStore+CredentialKeychainStoring.swift",
            INFRASTRUCTURE_ROOT / "SystemSecurityCredentialKeychainClient.swift",
        )
        for source_path in required_files:
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_path.is_file())

    def test_every_keychain_source_recursively_has_one_matching_primary_owner(self) -> None:
        for source_root in (DOMAIN_ROOT, APPLICATION_ROOT, INFRASTRUCTURE_ROOT):
            self.assertTrue(source_root.is_dir())
            for source_path in source_root.rglob("*.swift"):
                declarations = PRIMARY_DECLARATION.findall(source_path.read_text())
                expected = [] if "+" in source_path.stem else [source_path.stem]
                with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(declarations, expected)

    def test_domain_and_application_credential_owners_are_security_neutral(self) -> None:
        for source_root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for source_path in source_root.rglob("*.swift"):
                source = source_path.read_text()
                with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                    self.assertNotIn("import Security", source)
                    self.assertNotRegex(source, r"\b(?:SecItem|kSecAttr|kSecClass)\w*")

        actor_source = (APPLICATION_ROOT / "KeychainCredentialVault.swift").read_text()
        self.assertNotIn("SecurityCredentialKeychainStore", actor_source)
        self.assertIn("any CredentialKeychainStoring", actor_source)

        production_source = (
            INFRASTRUCTURE_ROOT / "KeychainCredentialVault+Production.swift"
        ).read_text()
        self.assertIn("SecurityCredentialKeychainStore()", production_source)

    def test_security_adapter_preserves_keychain_privacy_and_access_contracts(self) -> None:
        adapter_source = (
            INFRASTRUCTURE_ROOT
            / "SecurityCredentialKeychainStore+CredentialKeychainStoring.swift"
        ).read_text()
        all_infrastructure = "\n".join(
            path.read_text() for path in INFRASTRUCTURE_ROOT.rglob("*.swift")
        )

        self.assertIn("kSecUseDataProtectionKeychain", adapter_source)
        self.assertIn("kSecAttrAccessibleWhenUnlocked", adapter_source)
        self.assertIn("kSecAttrSynchronizableAny", adapter_source)
        self.assertNotIn("kSecAttrAccessGroup", all_infrastructure)

        descriptor_body = self._function_body(adapter_source, "descriptorItems")
        self.assertIn("kSecReturnAttributes", descriptor_body)
        self.assertNotIn("kSecReturnData", descriptor_body)

        system_client = INFRASTRUCTURE_ROOT / "SystemSecurityCredentialKeychainClient.swift"
        for source_path in INFRASTRUCTURE_ROOT.rglob("*.swift"):
            sec_item_calls = re.findall(r"\bSecItem\w+\s*\(", source_path.read_text())
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                if source_path == system_client:
                    self.assertEqual(
                        sec_item_calls,
                        [
                            "SecItemCopyMatching(",
                            "SecItemUpdate(",
                            "SecItemAdd(",
                            "SecItemDelete(",
                        ],
                    )
                else:
                    self.assertEqual(sec_item_calls, [])

    @staticmethod
    def _function_body(source: str, name: str) -> str:
        declaration = re.search(rf"\bfunc\s+{re.escape(name)}\b", source)
        if declaration is None:
            raise AssertionError(f"Missing function {name}")
        opening = source.find("{", declaration.end())
        if opening == -1:
            raise AssertionError(f"Missing body for {name}")
        depth = 0
        for offset in range(opening, len(source)):
            if source[offset] == "{":
                depth += 1
            elif source[offset] == "}":
                depth -= 1
                if depth == 0:
                    return source[opening + 1 : offset]
        raise AssertionError(f"Unbalanced body for {name}")


if __name__ == "__main__":
    unittest.main()
