#!/usr/bin/env python3
"""Structural contracts for the macOS browser-password import family."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
ONBOARDING_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Onboarding"
PASSWORD_IMPORT_ROOT = ONBOARDING_ROOT
LEGACY_FAMILY = ONBOARDING_ROOT / "BrowserPasswordImport"
LEGACY_AGGREGATE = ONBOARDING_ROOT / "BrowserPasswordImport.swift"

REQUIRED_FILES = (
    "Models/BrowserPasswordImport/BrowserDetectedPasswordStore.swift",
    "Models/BrowserPasswordImport/BrowserEncryptedPasswordRecord.swift",
    "Models/BrowserPasswordImport/BrowserImportedPassword.swift",
    "Models/BrowserPasswordImport/BrowserPasswordImportCandidate.swift",
    "Models/BrowserPasswordImport/BrowserPasswordImportError.swift",
    "Models/BrowserPasswordImport/BrowserPasswordImportResult.swift",
    "Services/BrowserPasswordImport/BrowserSafeStorageSecretProviding.swift",
    "Services/BrowserPasswordImport/BrowserPasswordImportCommitter.swift",
    "Services/BrowserPasswordImport/BrowserPasswordImportReader.swift",
    "Support/BrowserPasswordImport/BrowserPasswordSQLiteDatabase.swift",
    "Support/BrowserPasswordImport/ChromiumPasswordCrypto.swift",
    "Support/BrowserPasswordImport/LaunchScopedBrowserSafeStorage.swift",
    "Support/BrowserPasswordImport/SecurityBrowserSafeStorage.swift",
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z0-9_() ,.]+\n)*"
    r"(?:(?:public|internal|private|fileprivate|final|indirect) )*"
    r"(?:struct|class|enum|actor|protocol)\s+([A-Za-z0-9_]+)",
    flags=re.MULTILINE,
)


class BrowserPasswordImportStructureTests(unittest.TestCase):
    def test_password_import_has_explicit_feature_local_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        self.assertFalse(LEGACY_FAMILY.exists())
        for relative_path in REQUIRED_FILES:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((PASSWORD_IMPORT_ROOT / relative_path).is_file())

    def test_each_file_has_one_matching_primary_type(self) -> None:
        for relative_path in REQUIRED_FILES:
            with self.subTest(relative_path=relative_path):
                path = PASSWORD_IMPORT_ROOT / relative_path
                declarations = DECLARATION_PATTERN.findall(path.read_text())
                self.assertEqual(declarations, [path.stem])

    def test_framework_bridges_remain_in_infrastructure(self) -> None:
        framework_imports = ("import CommonCrypto", "import Security", "import SQLite3")
        for relative_path in REQUIRED_FILES:
            if not relative_path.startswith(("Models/", "Services/")):
                continue
            path = PASSWORD_IMPORT_ROOT / relative_path
            with self.subTest(path=path):
                source = path.read_text()
                for framework_import in framework_imports:
                    self.assertNotIn(framework_import, source)

        expected_owners = {
            "import CommonCrypto": (
                "Support/BrowserPasswordImport/ChromiumPasswordCrypto.swift"
            ),
            "import Security": (
                "Support/BrowserPasswordImport/SecurityBrowserSafeStorage.swift"
            ),
            "import SQLite3": (
                "Support/BrowserPasswordImport/BrowserPasswordSQLiteDatabase.swift"
            ),
        }
        for framework_import, relative_path in expected_owners.items():
            with self.subTest(framework_import=framework_import):
                importing_files = [
                    path.relative_to(PASSWORD_IMPORT_ROOT).as_posix()
                    for path in (PASSWORD_IMPORT_ROOT / "Support").rglob("*.swift")
                    if framework_import in path.read_text()
                ]
                self.assertEqual(importing_files, [relative_path])


if __name__ == "__main__":
    unittest.main()
