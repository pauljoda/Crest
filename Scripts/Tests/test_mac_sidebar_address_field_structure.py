#!/usr/bin/env python3
"""Vertical ownership contract for the macOS Sidebar address field."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SIDEBAR_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Sidebar"
ADDRESS_ROOT = SIDEBAR_ROOT / "SidebarAddressField"

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
    r"(?:View|ViewModifier)\b",
    re.MULTILINE,
)


class MacSidebarAddressFieldStructureTests(unittest.TestCase):
    def test_address_field_is_a_named_vertical_feature_family(self) -> None:
        self.assertFalse((SIDEBAR_ROOT / "SidebarAddressField.swift").exists())
        required_files = (
            ADDRESS_ROOT / "SidebarAddressField.swift",
            ADDRESS_ROOT / "Components/SidebarAddressFieldContent.swift",
            ADDRESS_ROOT / "Components/BrowserAddressLeadingControl.swift",
            ADDRESS_ROOT / "Components/BrowserAddressPlaceholderGlyph.swift",
            ADDRESS_ROOT / "Components/BrowserAddressEditor.swift",
            ADDRESS_ROOT / "Components/BrowserAddressClearButton.swift",
            ADDRESS_ROOT / "Components/BrowserAddressSecurityButton.swift",
            ADDRESS_ROOT / "Components/BrowserAddressSecurityIcon.swift",
            ADDRESS_ROOT / "Models/SidebarAddressFieldConfiguration.swift",
            ADDRESS_ROOT / "Support/BrowserAddressSecurityControlPolicy.swift",
            ADDRESS_ROOT / "Support/BrowserAddressLeadingControlPolicy.swift",
            ADDRESS_ROOT / "Components/BrowserAddressFieldSurface.swift",
            ADDRESS_ROOT / "Support/View+BrowserAddressFieldSurface.swift",
            ADDRESS_ROOT / "Support/SidebarAddressFieldPreviewFixture.swift",
        )
        for source_file in required_files:
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_file.is_file())

    def test_each_source_has_one_matching_primary_owner(self) -> None:
        for source_file in ADDRESS_ROOT.rglob("*.swift"):
            declarations = PRIMARY_DECLARATION.findall(source_file.read_text())
            expected = [] if "+" in source_file.stem else [source_file.stem]
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected)

    def test_each_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        for source_file in ADDRESS_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            owners = VISUAL_DECLARATION.findall(source)
            if not owners:
                continue
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(owners, [source_file.stem])
                preview = source[source.index("#Preview") :]
                self.assertIn(f"{source_file.stem}(", preview)
                for forbidden in (
                    "BrowserStore.production",
                    "UserDefaults",
                    "WKWebsiteDataStore.default",
                    "UUID()",
                    "Date()",
                ):
                    self.assertNotIn(forbidden, preview)

    def test_security_and_placeholder_policies_remain_exact(self) -> None:
        source = "\n".join(
            source_file.read_text()
            for source_file in ADDRESS_ROOT.rglob("*.swift")
        )
        for required in (
            "BrowserTabTrailingControlPolicy.minimumHitTarget",
            "!isAddressEditing && hasActiveSite",
            "return !hasAddress || hasResidentPage",
            "page.webView.serverTrust != nil",
            "BrowserSiteCertificatePresenter.present(",
            'accessibilityIdentifier("browser-address-security")',
            'Button("Clear", systemImage: "xmark.circle.fill")',
        ):
            self.assertIn(required, source)
        self.assertNotRegex(source, r"spaces\s*\[")

    def test_surface_preserves_progress_and_accessibility_behavior(self) -> None:
        surface = (
            ADDRESS_ROOT / "Components/BrowserAddressFieldSurface.swift"
        ).read_text()
        for required in (
            "BrowserVisualAccessibilityPolicy.animation(",
            "CrestMotion.loadingProgress",
            "reduceMotion: reduceMotion",
            "CGFloat(min(max(progress, 0.04), 1))",
            "BrowserChromeLayout.addressEditingRingWidth",
            "BrowserChromeLayout.addressCornerRadius",
        ):
            self.assertIn(required, surface)

    def test_preview_uses_private_in_memory_and_ephemeral_owners(self) -> None:
        fixture = (
            SIDEBAR_ROOT / "Support/BrowserSidebarExtensionPreviewFixture.swift"
        ).read_text()
        address_fixture = (
            ADDRESS_ROOT / "Support/SidebarAddressFieldPreviewFixture.swift"
        ).read_text()
        self.assertIn("BrowserSidebarExtensionPreviewFixture.makeContext()", address_fixture)
        self.assertRegex(fixture, r"UUID\s*\(\s*uuid:")
        for required in (
            "Date(timeIntervalSince1970:",
            "InMemoryBrowserSessionPersistence()",
            "browsingMode: .privateBrowsing",
            "usesEphemeralWebsiteDataStores: true",
        ):
            self.assertIn(required, fixture)
        for forbidden in (
            "UserDefaults",
            ".production(",
            "BrowserWebsiteDataStore.persistent",
            "WKWebsiteDataStore.default",
        ):
            self.assertNotIn(forbidden, fixture + address_fixture)


if __name__ == "__main__":
    unittest.main()
