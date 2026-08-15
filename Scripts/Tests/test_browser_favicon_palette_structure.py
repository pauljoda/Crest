#!/usr/bin/env python3
"""Structural contracts for favicon palette ownership."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserTab/Icons/FaviconPalette"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserFaviconPalette"
INFRASTRUCTURE_ROOT = REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserFaviconPalette"
PRESENTATION_FILE = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Tabs/Components/PinnedTabGrid/Support/BrowserFaviconColor+Presentation.swift"
)
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserFaviconPalette.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserFaviconPaletteStructureTests(unittest.TestCase):
    def test_palette_types_have_explicit_layer_owners(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())
        required_files = (
            DOMAIN_ROOT / "BrowserFaviconPalette.swift",
            DOMAIN_ROOT / "BrowserFaviconColor.swift",
            DOMAIN_ROOT / "BrowserFaviconPaletteExtractor.swift",
            APPLICATION_ROOT / "BrowserFaviconPaletteLoader.swift",
            INFRASTRUCTURE_ROOT / "BrowserFaviconPaletteExtractor+ImageIO.swift",
            INFRASTRUCTURE_ROOT / "BrowserFaviconPaletteLoader+Production.swift",
            INFRASTRUCTURE_ROOT / "BrowserFaviconPaletteLoaderProduction.swift",
            PRESENTATION_FILE,
        )
        for path in required_files:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

    def test_each_palette_owner_has_one_matching_primary_declaration(self) -> None:
        source_paths = [
            path
            for root in (
                DOMAIN_ROOT,
                APPLICATION_ROOT,
                INFRASTRUCTURE_ROOT,
            )
            for path in root.rglob("*.swift")
        ] + [PRESENTATION_FILE]
        for path in source_paths:
            declarations = DECLARATION_PATTERN.findall(path.read_text())
            expected_declarations = [] if "+" in path.stem else [path.stem]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected_declarations)

    def test_domain_and_application_are_framework_neutral(self) -> None:
        forbidden_imports = ("CoreGraphics", "ImageIO", "SwiftUI")
        for root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for path in root.rglob("*.swift"):
                source = path.read_text()
                for module in forbidden_imports:
                    with self.subTest(
                        path=path.relative_to(REPOSITORY_ROOT), module=module
                    ):
                        self.assertNotIn(f"import {module}\n", source)

        application_source = "\n".join(
            path.read_text() for path in APPLICATION_ROOT.rglob("*.swift")
        )
        self.assertNotIn("BrowserFaviconPaletteExtractor", application_source)
        self.assertIn("static let cacheLimit = 128", application_source)

    def test_framework_adapters_stay_in_their_named_layers(self) -> None:
        infrastructure_source = "\n".join(
            path.read_text() for path in INFRASTRUCTURE_ROOT.rglob("*.swift")
        )
        self.assertIn("import CoreGraphics", infrastructure_source)
        self.assertIn("import ImageIO", infrastructure_source)
        self.assertIn("Task.detached(priority: .utility)", infrastructure_source)

        presentation_source = PRESENTATION_FILE.read_text()
        self.assertIn("import SwiftUI", presentation_source)
        self.assertIn("var color: Color", presentation_source)
        self.assertNotIn("import ImageIO", presentation_source)


if __name__ == "__main__":
    unittest.main()
