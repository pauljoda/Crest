#!/usr/bin/env python3
"""Structural contract for the macOS browser detail presentation family."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class BrowserDetailStructureTests(unittest.TestCase):
    def source(self, relative_path: str) -> str:
        return (REPOSITORY_ROOT / relative_path).read_text()

    def test_detail_root_is_a_single_feature_entry_view(self) -> None:
        root_path = "CrestMac/Features/Browser/BrowserDetailView.swift"
        source = self.source(root_path)

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestMac/Features/Browser/Detail/BrowserDetailView.swift"
            ).exists()
        )
        self.assertEqual(
            re.findall(r"(?m)^struct\s+([A-Za-z0-9_]+)\s*:\s*View\b", source),
            ["BrowserDetailView"],
        )
        self.assertIn("BrowserDetailContent(", source)
        self.assertIn("BrowserTabRuntimeAssignment(", source)
        self.assertIn("tabID: tab.id", source)
        self.assertIn("spaceID: space.id", source)
        self.assertIn("profileID: space.profile.id", source)

    def test_visual_owners_live_with_their_vertical_features(self) -> None:
        expected_owners = {
            "CrestMac/Features/Browser/Components/BrowserDetailContent/BrowserDetailContent.swift": "BrowserDetailContent",
            "CrestMac/Features/Browser/Components/BrowserDetailContent/Components/BrowserStartPageContent.swift": "BrowserStartPageContent",
            "CrestMac/Features/Browser/Components/BrowserDetailContent/Components/BrowserLivePageContent.swift": "BrowserLivePageContent",
            "CrestMac/Features/Browser/Components/BrowserDetailContent/Components/BrowserUnloadedPageSurface.swift": "BrowserUnloadedPageSurface",
            "CrestMac/Features/Browser/Components/BrowserWebContentView.swift": "BrowserWebContentView",
            "CrestMac/Features/Browser/Components/BrowserWebPageSurface/BrowserWebPageSurface.swift": "BrowserWebPageSurface",
            "CrestMac/Features/Browser/Components/BrowserWebPageSurface/Components/BrowserWebPageFailureOverlay.swift": "BrowserWebPageFailureOverlay",
            "CrestMac/Features/Browser/Components/BrowserWebPageSurface/Components/BrowserDeveloperCaptureFeedbackView.swift": "BrowserDeveloperCaptureFeedbackView",
            "CrestMac/Features/Browser/Components/BrowserFindBar/BrowserFindBar.swift": "BrowserFindBar",
            "CrestMac/Features/Extensions/Components/BrowserChromeWebStoreInstallView/BrowserChromeWebStoreInstallView.swift": "BrowserChromeWebStoreInstallView",
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/BrowserCredentialChrome.swift": "BrowserCredentialChrome",
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/Components/BrowserStrongPasswordPanel.swift": "BrowserStrongPasswordPanel",
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/Components/BrowserCredentialSuggestionPanel.swift": "BrowserCredentialSuggestionPanel",
            "CrestMac/Infrastructure/WebKit/BrowserPlatformWebView.swift": "BrowserPlatformWebView",
        }

        for relative_path, owner in expected_owners.items():
            with self.subTest(owner=owner):
                source = self.source(relative_path)
                declarations = re.findall(
                    r"(?m)^(?:private\s+)?struct\s+([A-Za-z0-9_]+)\b",
                    source,
                )
                self.assertEqual(declarations, [owner])
                self.assertRegex(source, rf"#Preview[\s\S]*\b{owner}\s*\(")

    def test_patch_like_routes_are_exhaustive_values(self) -> None:
        chrome_phase = self.source(
            "CrestMac/Features/Extensions/Components/BrowserChromeWebStoreInstallView/Models/BrowserChromeWebStoreInstallPhase.swift"
        )
        credential_presentation = self.source(
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/Models/BrowserCredentialChromePresentation.swift"
        )
        chrome_view = self.source(
            "CrestMac/Features/Extensions/Components/BrowserChromeWebStoreInstallView/BrowserChromeWebStoreInstallView.swift"
        )
        credential_view = self.source(
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/BrowserCredentialChrome.swift"
        )

        self.assertIn("enum BrowserChromeWebStoreInstallPhase", chrome_phase)
        self.assertIn("static func resolve(", chrome_phase)
        self.assertIn("switch phase", chrome_view)
        self.assertIn("enum BrowserCredentialChromePresentation", credential_presentation)
        self.assertIn("static func resolve(", credential_presentation)
        self.assertIn("switch presentation", credential_view)

    def test_credentials_remain_bound_to_the_pages_space(self) -> None:
        suggestion_panel = self.source(
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/Components/BrowserCredentialSuggestionPanel.swift"
        )
        strong_password_panel = self.source(
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/Components/BrowserStrongPasswordPanel.swift"
        )

        self.assertIn("browser.session.space(id: page.spaceID)", suggestion_panel)
        self.assertIn("in: page.spaceID, using: browser", suggestion_panel)
        self.assertRegex(
            suggestion_panel,
            r"browser\.credential\(\s*id:\s*descriptor\.id,\s*in:\s*page\.spaceID\s*\)",
        )
        self.assertIn("browser.session.space(id: page.spaceID)", strong_password_panel)

    def test_preview_fixtures_are_feature_owned_deterministic_and_isolated(
        self,
    ) -> None:
        fixture_paths = (
            "CrestMac/Features/Browser/Support/BrowserDetailPreviewFixture.swift",
            "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/Support/BrowserCredentialChromePreviewFixture.swift",
            "CrestMac/Features/Extensions/Components/BrowserChromeWebStoreInstallView/Support/BrowserChromeWebStoreInstallPreviewFixture.swift",
        )

        for fixture_path in fixture_paths:
            with self.subTest(fixture_path=fixture_path):
                fixture = self.source(fixture_path)
                self.assertIn("usesEphemeralWebsiteDataStores: true", fixture)
                self.assertIn("browsingMode: .privateBrowsing", fixture)
                self.assertNotRegex(fixture, r"\bUUID\s*\(\s*\)")
                self.assertNotRegex(fixture, r"\bDate\s*\(\s*\)")
                for forbidden in (
                    "UserDefaults",
                    "KeychainCredentialVault",
                    "BrowserStore.production",
                    "BrowserExtensionControllerPool.production",
                    "WKWebsiteDataStore.default",
                ):
                    self.assertNotIn(forbidden, fixture)

        browser_fixture = self.source(fixture_paths[0])
        credential_fixture = self.source(fixture_paths[1])
        self.assertIn("InMemoryBrowserSessionPersistence()", browser_fixture)
        self.assertIn("InMemoryCredentialVault()", browser_fixture)
        self.assertIn("InMemoryBrowserSessionPersistence()", credential_fixture)
        self.assertIn("InMemoryCredentialVault()", credential_fixture)
        self.assertNotIn("BrowserCredentialFillRequest", browser_fixture)
        self.assertNotIn("BrowserCredentialSaveCandidate", browser_fixture)
        self.assertNotIn("BrowserChromeWebStoreCandidate", browser_fixture)

    def test_feature_previews_do_not_depend_on_browser_preview_samples(self) -> None:
        for feature in ("Credentials", "Extensions"):
            feature_root = REPOSITORY_ROOT / f"CrestMac/Features/{feature}"
            for source_path in feature_root.rglob("*.swift"):
                with self.subTest(source_path=source_path):
                    self.assertNotIn(
                        "BrowserDetailPreviewFixture",
                        source_path.read_text(),
                    )


if __name__ == "__main__":
    unittest.main()
