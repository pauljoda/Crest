#!/usr/bin/env python3
"""Structural contracts for WebExtension tab and window ownership."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserExtensions"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserExtensions"
EXTENSION_SESSION_GATEWAY = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserStore/Extensions/BrowserStore+BrowserExtensionTabWindowSessionHandling.swift"
)
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/WebKit/BrowserExtensions"
)
NATIVE_MESSAGING_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserExtensions/NativeMessaging"
)
MAC_INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestMac/Infrastructure/WebKit/BrowserExtensions"
)
MOBILE_INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestMobile/Infrastructure/WebKit/BrowserExtensions"
)
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserExtensionTabWindowAdapter.swift"
)
PROJECT_FILE = REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj"

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserExtensionTabWindowOwnershipTests(unittest.TestCase):
    def test_aggregate_is_replaced_by_explicit_layer_owners(self) -> None:
        required_files = (
            DOMAIN_ROOT / "Models/BrowserExtensionTabState.swift",
            DOMAIN_ROOT / "Models/BrowserExtensionSpaceState.swift",
            DOMAIN_ROOT / "Models/BrowserExtensionSessionState.swift",
            APPLICATION_ROOT
            / "Ports/BrowserExtensionPageSelectionProviding.swift",
            APPLICATION_ROOT
            / "Ports/BrowserExtensionTabWindowSessionHandling.swift",
            EXTENSION_SESSION_GATEWAY,
            INFRASTRUCTURE_ROOT / "BrowserExtensionPageProviding.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionTabWindowCoordinator.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+State.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+TabOperations.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+NativeMessaging.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegateMethods.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionTabAdapter.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionWindowAdapter.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserExtensionControllerPool+TabWindow.swift",
            NATIVE_MESSAGING_ROOT
            / "BrowserExtensionNativeMessagingError.swift",
            NATIVE_MESSAGING_ROOT
            / "BrowserExtensionNativeMessagingHandling.swift",
            MAC_INFRASTRUCTURE_ROOT
            / "BrowserExtensionPopupAnchorPolicy.swift",
            MAC_INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegate.swift",
            MOBILE_INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegate.swift",
        )

        for path in required_files:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        self.assertFalse(LEGACY_AGGREGATE.exists())

    def test_each_owner_has_one_matching_primary_declaration(self) -> None:
        for root in (
            DOMAIN_ROOT,
            APPLICATION_ROOT,
            INFRASTRUCTURE_ROOT,
            NATIVE_MESSAGING_ROOT,
            MAC_INFRASTRUCTURE_ROOT,
            MOBILE_INFRASTRUCTURE_ROOT,
        ):
            for path in root.rglob("*.swift"):
                declarations = DECLARATION_PATTERN.findall(path.read_text())
                expected = [] if "+" in path.stem else [path.stem]
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(declarations, expected)

    def test_domain_and_application_contracts_are_webkit_neutral(self) -> None:
        for root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for path in root.rglob("*.swift"):
                source = path.read_text()
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertNotIn("import WebKit", source)
                    self.assertNotIn("WKWebExtension", source)
                    self.assertNotIn("WKWebView", source)

        session_port = (
            APPLICATION_ROOT
            / "Ports/BrowserExtensionTabWindowSessionHandling.swift"
        ).read_text()
        self.assertIn("protocol BrowserExtensionTabWindowSessionHandling", session_port)
        self.assertNotIn("extension BrowserStore", session_port)
        browser_store_gateway = EXTENSION_SESSION_GATEWAY.read_text()
        self.assertIn(
            "extension BrowserStore: BrowserExtensionTabWindowSessionHandling",
            browser_store_gateway,
        )

    def test_shared_webkit_owners_have_no_platform_conditionals(self) -> None:
        for path in INFRASTRUCTURE_ROOT.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

        mac_delegate = (
            MAC_INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegate.swift"
        ).read_text()
        self.assertIn("import AppKit", mac_delegate)
        self.assertIn("NSAlert", mac_delegate)
        self.assertIn("presentActionPopup", mac_delegate)
        self.assertIn("WKWebExtensionControllerDelegate", mac_delegate)

        # Mobile declares the conformance and nothing else: extensions are a
        # macOS-only feature, and this twin exists only so the shared coordinator
        # can assign itself as a delegate when compiled into the mobile target.
        mobile_delegate = (
            MOBILE_INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegate.swift"
        ).read_text()
        mobile_prose = " ".join(mobile_delegate.replace("///", " ").split())
        self.assertIn("WKWebExtensionControllerDelegate", mobile_delegate)
        self.assertIn("macos-only feature", mobile_prose.lower())
        self.assertIn("never instantiates the extension", mobile_prose.lower())
        self.assertNotIn("import UIKit", mobile_delegate)
        self.assertNotIn("func ", mobile_delegate)

        shared_delegate_methods = (
            INFRASTRUCTURE_ROOT
            / "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegateMethods.swift"
        ).read_text()
        self.assertNotIn(
            "BrowserExtensionTabWindowCoordinator:\n    WKWebExtensionControllerDelegate",
            shared_delegate_methods,
        )

    def test_tab_window_sources_remain_bounded(self) -> None:
        for root in (
            INFRASTRUCTURE_ROOT,
            MAC_INFRASTRUCTURE_ROOT,
            MOBILE_INFRASTRUCTURE_ROOT,
        ):
            for path in root.rglob("*.swift"):
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertLess(len(path.read_text().splitlines()), 360)

    def test_generated_project_includes_shared_and_platform_owners(self) -> None:
        project = PROJECT_FILE.read_text()
        # The shared WebExtension runtime compiles into both app targets. Mobile
        # never instantiates it, but it is tied closely enough to WebKit to stay
        # shared rather than excluded, so every shared owner remains in both.
        shared_owners = (
            "BrowserExtensionPageProviding.swift",
            "BrowserExtensionPageSelectionProviding.swift",
            "BrowserExtensionSessionState.swift",
            "BrowserExtensionSpaceState.swift",
            "BrowserExtensionTabAdapter.swift",
            "BrowserExtensionTabState.swift",
            "BrowserExtensionControllerPool+TabWindow.swift",
            "BrowserExtensionTabWindowCoordinator.swift",
            "BrowserExtensionTabWindowCoordinator+NativeMessaging.swift",
            "BrowserExtensionTabWindowCoordinator+State.swift",
            "BrowserExtensionTabWindowCoordinator+TabOperations.swift",
            "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegateMethods.swift",
            "BrowserExtensionTabWindowSessionHandling.swift",
            "BrowserExtensionNativeMessagingError.swift",
            "BrowserExtensionNativeMessagingHandling.swift",
            "BrowserStore+BrowserExtensionTabWindowSessionHandling.swift",
            "BrowserExtensionWindowAdapter.swift",
        )
        mac_owners = (
            "BrowserExtensionPopupAnchorPolicy.swift",
            "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegate.swift",
        )
        mobile_owners = (
            "BrowserExtensionTabWindowCoordinator+WKWebExtensionControllerDelegate.swift",
        )

        for filename in shared_owners:
            with self.subTest(filename=filename):
                self.assertGreaterEqual(
                    project.count(f"{filename} in Sources"),
                    4,
                    "Each shared owner must remain in both app targets.",
                )
        for filename in mac_owners:
            with self.subTest(filename=filename):
                self.assertGreaterEqual(
                    project.count(f"{filename} in Sources"),
                    2,
                    "Each macOS owner must remain in the Mac app target.",
                )
        for filename in mobile_owners:
            with self.subTest(filename=filename):
                self.assertGreaterEqual(
                    project.count(f"{filename} in Sources"),
                    2,
                    "Each mobile owner must remain in the mobile app target.",
                )

        self.assertNotIn("BrowserExtensionTabWindowAdapter.swift in Sources", project)


if __name__ == "__main__":
    unittest.main()
