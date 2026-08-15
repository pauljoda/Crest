#!/usr/bin/env python3
"""Structural contracts for installed-browser import discovery on macOS."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
ONBOARDING_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Onboarding"
IMPORT_SOURCE_ROOT = ONBOARDING_ROOT
LEGACY_FAMILY = ONBOARDING_ROOT / "BrowserInstalledImportSource"
LEGACY_AGGREGATE = ONBOARDING_ROOT / "BrowserInstalledImportSource.swift"

REQUIRED_FILES = (
    "Models/BrowserInstalledImportSource/BrowserImportApplication.swift",
    "Models/BrowserInstalledImportSource/BrowserImportQueue.swift",
    "Models/BrowserInstalledImportSource/BrowserInstalledImportSource.swift",
    "Models/BrowserInstalledImportSource/BrowserDetectedImportProfile.swift",
    "Models/BrowserInstalledImportSource/BrowserDetectedImportPayload.swift",
    "Support/BrowserInstalledImportSource/BrowserImportSourceSpaceHeaderStyle.swift",
    "Services/BrowserInstalledImportSource/BrowserDetectedImportReader.swift",
    "Support/BrowserInstalledImportSource/BrowserImportDataDirectoryAccess.swift",
    "Support/BrowserInstalledImportSource/BrowserImportAccessStore.swift",
    "Support/BrowserInstalledImportSource/BrowserInstalledImportSourceDetector.swift",
    "Support/BrowserInstalledImportSource/BrowserImportDataLocator.swift",
    "Support/BrowserInstalledImportSource/BrowserImportFilePicker.swift",
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z0-9_() ,.]+\n)*"
    r"(?:(?:public|internal|private|fileprivate|final|indirect) )*"
    r"(?:struct|class|enum|actor|protocol)\s+([A-Za-z0-9_]+)",
    flags=re.MULTILINE,
)


class BrowserInstalledImportSourceStructureTests(unittest.TestCase):
    def test_import_source_has_explicit_feature_local_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        self.assertFalse(LEGACY_FAMILY.exists())
        for relative_path in REQUIRED_FILES:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((IMPORT_SOURCE_ROOT / relative_path).is_file())

    def test_each_file_has_one_matching_primary_type(self) -> None:
        for relative_path in REQUIRED_FILES:
            with self.subTest(relative_path=relative_path):
                path = IMPORT_SOURCE_ROOT / relative_path
                declarations = DECLARATION_PATTERN.findall(path.read_text())
                self.assertEqual(declarations, [path.stem])

    def test_platform_and_file_access_stay_in_mac_infrastructure(self) -> None:
        expected_owners = {
            "NSWorkspace": (
                "Support/BrowserInstalledImportSource/BrowserInstalledImportSourceDetector.swift"
            ),
            "startAccessingSecurityScopedResource": (
                "Support/BrowserInstalledImportSource/BrowserImportDataDirectoryAccess.swift"
            ),
            ".withSecurityScope": (
                "Support/BrowserInstalledImportSource/BrowserImportAccessStore.swift"
            ),
            "FileManager": (
                "Support/BrowserInstalledImportSource/BrowserImportDataLocator.swift"
            ),
            "NSOpenPanel": (
                "Support/BrowserInstalledImportSource/BrowserImportFilePicker.swift"
            ),
        }
        for symbol, relative_path in expected_owners.items():
            with self.subTest(symbol=symbol):
                owning_files = [
                    path.relative_to(IMPORT_SOURCE_ROOT).as_posix()
                    for path in (IMPORT_SOURCE_ROOT / "Support").rglob("*.swift")
                    if symbol in path.read_text()
                ]
                self.assertEqual(owning_files, [relative_path])


if __name__ == "__main__":
    unittest.main()
