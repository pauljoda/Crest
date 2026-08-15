#!/usr/bin/env python3
"""Structural contracts for browser window-state persistence ownership."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
APPLICATION_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Application/BrowserWindowState/Ports"
)
PERSISTENCE_PORT = APPLICATION_ROOT / "BrowserWindowStatePersisting.swift"
PERSISTENCE_DEFAULTS = (
    APPLICATION_ROOT / "BrowserWindowStatePersisting+Defaults.swift"
)
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserWindowStatePersistence"
)
USER_DEFAULTS_ADAPTER = (
    INFRASTRUCTURE_ROOT / "UserDefaultsBrowserWindowStatePersistence.swift"
)
IN_MEMORY_ADAPTER = (
    INFRASTRUCTURE_ROOT / "InMemoryBrowserWindowStatePersistence.swift"
)
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserWindowStatePersistence.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
EXTENSION_PATTERN = re.compile(
    r"^extension\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\{",
    re.MULTILINE,
)


class BrowserWindowStatePersistenceStructureTests(unittest.TestCase):
    def test_window_state_persistence_has_explicit_layer_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        for path in (
            PERSISTENCE_PORT,
            PERSISTENCE_DEFAULTS,
            USER_DEFAULTS_ADAPTER,
            IN_MEMORY_ADAPTER,
        ):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

    def test_each_file_scope_owner_has_one_matching_file(self) -> None:
        for path in (PERSISTENCE_PORT, USER_DEFAULTS_ADAPTER, IN_MEMORY_ADAPTER):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(
                    DECLARATION_PATTERN.findall(path.read_text()),
                    [path.stem],
                )

        defaults_source = PERSISTENCE_DEFAULTS.read_text()
        self.assertEqual(DECLARATION_PATTERN.findall(defaults_source), [])
        self.assertEqual(
            EXTENSION_PATTERN.findall(defaults_source),
            ["BrowserWindowStatePersisting"],
        )

    def test_framework_storage_and_queueing_stay_in_infrastructure(self) -> None:
        application_source = "\n".join(
            path.read_text() for path in APPLICATION_ROOT.rglob("*.swift")
        )
        self.assertNotIn("UserDefaults", application_source)
        self.assertNotIn("DispatchQueue", application_source)
        self.assertNotIn("JSONEncoder", application_source)
        self.assertNotIn("UserDefaultsBrowserWindowStatePersistence", application_source)
        self.assertNotIn("InMemoryBrowserWindowStatePersistence", application_source)

        user_defaults_source = USER_DEFAULTS_ADAPTER.read_text()
        self.assertIn('"crest.windows.v1"', user_defaults_source)
        self.assertIn(
            '"com.pauldavis.crest.window-state-persistence"',
            user_defaults_source,
        )
        self.assertIn("JSONEncoder", user_defaults_source)
        self.assertIn("JSONDecoder", user_defaults_source)
        self.assertIn("DispatchQueue.main.async", user_defaults_source)
        self.assertIn("withCheckedContinuation", user_defaults_source)
        self.assertNotIn("typealias", user_defaults_source)

        in_memory_source = IN_MEMORY_ADAPTER.read_text()
        self.assertNotIn("UserDefaults", in_memory_source)
        self.assertNotIn("DispatchQueue", in_memory_source)


if __name__ == "__main__":
    unittest.main()
