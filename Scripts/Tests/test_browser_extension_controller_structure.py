#!/usr/bin/env python3
"""Ownership contracts for Crest's WebExtension controller facade."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
INFRASTRUCTURE_ROOT = REPOSITORY_ROOT / "CrestShared/Infrastructure"
FACADE = INFRASTRUCTURE_ROOT / "BrowserExtensionControllerPool.swift"
CONTROLLER_ROOT = INFRASTRUCTURE_ROOT / "BrowserExtensions/Controller"
MAC_CONTROLLER_ROOT = (
    REPOSITORY_ROOT / "CrestMac/Infrastructure/WebKit/Extensions/Controller"
)
MOBILE_CONTROLLER_ROOT = (
    REPOSITORY_ROOT / "CrestMobile/Infrastructure/WebKit/Extensions/Controller"
)

PRIMARY_DECLARATION = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserExtensionControllerStructureTests(unittest.TestCase):
    def test_controller_responsibilities_have_explicit_owners(self) -> None:
        required_owners = (
            "BrowserExtensionCommandController.swift",
            "BrowserExtensionContextObserver.swift",
            "BrowserExtensionControllerPoolError.swift",
            "BrowserExtensionInstallationController.swift",
            "BrowserExtensionPermissionController.swift",
            "BrowserExtensionPersistenceController.swift",
            "BrowserExtensionRestorationController.swift",
            "BrowserExtensionRuntimeContextController.swift",
            "BrowserSafariWebExtensionRuntimeResource.swift",
            "BrowserExtensionToolbarController.swift",
        )
        for filename in required_owners:
            with self.subTest(filename=filename):
                self.assertTrue((CONTROLLER_ROOT / filename).is_file())

        application_models = ("BrowserExtensionSummary.swift",)
        application_model_root = (
            REPOSITORY_ROOT
            / "CrestShared/Application/BrowserExtensions/Models"
        )
        for filename in application_models:
            with self.subTest(application_model=filename):
                self.assertTrue((application_model_root / filename).is_file())
                self.assertFalse((CONTROLLER_ROOT / filename).exists())

        domain_models = (
            "BrowserExtensionAccessDecision.swift",
            "BrowserExtensionPermissionSnapshot.swift",
        )
        domain_model_root = (
            REPOSITORY_ROOT
            / "CrestShared/Domain/BrowserExtensions/Models"
        )
        for filename in domain_models:
            with self.subTest(domain_model=filename):
                self.assertTrue((domain_model_root / filename).is_file())
                self.assertFalse((CONTROLLER_ROOT / filename).exists())

        required_facades = (
            CONTROLLER_ROOT / "BrowserExtensionControllerPool+Installation.swift",
            CONTROLLER_ROOT / "BrowserExtensionControllerPool+Permissions.swift",
            CONTROLLER_ROOT / "BrowserExtensionControllerPool+Restoration.swift",
            CONTROLLER_ROOT / "BrowserExtensionControllerPool+RuntimeContext.swift",
            CONTROLLER_ROOT / "BrowserExtensionControllerPool+Toolbar.swift",
            MAC_CONTROLLER_ROOT / "BrowserExtensionControllerPool+Commands.swift",
            MAC_CONTROLLER_ROOT / "BrowserExtensionControllerPool+MacInstallation.swift",
            MAC_CONTROLLER_ROOT / "BrowserExtensionControllerPool+MacToolbar.swift",
            MAC_CONTROLLER_ROOT / "BrowserExtensionCommandController+Mac.swift",
            MAC_CONTROLLER_ROOT / "BrowserExtensionInstallationController+Mac.swift",
            MAC_CONTROLLER_ROOT / "BrowserExtensionToolbarController+Mac.swift",
            MAC_CONTROLLER_ROOT / "BrowserPlatformSafariWebExtensionLoader.swift",
            MOBILE_CONTROLLER_ROOT / "BrowserExtensionCommandController+Mobile.swift",
            MOBILE_CONTROLLER_ROOT / "BrowserPlatformSafariWebExtensionLoader.swift",
        )
        for source_path in required_facades:
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_path.is_file())

    def test_every_controller_source_has_one_matching_primary_owner(self) -> None:
        sources = [
            FACADE,
            *CONTROLLER_ROOT.rglob("*.swift"),
            *MAC_CONTROLLER_ROOT.rglob("*.swift"),
            *MOBILE_CONTROLLER_ROOT.rglob("*.swift"),
        ]
        for source_path in sources:
            declarations = PRIMARY_DECLARATION.findall(source_path.read_text())
            expected = [] if "+" in source_path.stem else [source_path.stem]
            with self.subTest(source_path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected)

    def test_mobile_controller_twins_are_documented_inert_stubs(self) -> None:
        for filename in (
            "BrowserExtensionCommandController+Mobile.swift",
            "BrowserPlatformSafariWebExtensionLoader.swift",
        ):
            source = (MOBILE_CONTROLLER_ROOT / filename).read_text()
            prose = " ".join(source.replace("///", " ").split())
            with self.subTest(filename=filename):
                self.assertIn("macos-only feature", prose.lower())
                self.assertIn("never instantiates the extension", prose.lower())
                self.assertIn("product decision first", prose)
                self.assertNotIn("import Security", source)

        commands = (
            MOBILE_CONTROLLER_ROOT / "BrowserExtensionCommandController+Mobile.swift"
        ).read_text()
        self.assertEqual(commands.count("{}"), 3)
        loader = (
            MOBILE_CONTROLLER_ROOT / "BrowserPlatformSafariWebExtensionLoader.swift"
        ).read_text()
        self.assertIn("throw BrowserExtensionControllerPoolError", loader)
        self.assertNotIn("BrowserSafariWebExtensionResource(", loader)

    def test_pool_is_a_bounded_facade_without_aggregate_state(self) -> None:
        source = FACADE.read_text()
        self.assertLess(len(source.splitlines()), 220)
        self.assertNotIn("NotificationCenter", source)
        self.assertNotIn("[SpaceID: [String: WKWebExtensionContext]]", source)
        self.assertNotIn("BrowserSecurityScopedResourceAccess", source)
        self.assertNotIn("WKWebExtension.MatchPattern", source)
        self.assertNotIn("CommandDefault", source)

    def test_runtime_and_observation_owners_keep_release_cleanup_together(self) -> None:
        runtime = (
            CONTROLLER_ROOT / "BrowserExtensionRuntimeContextController.swift"
        ).read_text()
        observer = (
            CONTROLLER_ROOT / "BrowserExtensionContextObserver.swift"
        ).read_text()

        self.assertIn("private var contextsBySpace", runtime)
        self.assertIn("func releaseContext", runtime)
        self.assertIn("contextObserver.stopObserving", runtime)
        self.assertIn("unregisterNativeMessagingIdentity", runtime)
        self.assertIn("func stopObserving", observer)
        self.assertIn("func stopObservingAll", observer)
        self.assertIn("isolated deinit", observer)
        self.assertIn("removeObserver", observer)

    def test_installation_owner_keeps_replacement_rollback_explicit(self) -> None:
        source = (
            MAC_CONTROLLER_ROOT / "BrowserExtensionInstallationController+Mac.swift"
        ).read_text()
        self.assertIn("func restorePreviousInstallation", source)
        self.assertIn("persistence.discard", source)
        self.assertIn("runtime.releaseContext", source)


if __name__ == "__main__":
    unittest.main()
