#!/usr/bin/env python3
"""Vertical ownership contract for residual macOS browser detail surfaces."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LEGACY_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Browser/Detail"
MAC_COMPONENT_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Browser/Components"
DEVELOPER_ROOT = MAC_COMPONENT_ROOT / "BrowserDeveloperToolbar"
START_PAGE_ROOT = MAC_COMPONENT_ROOT / "BrowserStartPage"
SITE_SETTINGS_ROOT = REPOSITORY_ROOT / "CrestMac/Features/SiteSettings"
WEB_HOST = REPOSITORY_ROOT / "CrestMac/Infrastructure/WebKit/BrowserWebHostView.swift"

PRIMARY_DECLARATION = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
VISUAL_DECLARATION = re.compile(
    r"^(?:(?:private|fileprivate|internal|public|package|final)\s+)*"
    r"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
    r"(?:View|ButtonStyle)\b",
    re.MULTILINE,
)


class MacBrowserDetailResidualStructureTests(unittest.TestCase):
    def test_legacy_detail_bucket_is_replaced_by_vertical_owners(self) -> None:
        self.assertFalse(LEGACY_ROOT.exists())

        required_files = (
            DEVELOPER_ROOT / "BrowserDeveloperToolbar.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperToolbarButton.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperToolbarDivider.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperSiteSettingsControl.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperAddressField.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperCaptureControls.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperInspectorControls.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperCaptureOptions.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperCapturePreview.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperToolbarBackground.swift",
            DEVELOPER_ROOT / "Components/BrowserRegionCaptureOverlay.swift",
            DEVELOPER_ROOT / "Components/BrowserRegionCaptureInstruction.swift",
            DEVELOPER_ROOT / "Components/BrowserDeveloperToolbarButtonStyle.swift",
            DEVELOPER_ROOT / "Support/BrowserDeveloperToolbarMetrics.swift",
            START_PAGE_ROOT / "BrowserStartPage.swift",
            START_PAGE_ROOT / "Components/BrowserPrivateBrowsingNotice.swift",
            START_PAGE_ROOT / "Components/BrowserStartPageCommandPalette.swift",
            SITE_SETTINGS_ROOT / "BrowserSiteSettingsContent.swift",
            SITE_SETTINGS_ROOT / "Components/BrowserSiteDeveloperModeStatus.swift",
            SITE_SETTINGS_ROOT / "Components/BrowserSiteOriginSettings.swift",
            SITE_SETTINGS_ROOT / "Components/BrowserSiteSecuritySection.swift",
            SITE_SETTINGS_ROOT / "Components/BrowserSitePermissionDisclosure.swift",
            SITE_SETTINGS_ROOT / "Components/BrowserSitePermissionRow.swift",
            SITE_SETTINGS_ROOT / "Models/BrowserSiteCertificatePresentationPolicy.swift",
            SITE_SETTINGS_ROOT / "Models/BrowserSitePermissionDisclosurePolicy.swift",
            SITE_SETTINGS_ROOT / "Services/BrowserSiteCertificatePresenter.swift",
            SITE_SETTINGS_ROOT / "Support/BrowserSiteSettingsPreviewFixture.swift",
            WEB_HOST,
        )
        for path in required_files:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

    def test_each_owner_has_one_matching_primary_type(self) -> None:
        roots = (DEVELOPER_ROOT, START_PAGE_ROOT, SITE_SETTINGS_ROOT)
        source_paths = [WEB_HOST]
        for root in roots:
            source_paths.extend(sorted(root.rglob("*.swift")))

        for path in source_paths:
            declarations = PRIMARY_DECLARATION.findall(path.read_text())
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, [path.stem])

    def test_visual_owners_have_direct_isolated_previews(self) -> None:
        for root in (DEVELOPER_ROOT, START_PAGE_ROOT, SITE_SETTINGS_ROOT):
            for path in root.rglob("*.swift"):
                source = path.read_text()
                owners = VISUAL_DECLARATION.findall(source)
                if not owners:
                    continue
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(owners, [path.stem])
                    preview = source[source.index("#Preview") :]
                    self.assertIn(f"{path.stem}(", preview)
                    for forbidden in (
                        "BrowserStore.production",
                        "BrowserWebsiteDataStore.persistent",
                        "UserDefaults",
                        "WKWebsiteDataStore.default",
                        "UUID()",
                        "Date()",
                    ):
                        self.assertNotIn(forbidden, preview)

    def test_site_and_developer_actions_keep_exact_page_and_space_scope(self) -> None:
        developer_source = "\n".join(
            path.read_text() for path in DEVELOPER_ROOT.rglob("*.swift")
        )
        site_source = "\n".join(
            path.read_text() for path in SITE_SETTINGS_ROOT.rglob("*.swift")
        )

        self.assertIn("pages.activePage === page", developer_source)
        self.assertIn("browser.navigateSelectedTab(to: url)", developer_source)
        self.assertIn("page.load(url)", developer_source)
        self.assertIn("spaceID: page.spaceID", site_source)
        self.assertIn("permissionCenter.setDecision(", site_source)
        self.assertNotRegex(site_source, r"spaces\s*\[")

    def test_platform_frameworks_stay_in_explicit_adapters(self) -> None:
        presenter = SITE_SETTINGS_ROOT / "Services/BrowserSiteCertificatePresenter.swift"
        self.assertIn("import SecurityInterface", presenter.read_text())
        self.assertIn("import WebKit", WEB_HOST.read_text())

        for root in (DEVELOPER_ROOT, START_PAGE_ROOT):
            for path in root.rglob("*.swift"):
                source = path.read_text()
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertNotIn("import WebKit", source)
                    self.assertNotIn("import SecurityInterface", source)


if __name__ == "__main__":
    unittest.main()
