#!/usr/bin/env python3
"""Structural contracts for session persistence ownership."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
APPLICATION_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Application/BrowserStore/Ports"
)
SAVE_SCOPE = (
    APPLICATION_ROOT / "BrowserSessionSaveScope.swift"
)
PERSISTENCE_PORT = (
    APPLICATION_ROOT / "BrowserSessionPersisting.swift"
)
PERSISTENCE_DEFAULTS = (
    APPLICATION_ROOT / "BrowserSessionPersisting+Defaults.swift"
)
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserSessionPersistence"
)
USER_DEFAULTS_ADAPTER = (
    INFRASTRUCTURE_ROOT / "UserDefaultsBrowserSessionPersistence.swift"
)
IN_MEMORY_ADAPTER = (
    INFRASTRUCTURE_ROOT / "InMemoryBrowserSessionPersistence.swift"
)
STORE_INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserStore"
)
STORE_COMPOSITION = STORE_INFRASTRUCTURE_ROOT / "BrowserStore+Composition.swift"
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserSessionPersistence.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserSessionPersistenceStructureTests(unittest.TestCase):
    def test_session_persistence_has_explicit_layer_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        for path in (
            SAVE_SCOPE,
            PERSISTENCE_PORT,
            PERSISTENCE_DEFAULTS,
            USER_DEFAULTS_ADAPTER,
            IN_MEMORY_ADAPTER,
            STORE_COMPOSITION,
        ):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

    def test_each_owner_has_one_matching_primary_declaration(self) -> None:
        paths = [
            path
            for root in (
                APPLICATION_ROOT,
                INFRASTRUCTURE_ROOT,
                STORE_INFRASTRUCTURE_ROOT,
            )
            for path in root.rglob("*.swift")
        ]
        for path in paths:
            declarations = DECLARATION_PATTERN.findall(path.read_text())
            expected_declarations = [] if "+" in path.stem else [path.stem]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected_declarations)

    def test_framework_and_storage_details_stay_in_infrastructure(self) -> None:
        for path in (SAVE_SCOPE, PERSISTENCE_PORT):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("UserDefaults", source)
                self.assertNotIn("DispatchQueue", source)
                self.assertNotIn("BrowserFaviconStoring", source)

        production_source = USER_DEFAULTS_ADAPTER.read_text()
        self.assertIn("UserDefaults", production_source)
        self.assertIn("DispatchQueue", production_source)
        self.assertIn("BrowserFaviconStoring", production_source)

        application_source = "\n".join(
            path.read_text()
            for path in (REPOSITORY_ROOT / "CrestShared/Application").rglob("*.swift")
        )
        self.assertNotIn("UserDefaultsBrowserSessionPersistence", application_source)
        self.assertNotIn("InMemoryBrowserSessionPersistence", application_source)

        composition_source = STORE_COMPOSITION.read_text()
        self.assertRegex(
            composition_source,
            r"static func production\(\s*"
            r"launchEnvironment: BrowserLaunchEnvironment = \.current\s*"
            r"\) -> BrowserStore",
        )
        self.assertIn("static func privateBrowsing()", composition_source)
        self.assertIn("UserDefaultsBrowserSessionPersistence", composition_source)
        self.assertIn("InMemoryBrowserSessionPersistence", composition_source)

    def test_persisted_keys_remain_owned_and_stable(self) -> None:
        source = USER_DEFAULTS_ADAPTER.read_text()
        for key in (
            "crest.session.v2",
            "crest.session.v1",
            "crest.history.v1.",
            "crest.history.v1.index",
            "crest.session.migratedToV2",
        ):
            with self.subTest(key=key):
                self.assertEqual(source.count(f'"{key}"'), 1)


if __name__ == "__main__":
    unittest.main()
