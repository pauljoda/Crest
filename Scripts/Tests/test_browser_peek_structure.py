#!/usr/bin/env python3
"""Vertical ownership and deterministic preview contracts for Peek."""

from __future__ import annotations

import pathlib
import re
import runpy
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
MAC_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Peek"
MOBILE_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/TransientBrowsing"
ACTION_BAR_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/TransientBrowsing/Components/BrowserPeekActionBar"
)
SHARED_TRANSIENT_ROOT = REPOSITORY_ROOT / "CrestShared/Features/TransientBrowsing"
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[\w.]+(?:\([^\n]*\))?\s+)*"
    r"(?:(?:public|internal|package|private|fileprivate|open|final|indirect|"
    r"nonisolated|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_]\w*)",
    re.MULTILINE,
)


class BrowserPeekStructureTests(unittest.TestCase):
    def assert_preview_fixture_is_isolated(self, source: str) -> None:
        patterns = (
            *VERTICAL_GUARD["LIVE_PREVIEW_PATTERNS"],
            *VERTICAL_GUARD["NONDETERMINISTIC_PREVIEW_PATTERNS"],
        )
        for subject, pattern in patterns:
            with self.subTest(subject=subject):
                self.assertIsNone(pattern.search(source))

    def test_mac_peek_uses_named_vertical_owners(self) -> None:
        required = (
            "BrowserPeekOverlay.swift",
            "Models/BrowserPeekModel.swift",
            "Components/BrowserPeekOverlayContent.swift",
            "Components/BrowserPeekUnlockedContent.swift",
            "Components/BrowserPeekSurface/BrowserPeekSurface.swift",
            "Components/BrowserPeekSurface/Components/BrowserPeekScrim.swift",
            "Components/BrowserPeekSurface/Components/BrowserPeekCardStack.swift",
            "Components/BrowserPeekPageCard/BrowserPeekPageCard.swift",
            "Components/BrowserPeekPageCard/Components/BrowserPeekPageContent.swift",
            "Components/BrowserPeekPageCard/Components/BrowserPeekReleasedPageView.swift",
            "Components/BrowserPeekPageCard/Components/BrowserPeekLoadingPageView.swift",
            "Components/BrowserPeekPageCard/Components/BrowserPeekInitialLoadingSurface.swift",
            "Components/BrowserPeekKeyboardMonitor/BrowserPeekKeyboardMonitor.swift",
            "Components/BrowserPeekKeyboardMonitor/Support/BrowserPeekKeyboardMonitorCoordinator.swift",
            "Components/BrowserPeekKeyboardMonitor/BrowserPeekWindowTrackingView.swift",
            "Support/BrowserKeyboardModifierFlags+NSEvent.swift",
            "Support/BrowserPeekPreviewAuthenticator.swift",
            "Support/BrowserPeekPreviewFixture.swift",
        )
        for relative_path in required:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((MAC_ROOT / relative_path).is_file())

        self.assertFalse((MAC_ROOT / "Extensions").exists())

    def test_each_mac_peek_file_has_one_matching_owner(self) -> None:
        for source_file in MAC_ROOT.rglob("*.swift"):
            declarations = DECLARATION_PATTERN.findall(source_file.read_text())
            expected = [] if "+" in source_file.stem else [source_file.stem]
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected)

    def test_mac_visual_owners_have_direct_previews(self) -> None:
        visual_pattern = re.compile(
            r"\b(?:struct|class)\s+(\w+)(?:<[^\n{]+>)?\s*:\s*"
            r"(?:View|NSViewRepresentable)\b"
        )
        for source_file in MAC_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            for owner in visual_pattern.findall(source):
                with self.subTest(owner=owner):
                    self.assertIn("#Preview", source)
                    self.assertIn(owner, source[source.index("#Preview") :])

    def test_mac_preview_fixture_is_fixed_and_isolated(self) -> None:
        fixture = (MAC_ROOT / "Support/BrowserPeekPreviewFixture.swift").read_text()
        model = (MAC_ROOT / "Models/BrowserPeekModel.swift").read_text()
        unlocked_preview = (
            MAC_ROOT / "Components/BrowserPeekUnlockedContent.swift"
        ).read_text()
        self.assertRegex(fixture, r"UUID\(\s*uuid:\s*\(")
        self.assertIn("Date(timeIntervalSince1970: 0)", fixture)
        self.assertIn("InMemoryBrowserSessionPersistence", fixture)
        self.assertIn("InMemoryCredentialVault", fixture)
        self.assertNotIn("BrowserPagePool(", fixture)
        self.assertIn("pages = nil", model)
        self.assertIn("installsKeyboardMonitor: false", unlocked_preview)
        self.assert_preview_fixture_is_isolated(fixture)
        for forbidden in (
            "UserDefaults",
            "@AppStorage",
            "Keychain",
            ".standard",
            "BrowserLinkPreferenceStore.shared",
            "UUID()",
            "Date()",
            "Date.now",
            "FileManager",
            "URLSession",
            "Data(contentsOf:",
            "WKWebView",
        ):
            self.assertNotIn(forbidden, fixture)

    def test_mobile_transient_browsing_uses_named_vertical_owners(self) -> None:
        required = (
            "MobileBrowserTransientOverlay.swift",
            "Models/MobileBrowserTransientOverlayModel.swift",
            "Models/MobileBrowserTransientPresentationState.swift",
            "Models/MobileBrowserTransientRequest.swift",
            "Models/MobileBrowserTransientRenderIdentity.swift",
            "Models/MobileTransientBrowsingPresentation.swift",
            "Components/MobileBrowserTransientOverlayContent.swift",
            "Components/MobileBrowserTransientLifecycleModifier.swift",
            "Components/MobileBrowserTransientOverlaySurface.swift",
            "Components/MobileBrowserTransientUnlockedContent.swift",
            "Components/MobileBrowserTransientSurface.swift",
            "Components/MobileBrowserUnavailableTransientSpaceView.swift",
            "Components/MobileBrowserTransientScrim.swift",
            "Components/MobileTransientBrowsingOverlay/MobileTransientBrowsingOverlay.swift",
            "Components/MobileTransientBrowsingOverlay/Components/MobileTransientBrowsingRequestOverlay.swift",
            "Components/MobileTransientBrowsingOverlay/Components/MobileTransientBrowsingPreviewSurface.swift",
            "Components/MobileBrowserTransientCard/MobileBrowserTransientCard.swift",
            "Components/MobileBrowserTransientCard/Components/MobileBrowserTransientPhoneCard.swift",
            "Components/MobileBrowserTransientCard/Components/MobileBrowserTransientTabletCard.swift",
            "Components/MobileBrowserTransientCard/Components/MobileBrowserTransientPageCard.swift",
            "Components/MobileBrowserTransientCard/Components/MobileBrowserTransientActionControls.swift",
            "Support/MobileBrowserTransientChromePolicy.swift",
            "Support/MobileBrowserTransientLayout.swift",
            "Support/MobileBrowserPeekSourceTransform.swift",
            "Support/MobileBrowserTransientPreviewFixture.swift",
            "Support/MobileBrowserTransientPreviewAuthenticator.swift",
        )
        for relative_path in required:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((MOBILE_ROOT / relative_path).is_file())

        self.assertFalse((REPOSITORY_ROOT / "CrestMobile/Features/Peek").exists())

    def test_each_mobile_transient_file_has_one_matching_owner(self) -> None:
        for source_file in MOBILE_ROOT.rglob("*.swift"):
            declarations = DECLARATION_PATTERN.findall(source_file.read_text())
            expected = [] if "+" in source_file.stem else [source_file.stem]
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected)

    def test_mobile_visual_owners_have_direct_previews(self) -> None:
        visual_pattern = re.compile(
            r"\b(?:struct|class)\s+(\w+)(?:<[^\n{]+>)?\s*:\s*View\b"
        )
        for source_file in MOBILE_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            for owner in visual_pattern.findall(source):
                with self.subTest(owner=owner):
                    self.assertIn("#Preview", source)
                    self.assertIn(owner, source[source.index("#Preview") :])

    def test_mobile_preview_fixture_is_fixed_and_isolated(self) -> None:
        fixture = (
            MOBILE_ROOT / "Support/MobileBrowserTransientPreviewFixture.swift"
        ).read_text()
        model = (
            MOBILE_ROOT / "Models/MobileBrowserTransientOverlayModel.swift"
        ).read_text()
        self.assertRegex(fixture, r"UUID\(\s*uuid:\s*\(")
        self.assertIn("Date(timeIntervalSince1970: 0)", fixture)
        self.assertIn("InMemoryBrowserSessionPersistence", fixture)
        self.assertIn("InMemoryCredentialVault", fixture)
        self.assertIn("browsingMode: .privateBrowsing", fixture)
        self.assertIn("MobileBrowserTransientPreviewAuthenticator", fixture)
        self.assertIn("pages = nil", model)
        self.assertIn("preferences = .isolated", model)
        self.assertIn("now: Date(timeIntervalSince1970: 0)", model)
        self.assert_preview_fixture_is_isolated(fixture)
        for forbidden in (
            "UserDefaults",
            "@AppStorage",
            "Keychain",
            ".standard",
            "BrowserLinkPreferenceStore.shared",
            "MobileBrowserPageStore(",
            "UUID()",
            "Date()",
            "Date.now",
            "FileManager",
            "URLSession",
            "Data(contentsOf:",
            "WKWebView",
        ):
            self.assertNotIn(forbidden, fixture)

    def test_shared_action_bar_uses_named_vertical_owners_and_direct_previews(self) -> None:
        required = (
            "Components/BrowserPeekActionBar/BrowserPeekActionBar.swift",
            "Components/BrowserPeekActionBar/Components/BrowserPeekCloseButton.swift",
            "Components/BrowserPeekActionBar/Components/BrowserPeekDestinationControl.swift",
            "Components/BrowserPeekActionBar/Components/BrowserPeekDestinationMenu.swift",
            "Components/BrowserPeekActionBar/Components/BrowserPeekDestinationPrimaryButton.swift",
            "Models/BrowserPeekKeyboardAction.swift",
            "Support/BrowserPeekChromePolicy.swift",
            "Support/BrowserPeekKeyboardPolicy.swift",
            "Support/BrowserPeekPresentationPolicy.swift",
            "Support/BrowserPeekActionBarPreviewFixture.swift",
        )
        for relative_path in required:
            source_file = SHARED_TRANSIENT_ROOT / relative_path
            with self.subTest(relative_path=relative_path):
                self.assertTrue(source_file.is_file())

        for source_file in ACTION_BAR_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            declarations = DECLARATION_PATTERN.findall(source)
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, [source_file.stem])
                self.assertIn("#Preview", source)
                self.assertIn(source_file.stem, source[source.index("#Preview") :])

        fixture = (
            SHARED_TRANSIENT_ROOT / "Support/BrowserPeekActionBarPreviewFixture.swift"
        ).read_text()
        self.assertRegex(fixture, r"UUID\(\s*uuid:\s*\(")
        self.assert_preview_fixture_is_isolated(fixture)
        for forbidden in (
            "UUID()",
            "Date()",
            "Date.now",
            "FileManager",
            "URLSession",
            "Data(contentsOf:",
            "WKWebView",
            "UserDefaults",
            "Keychain",
        ):
            self.assertNotIn(forbidden, fixture)

    def test_delayed_destination_actions_retain_exact_runtime_assignments(self) -> None:
        action_bar = (ACTION_BAR_ROOT / "BrowserPeekActionBar.swift").read_text()
        destination_menu = (
            ACTION_BAR_ROOT
            / "Components/BrowserPeekDestinationMenu.swift"
        ).read_text()
        mac_model = (MAC_ROOT / "Models/BrowserPeekModel.swift").read_text()
        mobile_model = (
            MOBILE_ROOT / "Models/MobileBrowserTransientOverlayModel.swift"
        ).read_text()
        mobile_root = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/TransientBrowsing/Components/MobileTransientBrowsingOverlay/Components/MobileTransientBrowsingRequestOverlay.swift"
        ).read_text()
        access_view = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Settings/BrowserSpaceAccessView.swift"
        ).read_text()

        self.assertIn(
            "openInSpace: (BrowserSpaceRuntimeAssignment) -> Void",
            action_bar,
        )
        self.assertIn("BrowserSpaceRuntimeAssignment(space: candidate)", destination_menu)
        self.assertIn(
            "promote(to destinationAssignment: BrowserSpaceRuntimeAssignment)",
            mac_model,
        )
        self.assertIn(
            "promote(to destinationAssignment: BrowserSpaceRuntimeAssignment)",
            mobile_model,
        )
        self.assertIn("setSourceLocked(_ isLocked: Bool)", mac_model)
        self.assertIn("setSourceLocked(_ isLocked: Bool)", mobile_model)
        self.assertIn(
            "selectSpace: (BrowserSpaceRuntimeAssignment) -> Void",
            access_view,
        )
        self.assertIn(
            "selectLockedSpace(_ assignment: BrowserSpaceRuntimeAssignment)",
            mac_model,
        )
        self.assertIn(
            "selectLockedSpace(_ assignment: BrowserSpaceRuntimeAssignment)",
            mobile_model,
        )
        unlocked_content = (
            MOBILE_ROOT / "Components/MobileBrowserTransientUnlockedContent.swift"
        ).read_text()
        mac_unlocked_content = (
            MAC_ROOT / "Components/BrowserPeekUnlockedContent.swift"
        ).read_text()
        self.assertIn(
            "model.recordCompletedNavigation(",
            unlocked_content[unlocked_content.index("private func updatePresentation") :],
        )
        self.assertIn(
            "recordCompletedNavigation: model.recordCompletedNavigation",
            mac_unlocked_content,
        )
        self.assertIn(".renderIdentity)", mobile_root)


if __name__ == "__main__":
    unittest.main()
