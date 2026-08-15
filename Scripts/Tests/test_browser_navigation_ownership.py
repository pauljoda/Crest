#!/usr/bin/env python3
"""Structural contracts for browser navigation ownership."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserNavigation"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserNavigation"
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/WebKit/Navigation"
)
FAILURE_PRESENTATION = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Navigation/BrowserNavigationFailureView/Support/BrowserNavigationFailure+Presentation.swift"
)
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserNavigationDecider.swift"
)
LEGACY_FAILURE_AGGREGATE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserNavigationFailure.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserNavigationOwnershipTests(unittest.TestCase):
    def test_aggregate_is_replaced_by_explicit_layer_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        for root in (DOMAIN_ROOT, APPLICATION_ROOT, INFRASTRUCTURE_ROOT):
            with self.subTest(root=root.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(root.is_dir())
                self.assertTrue(any(root.rglob("*.swift")))

    def test_each_owner_has_one_matching_primary_declaration(self) -> None:
        for root in (DOMAIN_ROOT, APPLICATION_ROOT, INFRASTRUCTURE_ROOT):
            for path in root.rglob("*.swift"):
                declarations = DECLARATION_PATTERN.findall(path.read_text())
                expected = [] if "+" in path.stem else [path.stem]
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(declarations, expected)

    def test_domain_and_application_are_webkit_neutral(self) -> None:
        for root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for path in root.rglob("*.swift"):
                source = path.read_text()
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertNotIn("import WebKit", source)
                    self.assertNotIn("WKNavigation", source)

        infrastructure_source = "\n".join(
            path.read_text() for path in INFRASTRUCTURE_ROOT.rglob("*.swift")
        )
        self.assertIn("import WebKit", infrastructure_source)
        self.assertIn("WKNavigationActionPolicy", infrastructure_source)

        popup_trigger = (
            DOMAIN_ROOT / "Models/BrowserPopupTrigger.swift"
        ).read_text()
        self.assertIn("case explicitUserNavigation", popup_trigger)
        self.assertIn("case scripted", popup_trigger)
        self.assertNotIn("WKNavigationType", popup_trigger)

        popup_adapter = (
            INFRASTRUCTURE_ROOT / "BrowserPopupTrigger+WebKit.swift"
        ).read_text()
        self.assertIn("WKNavigationType", popup_adapter)
        self.assertIn("extension BrowserPopupTrigger", popup_adapter)

    def test_consent_workflow_stays_application_owned(self) -> None:
        coordinator = (
            APPLICATION_ROOT / "BrowserExternalSchemeCoordinator.swift"
        ).read_text()
        self.assertIn("BrowserSitePermissionCenter", coordinator)
        self.assertIn("BrowserExternalSchemeConsent.resolve", coordinator)
        self.assertNotIn("UserDefaults", coordinator)
        self.assertNotIn("WKNavigationAction", coordinator)

    def test_response_intent_scopes_its_http_classification_helper(self) -> None:
        source = (
            DOMAIN_ROOT / "Models/BrowserNavigationResponseIntent.swift"
        ).read_text()

        self.assertNotIn("extension URLResponse", source)
        self.assertIn("private static func requestsDownload", source)

    def test_navigation_failure_separates_values_mapping_and_presentation(self) -> None:
        model_paths = (
            DOMAIN_ROOT / "Models/BrowserNavigationFailure.swift",
            DOMAIN_ROOT / "Models/BrowserNavigationFailureKind.swift",
            DOMAIN_ROOT / "Models/BrowserNavigationFailurePhase.swift",
        )
        for path in model_paths:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                source = path.read_text()
                self.assertEqual(DECLARATION_PATTERN.findall(source), [path.stem])
                self.assertNotIn("WebKit", source)
                self.assertNotIn("NSError", source)
                self.assertNotIn("CREST_", source)

        adapter = (
            INFRASTRUCTURE_ROOT / "BrowserNavigationFailure+WebKit.swift"
        ).read_text()
        self.assertIn("extension BrowserNavigationFailure", adapter)
        self.assertIn("NSError", adapter)
        self.assertIn("WKError", adapter)
        self.assertIn("NSURLErrorDomain", adapter)

        presentation = FAILURE_PRESENTATION.read_text()
        self.assertIn("extension BrowserNavigationFailure", presentation)
        self.assertIn("var displayHost", presentation)
        self.assertIn("var browserCode", presentation)
        self.assertIn("CREST_NAVIGATION_FAILED", presentation)

        self.assertFalse(LEGACY_FAILURE_AGGREGATE.exists())


if __name__ == "__main__":
    unittest.main()
