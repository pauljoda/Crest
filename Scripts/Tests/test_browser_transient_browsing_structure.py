#!/usr/bin/env python3
"""Structural contract for transient-browsing ownership."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserTransientBrowsing"
APPLICATION_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Application/BrowserTransientBrowsing"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserTransientBrowsingStructureTests(unittest.TestCase):
    def test_flat_source_is_replaced_by_responsibility_tree(self) -> None:
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserTransientBrowsing.swift").exists()
        )

        required_files = (
            "ExternalLinks/BrowserExternalLinkScenePolicy.swift",
            "ExternalLinks/BrowserExternalLinkDestination.swift",
            "ExternalLinks/BrowserLinkRouteMatch.swift",
            "ExternalLinks/BrowserLinkRoute.swift",
            "ExternalLinks/BrowserLinkRoutingDecision.swift",
            "ExternalLinks/BrowserLinkRoutingPolicy.swift",
            "ExternalLinks/BrowserLinkPreferences.swift",
            "ExternalLinks/BrowserLinkClickModifier.swift",
            "ExternalLinks/BrowserLinkClickIntent.swift",
            "ExternalLinks/BrowserLinkClickModifierPolicy.swift",
            "QuickWindow/BrowserQuickWindowArchivePolicy.swift",
            "QuickWindow/BrowserQuickWindowRequest.swift",
            "Peek/BrowserPeekTrigger.swift",
            "Peek/BrowserPeekSourcePresentation.swift",
            "Peek/BrowserPeekRequest.swift",
            "Peek/BrowserPeekPresentationPhase.swift",
            "Peek/BrowserPeekPolicy.swift",
            "Navigation/BrowserPageNavigationContext.swift",
            "SavedSites/BrowserSavedSitePolicy.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((DOMAIN_ROOT / relative_path).is_file())

        for relative_path in (
            "Peek/BrowserTransientBrowsingCoordinator.swift",
            "QuickWindow/BrowserTransientActivityClock.swift",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertTrue((APPLICATION_ROOT / relative_path).is_file())

    def test_each_source_has_one_matching_primary_declaration(self) -> None:
        for root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for source_path in root.rglob("*.swift"):
                with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                    declarations = DECLARATION_PATTERN.findall(source_path.read_text())
                    expected = [] if "+" in source_path.stem else [source_path.stem]
                    self.assertEqual(declarations, expected)

    def test_observable_main_actor_owners_are_isolated(self) -> None:
        coordinator_source = (
            APPLICATION_ROOT / "Peek/BrowserTransientBrowsingCoordinator.swift"
        ).read_text()
        store_source = (
            REPOSITORY_ROOT
            / "CrestShared/Application/BrowserLinkPreferences/BrowserLinkPreferenceStore.swift"
        ).read_text()
        clock_source = (
            APPLICATION_ROOT / "QuickWindow/BrowserTransientActivityClock.swift"
        ).read_text()

        for source in (coordinator_source, store_source, clock_source):
            self.assertIn("@Observable", source)
            self.assertIn("@MainActor", source)

        self.assertIn("final class BrowserTransientBrowsingCoordinator", coordinator_source)
        self.assertNotIn("final class BrowserLinkPreferenceStore", coordinator_source)
        self.assertIn("final class BrowserLinkPreferenceStore", store_source)
        self.assertNotIn("final class BrowserTransientBrowsingCoordinator", store_source)
        self.assertIn("final class BrowserTransientActivityClock", clock_source)

        for source_path in DOMAIN_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import Observation", source)
                self.assertNotIn("@Observable", source)
                self.assertNotIn("@MainActor", source)

    def test_all_sources_are_bounded(self) -> None:
        for root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for source_path in root.rglob("*.swift"):
                with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                    self.assertLess(len(source_path.read_text().splitlines()), 260)


if __name__ == "__main__":
    unittest.main()
