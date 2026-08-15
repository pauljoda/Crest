#!/usr/bin/env python3
"""Structural contracts for Reader Mode ownership."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserReaderMode"
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserReaderMode"
)
PRESENTATION_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Features/ReaderMode/Support"
)
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserReaderMode.swift"
)
LOCALIZATION_CATALOG = (
    REPOSITORY_ROOT / "CrestShared/Resources/Localizable.xcstrings"
)
PROJECT_FILE = REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj"

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserReaderModeOwnershipTests(unittest.TestCase):
    def test_reader_mode_uses_explicit_layer_owners(self) -> None:
        required_files = (
            DOMAIN_ROOT / "Models/BrowserReaderModeAction.swift",
            DOMAIN_ROOT / "Models/BrowserReaderModeError.swift",
            DOMAIN_ROOT / "Models/BrowserReaderModeSnapshot.swift",
            DOMAIN_ROOT / "Models/BrowserReaderModeState.swift",
            INFRASTRUCTURE_ROOT / "BrowserReaderModeController.swift",
            INFRASTRUCTURE_ROOT / "BrowserReaderModeJavaScriptBridge.swift",
            INFRASTRUCTURE_ROOT / "BrowserReaderModeSnapshotDecoder.swift",
            PRESENTATION_ROOT / "BrowserReaderModeError+LocalizedError.swift",
            PRESENTATION_ROOT / "BrowserReaderModePresentation.swift",
        )

        for path in required_files:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        self.assertFalse(LEGACY_AGGREGATE.exists())

    def test_each_reader_mode_owner_has_one_matching_primary_declaration(self) -> None:
        for root in (DOMAIN_ROOT, INFRASTRUCTURE_ROOT, PRESENTATION_ROOT):
            for path in root.rglob("*.swift"):
                declarations = DECLARATION_PATTERN.findall(path.read_text())
                expected = [] if "+" in path.stem else [path.stem]
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(declarations, expected)

    def test_domain_is_pure_and_webkit_execution_is_infrastructure_owned(self) -> None:
        domain_source = "\n".join(
            path.read_text() for path in DOMAIN_ROOT.rglob("*.swift")
        )
        for forbidden in (
            "import WebKit",
            "WKContentWorld",
            "WKWebView",
            "callAsyncJavaScript",
            "LocalizedError",
            "LocalizedStringResource",
            "Reader Mode is not available for this page.",
            "This page could not be presented in Reader Mode.",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, domain_source)

        controller = (
            INFRASTRUCTURE_ROOT / "BrowserReaderModeController.swift"
        ).read_text()
        bridge = (
            INFRASTRUCTURE_ROOT / "BrowserReaderModeJavaScriptBridge.swift"
        ).read_text()
        self.assertIn("WKContentWorld", controller)
        self.assertIn("callAsyncJavaScript", controller)
        self.assertIn("BrowserReaderModeAction", controller)
        self.assertIn("action.rawValue", controller)
        self.assertNotRegex(controller, r'perform\("(?:availability|activate|deactivate|snapshot)"')
        self.assertIn("const makeBridge", bridge)
        self.assertIn('main.setAttribute("aria-label", readerModeLabel)', bridge)
        self.assertNotIn('main.setAttribute("aria-label", "Reader Mode")', bridge)

    def test_runtime_presentation_is_catalog_owned(self) -> None:
        error_presentation = (
            PRESENTATION_ROOT / "BrowserReaderModeError+LocalizedError.swift"
        ).read_text()
        presentation = (
            PRESENTATION_ROOT / "BrowserReaderModePresentation.swift"
        ).read_text()
        self.assertIn("LocalizedError", error_presentation)
        self.assertIn("String(localized:", error_presentation)
        self.assertIn("LocalizedStringResource", presentation)

        catalog = json.loads(LOCALIZATION_CATALOG.read_text())["strings"]
        for key in (
            "Reader Mode",
            "Reader Mode is not available for this page.",
            "This page could not be presented in Reader Mode.",
        ):
            with self.subTest(key=key):
                self.assertIn(key, catalog)

    def test_generated_project_includes_reader_mode_owners(self) -> None:
        project = PROJECT_FILE.read_text()
        shared_owners = (
            "BrowserReaderModeAction.swift",
            "BrowserReaderModeController.swift",
            "BrowserReaderModeError+LocalizedError.swift",
            "BrowserReaderModeError.swift",
            "BrowserReaderModeJavaScriptBridge.swift",
            "BrowserReaderModePresentation.swift",
            "BrowserReaderModeSnapshot.swift",
            "BrowserReaderModeSnapshotDecoder.swift",
            "BrowserReaderModeState.swift",
        )

        for filename in shared_owners:
            with self.subTest(filename=filename):
                self.assertGreaterEqual(
                    project.count(f"{filename} in Sources"),
                    4,
                    "Each shared owner must remain in both app targets.",
                )

        self.assertGreaterEqual(
            project.count("BrowserReaderModeTests.swift in Sources"),
            2,
        )
        self.assertNotIn("BrowserReaderMode.swift in Sources", project)


if __name__ == "__main__":
    unittest.main()
