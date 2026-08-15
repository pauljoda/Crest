#!/usr/bin/env python3
"""Structural contract for shared site-permission ownership."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserSitePermissions"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserSitePermissions"
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserSitePermissions"
)
PRESENTATION_ROOT = REPOSITORY_ROOT / "CrestShared/Features/SitePermissions/Support"


class BrowserSitePermissionsStructureTests(unittest.TestCase):
    def test_site_permission_types_have_layered_feature_owners(self) -> None:
        required_paths = (
            DOMAIN_ROOT / "Models/BrowserMediaPermission.swift",
            DOMAIN_ROOT / "Models/BrowserSiteOrigin.swift",
            DOMAIN_ROOT / "Models/BrowserSitePermission.swift",
            DOMAIN_ROOT / "Models/BrowserSitePermissionDecision.swift",
            DOMAIN_ROOT / "Models/BrowserSitePermissionPromptResponse.swift",
            DOMAIN_ROOT / "Models/BrowserSitePermissionRecord.swift",
            DOMAIN_ROOT
            / "Policies/BrowserSitePermissionDecisionPersistencePolicy.swift",
            DOMAIN_ROOT / "Policies/BrowserSitePermissionRecordOrderingPolicy.swift",
            APPLICATION_ROOT / "BrowserSitePermissionCenter.swift",
            APPLICATION_ROOT / "BrowserSitePermissionPersisting.swift",
            INFRASTRUCTURE_ROOT
            / "Persistence/InMemoryBrowserSitePermissionPersistence.swift",
            INFRASTRUCTURE_ROOT
            / "Persistence/UserDefaultsBrowserSitePermissionPersistence.swift",
            INFRASTRUCTURE_ROOT / "BrowserSitePermissionCenter+Production.swift",
            INFRASTRUCTURE_ROOT / "WebKit/BrowserMediaPermission+WebKit.swift",
            INFRASTRUCTURE_ROOT / "WebKit/BrowserSiteOrigin+WebKit.swift",
            PRESENTATION_ROOT / "BrowserMediaPermission+Presentation.swift",
            PRESENTATION_ROOT / "BrowserSitePermission+Presentation.swift",
            PRESENTATION_ROOT / "BrowserSitePermissionDecision+Presentation.swift",
            PRESENTATION_ROOT / "BrowserSitePermissionRecord+Presentation.swift",
        )

        for path in required_paths:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserSitePermissionCenter.swift"
            ).exists()
        )

    def test_domain_remains_framework_neutral(self) -> None:
        forbidden_imports = (
            "import Observation",
            "import SwiftUI",
            "import WebKit",
        )

        for path in DOMAIN_ROOT.rglob("*.swift"):
            source = path.read_text()
            for forbidden_import in forbidden_imports:
                with self.subTest(
                    path=path.relative_to(REPOSITORY_ROOT),
                    forbidden_import=forbidden_import,
                ):
                    self.assertNotIn(forbidden_import, source)

        domain_source = "\n".join(
            path.read_text() for path in DOMAIN_ROOT.rglob("*.swift")
        )
        self.assertNotIn("settingsLabel", domain_source)
        self.assertNotIn("var symbol", domain_source)
        self.assertNotIn("displayLabel", domain_source)

    def test_framework_and_storage_adapters_stay_in_infrastructure(self) -> None:
        webkit_sources = tuple(INFRASTRUCTURE_ROOT.glob("WebKit/*.swift"))
        self.assertEqual(len(webkit_sources), 2)
        for path in webkit_sources:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("import WebKit", path.read_text())

        persistence_source = (
            INFRASTRUCTURE_ROOT
            / "Persistence/UserDefaultsBrowserSitePermissionPersistence.swift"
        ).read_text()
        self.assertIn('"crest.site-permissions.v1"', persistence_source)
        self.assertIn("UserDefaults", persistence_source)

        center_source = (APPLICATION_ROOT / "BrowserSitePermissionCenter.swift").read_text()
        self.assertIn("@Observable", center_source)
        self.assertIn("@MainActor", center_source)
        self.assertNotIn("import WebKit", center_source)
        self.assertNotIn("UserDefaults", center_source)
        self.assertNotIn("InMemoryBrowserSitePermissionPersistence", center_source)

    def test_each_source_has_at_most_one_primary_declaration(self) -> None:
        declaration_pattern = re.compile(
            r"^(?:@\w+(?:\([^\n]*\))?\s*)*"
            r"(?:(?:public|internal|private|fileprivate|open|final|indirect)\s+)*"
            r"(?:struct|enum|class|actor|protocol|typealias)\s+",
            re.MULTILINE,
        )

        for root in (
            DOMAIN_ROOT,
            APPLICATION_ROOT,
            INFRASTRUCTURE_ROOT,
            PRESENTATION_ROOT,
        ):
            for path in root.rglob("*.swift"):
                declarations = declaration_pattern.findall(path.read_text())
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertLessEqual(len(declarations), 1)


if __name__ == "__main__":
    unittest.main()
