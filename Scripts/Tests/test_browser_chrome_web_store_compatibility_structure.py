#!/usr/bin/env python3
"""Ownership and restoration contract for store WebExtension compatibility."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-vertical-structure.py"
PROJECT = REPOSITORY_ROOT / "Crest.xcodeproj" / "project.pbxproj"
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Extensions/BrowserChromeWebStoreCompatibilityPackage.swift"
)
OWNERS = {
    "CrestMac/Features/Extensions/Models/BrowserChromeWebStoreCompatibilityPackageError.swift": (
        "BrowserWebExtensionCompatibilityPackageError",
        "BrowserChromeWebStoreCompatibilityPackageError",
    ),
    "CrestMac/Features/Extensions/Models/BrowserChromeWebStorePreparedPackage.swift": (
        "BrowserWebExtensionPreparedPackage",
        "BrowserChromeWebStorePreparedPackage",
    ),
    "CrestMac/Features/Extensions/Services/BrowserChromeWebStoreCompatibilityPackagePreparer.swift": (
        "BrowserWebExtensionCompatibilityPackagePreparer",
        "BrowserChromeWebStoreCompatibilityPackagePreparer",
    ),
    "CrestMac/Infrastructure/WebKit/Extensions/Compatibility/BrowserChromeWebStoreStoredResourcePreparer.swift": (
        "BrowserStoreWebExtensionStoredResourcePreparer",
        "BrowserChromeWebStoreStoredResourcePreparer",
    ),
    "CrestShared/Infrastructure/BrowserExtensions/Compatibility/BrowserExtensionStoredResource.swift": (
        "BrowserExtensionStoredResource",
    ),
    "CrestShared/Infrastructure/BrowserExtensions/Compatibility/BrowserExtensionStoredResourceIdentityPreparer.swift": (
        "BrowserExtensionStoredResourceIdentityPreparer",
    ),
    "CrestShared/Infrastructure/BrowserExtensions/Compatibility/BrowserExtensionStoredResourcePreparing.swift": (
        "BrowserExtensionStoredResourcePreparing",
    ),
}


def load_guard_module():
    spec = importlib.util.spec_from_file_location(
        "crest_vertical_structure_guard", GUARD_SCRIPT
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load the vertical structure guard")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BrowserChromeWebStoreCompatibilityStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def test_aggregate_is_replaced_by_matching_owner_files(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        for relative_path, owners in OWNERS.items():
            source_path = REPOSITORY_ROOT / relative_path
            with self.subTest(source_path=relative_path):
                self.assertTrue(source_path.is_file())
                declarations = self.guard._primary_declarations(
                    source_path.read_text()
                )
                self.assertEqual(
                    [item.name for item in declarations], list(owners)
                )
                self.assertEqual(
                    self.guard._top_level_extensions(source_path.read_text()),
                    [],
                )

    def test_dark_reader_package_is_not_rewritten(self) -> None:
        source = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Extensions/Services/BrowserChromeWebStoreCompatibilityPackagePreparer.swift"
        ).read_text()
        self.assertNotIn('"eimadpbcbfnmbkopoojfekhnkhdbieeh"', source)
        self.assertNotIn('background["scripts"] = [serviceWorker]', source)
        self.assertNotIn('background["persistent"] = false', source)
        self.assertNotIn('background.removeValue(forKey: "service_worker")', source)

    def test_restoration_prepares_stored_packages_without_changing_identity(self) -> None:
        runtime = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/BrowserExtensions/Controller/BrowserExtensionRuntimeContextController.swift"
        ).read_text()
        adapter = (
            REPOSITORY_ROOT
            / "CrestMac/Infrastructure/WebKit/Extensions/Compatibility/BrowserChromeWebStoreStoredResourcePreparer.swift"
        ).read_text()
        app = (REPOSITORY_ROOT / "CrestMac/App/CrestApp.swift").read_text()
        self.assertIn("storedResourcePreparer.prepare", runtime)
        self.assertIn("preparedResource.retainedAccess", runtime)
        self.assertIn("source.extensionID.rawValue == installation.id", adapter)
        self.assertIn("BrowserStoreWebExtensionStoredResourcePreparer()", app)

    def test_split_owners_are_in_the_expected_app_targets(self) -> None:
        project = PROJECT.read_text()
        for relative_path in OWNERS:
            filename = Path(relative_path).name
            expected_count = 2 if relative_path.startswith("CrestShared/") else 1
            with self.subTest(filename=filename):
                self.assertGreaterEqual(
                    project.count(f"/* {filename} in Sources */"),
                    expected_count,
                )


if __name__ == "__main__":
    unittest.main()
