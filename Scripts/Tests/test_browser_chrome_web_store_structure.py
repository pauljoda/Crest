#!/usr/bin/env python3
"""Ownership contract for shared Chrome Web Store support."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared"
    / "Infrastructure"
    / "BrowserChromeWebStore"
)
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT
    / "CrestShared"
    / "Infrastructure"
    / "BrowserChromeWebStoreSupport.swift"
)
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-vertical-structure.py"
PROJECT = REPOSITORY_ROOT / "Crest.xcodeproj" / "project.pbxproj"

PRIMARY_OWNERS = {
    "BrowserChromeExtensionID.swift": "BrowserChromeExtensionID",
    "BrowserChromeWebStoreItem.swift": "BrowserChromeWebStoreItem",
    "BrowserChromeWebStoreInstallNavigation.swift": (
        "BrowserChromeWebStoreInstallNavigation"
    ),
    "BrowserChromeWebStoreUpdateRequest.swift": (
        "BrowserChromeWebStoreUpdateRequest"
    ),
    "BrowserVerifiedCRX3Package.swift": "BrowserVerifiedCRX3Package",
    "BrowserCRX3VerifierError.swift": "BrowserCRX3VerifierError",
    "BrowserCRX3Verifier.swift": "BrowserCRX3Verifier",
    "BrowserCRX3SignatureScheme.swift": "BrowserCRX3SignatureScheme",
    "BrowserCRX3VerifiedProof.swift": "BrowserCRX3VerifiedProof",
    "BrowserExtensionRuntimeIdentifierPolicy.swift": (
        "BrowserExtensionRuntimeIdentifierPolicy"
    ),
    "BrowserCRX3ProtobufFields.swift": "BrowserCRX3ProtobufFields",
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


class BrowserChromeWebStoreStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def test_aggregate_is_replaced_by_matching_owner_files(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        for filename in PRIMARY_OWNERS:
            self.assertTrue((SOURCE_ROOT / filename).is_file(), filename)
        self.assertTrue((SOURCE_ROOT / "Data+HexString.swift").is_file())

    def test_each_source_has_exactly_one_file_scope_declaration(self) -> None:
        for source_path in SOURCE_ROOT.glob("*.swift"):
            source = source_path.read_text()
            primary = self.guard._primary_declarations(source)
            extensions = self.guard._top_level_extensions(source)
            declarations = [item.name for item in primary] + [
                f"extension {item.target}" for item in extensions
            ]
            self.assertEqual(
                len(declarations),
                1,
                f"{source_path.name}: {declarations}",
            )

    def test_primary_owner_names_match_their_filenames(self) -> None:
        for filename, owner in PRIMARY_OWNERS.items():
            source = (SOURCE_ROOT / filename).read_text()
            primary = self.guard._primary_declarations(source)
            self.assertEqual([item.name for item in primary], [owner], filename)

        data_extension = (SOURCE_ROOT / "Data+HexString.swift").read_text()
        extensions = self.guard._top_level_extensions(data_extension)
        self.assertEqual([item.target for item in extensions], ["Data"])
        self.assertEqual(self.guard._primary_declarations(data_extension), [])

    def test_verifier_support_types_have_matching_owner_files(self) -> None:
        verifier = (SOURCE_ROOT / "BrowserCRX3Verifier.swift").read_text()
        self.assertNotIn("struct BrowserCRX3VerifiedProof", verifier)
        self.assertNotIn("enum BrowserCRX3SignatureScheme", verifier)
        self.assertNotIn("struct BrowserCRX3ProtobufFields", verifier)

    def test_all_split_owners_are_in_both_shared_app_targets(self) -> None:
        project = PROJECT.read_text()
        for filename in [*PRIMARY_OWNERS, "Data+HexString.swift"]:
            self.assertGreaterEqual(
                project.count(f"/* {filename} in Sources */"),
                2,
                filename,
            )


if __name__ == "__main__":
    unittest.main()
