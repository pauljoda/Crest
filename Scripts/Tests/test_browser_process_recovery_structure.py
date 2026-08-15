#!/usr/bin/env python3
"""Structural contracts for browser process-recovery ownership."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserPageLifecycle"
ACTION = DOMAIN_ROOT / "Models/BrowserProcessRecoveryAction.swift"
POLICY = DOMAIN_ROOT / "Policies/BrowserProcessRecovery.swift"
MEMORY_LEVEL = DOMAIN_ROOT / "Models/BrowserMemoryPressureLevel.swift"
IDLE_UNLOAD_POLICY = DOMAIN_ROOT / "Policies/BrowserPageIdleUnloadPolicy.swift"
MEMORY_COALESCER = DOMAIN_ROOT / "Policies/BrowserMemoryPressureCoalescer.swift"
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserProcessRecovery.swift"
)
LEGACY_MEMORY_AGGREGATE = REPOSITORY_ROOT / "CrestShared/Domain/BrowserMemoryPressure.swift"

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserProcessRecoveryStructureTests(unittest.TestCase):
    def test_process_recovery_has_matching_domain_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        for path in (ACTION, POLICY):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(
                    DECLARATION_PATTERN.findall(path.read_text()),
                    [path.stem],
                )

    def test_domain_owners_stay_framework_neutral(self) -> None:
        for path in (ACTION, POLICY):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("WebKit", source)
                self.assertNotIn("Foundation", source)
                self.assertNotIn("Observation", source)

    def test_memory_pressure_has_matching_domain_owners(self) -> None:
        self.assertFalse(LEGACY_MEMORY_AGGREGATE.exists())
        for path in (MEMORY_LEVEL, IDLE_UNLOAD_POLICY, MEMORY_COALESCER):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(
                    DECLARATION_PATTERN.findall(path.read_text()),
                    [path.stem],
                )

    def test_memory_pressure_owners_stay_platform_neutral(self) -> None:
        for path in (MEMORY_LEVEL, IDLE_UNLOAD_POLICY, MEMORY_COALESCER):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import WebKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import Observation", source)

    def test_memory_pressure_preserves_coalescing_and_idle_unload_contracts(self) -> None:
        level_source = MEMORY_LEVEL.read_text()
        idle_source = IDLE_UNLOAD_POLICY.read_text()
        coalescer_source = MEMORY_COALESCER.read_text()

        self.assertIn("case warning", level_source)
        self.assertIn("case critical", level_source)
        self.assertIn("defaultLifetime: TimeInterval = 10 * 60", idle_source)
        self.assertIn("time >= deadline", idle_source)
        self.assertIn("defaultWindow: TimeInterval = 1", coalescer_source)
        self.assertIn("level <= handled.level", coalescer_source)

    def test_recovery_policy_preserves_its_bounded_reload_contract(self) -> None:
        action_source = ACTION.read_text()
        policy_source = POLICY.read_text()

        self.assertIn("case reload", action_source)
        self.assertIn("case showFailure", action_source)
        self.assertIn("maximumAutomaticReloads: Int = 2", policy_source)
        self.assertIn("consecutiveTerminations <= maximumAutomaticReloads", policy_source)
        self.assertIn("func recordSuccessfulNavigation", policy_source)
        self.assertIn("func reset", policy_source)


if __name__ == "__main__":
    unittest.main()
