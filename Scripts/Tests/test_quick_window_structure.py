#!/usr/bin/env python3
"""Vertical ownership and isolation contracts for macOS Quick Window."""

from __future__ import annotations

import pathlib
import re
import runpy
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
QUICK_WINDOW_ROOT = REPOSITORY_ROOT / "CrestMac/Features/QuickWindow"
VIEW_ROOT = QUICK_WINDOW_ROOT / "BrowserQuickWindowView"
DOMAIN_REQUEST = (
    REPOSITORY_ROOT
    / "CrestShared/Domain/BrowserTransientBrowsing/QuickWindow/BrowserQuickWindowRequest.swift"
)
DOMAIN_REQUEST_IDENTITY = (
    REPOSITORY_ROOT
    / "CrestShared/Domain/BrowserTransientBrowsing/QuickWindow/BrowserQuickWindowRequest+PresentationIdentity.swift"
)
MOBILE_TRANSIENT_SURFACE = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/TransientBrowsing/MobileBrowserTransientOverlay.swift"
)
MOBILE_TRANSIENT_CONTENT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/TransientBrowsing/Components/MobileBrowserTransientOverlayContent.swift"
)
MOBILE_TRANSIENT_MODEL = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/TransientBrowsing/Models/MobileBrowserTransientOverlayModel.swift"
)
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


class QuickWindowStructureTests(unittest.TestCase):
    def test_vertical_owner_topology_is_complete(self) -> None:
        required_files = (
            "BrowserQuickWindowScene.swift",
            "Models/BrowserQuickWindowBrowsingContext.swift",
            "Services/BrowserQuickWindowContextResolver.swift",
            "Support/BrowserQuickWindowChromePolicy.swift",
            "Support/BrowserQuickWindowLayout.swift",
            "Support/BrowserQuickWindowPreviewFixture.swift",
            "Support/BrowserQuickWindowPreviewAuthenticator.swift",
            "BrowserQuickWindowView/BrowserQuickWindowView.swift",
            "BrowserQuickWindowView/Models/BrowserQuickWindowModel.swift",
            "BrowserQuickWindowView/Services/BrowserQuickWindowRequestLifecycle.swift",
            "BrowserQuickWindowView/Components/BrowserQuickWindowContent.swift",
            "BrowserQuickWindowView/Components/BrowserQuickWindowWindowSurface/BrowserQuickWindowWindowSurface.swift",
            "BrowserQuickWindowView/Components/BrowserQuickWindowUnlockedContent/BrowserQuickWindowUnlockedContent.swift",
            "BrowserQuickWindowView/Components/BrowserQuickWindowPageSurface/BrowserQuickWindowPageSurface.swift",
            "BrowserQuickWindowView/Components/BrowserQuickWindowToolbar/BrowserQuickWindowToolbar.swift",
            "BrowserQuickWindowView/Components/BrowserQuickWindowAddressControl/BrowserQuickWindowAddressControl.swift",
            "BrowserQuickWindowView/Components/BrowserQuickWindowDestinationControl.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((QUICK_WINDOW_ROOT / relative_path).is_file())

        self.assertFalse((QUICK_WINDOW_ROOT / "Modifiers").exists())
        self.assertFalse((QUICK_WINDOW_ROOT / "Policies").exists())
        self.assertFalse((QUICK_WINDOW_ROOT / "BrowserQuickWindowView.swift").exists())
        self.assertTrue(DOMAIN_REQUEST_IDENTITY.is_file())

    def test_each_owner_file_has_one_matching_declaration(self) -> None:
        for source_file in QUICK_WINDOW_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            declarations = DECLARATION_PATTERN.findall(source)
            with self.subTest(source_file=source_file.relative_to(REPOSITORY_ROOT)):
                if "+" in source_file.stem:
                    self.assertEqual(declarations, [])
                else:
                    self.assertEqual(declarations, [source_file.stem])

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        visual_pattern = re.compile(r"\b(?:struct|class)\s+(\w+)\s*:\s*(?:View|ViewModifier)\b")
        for source_file in QUICK_WINDOW_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            for owner in visual_pattern.findall(source):
                with self.subTest(owner=owner):
                    self.assertIn("#Preview", source)
                    preview_source = source[source.index("#Preview") :]
                    self.assertIn(owner, preview_source)

        fixture = (
            QUICK_WINDOW_ROOT / "Support/BrowserQuickWindowPreviewFixture.swift"
        ).read_text()
        self.assertRegex(fixture, r"UUID\(\s*uuid:\s*\(")
        self.assertIn("id: uuid(0x41)", fixture)
        self.assertIn("Date(timeIntervalSince1970: 0)", fixture)
        self.assertIn("InMemoryBrowserSessionPersistence", fixture)
        self.assertIn("InMemoryCredentialVault", fixture)
        self.assertIn("BrowserQuickWindowPreviewAuthenticator", fixture)
        for subject, pattern in (
            *VERTICAL_GUARD["LIVE_PREVIEW_PATTERNS"],
            *VERTICAL_GUARD["NONDETERMINISTIC_PREVIEW_PATTERNS"],
        ):
            with self.subTest(subject=subject):
                self.assertIsNone(pattern.search(fixture))
        model = (
            QUICK_WINDOW_ROOT
            / "BrowserQuickWindowView/Models/BrowserQuickWindowModel.swift"
        ).read_text()
        self.assertIn("pages = nil", model)
        self.assertIn("preferences = .isolated", model)
        self.assertIn("now: Date(timeIntervalSince1970: 0)", model)
        for forbidden in (
            "UserDefaults",
            "@AppStorage",
            "Keychain",
            ".standard",
            "BrowserPagePool(",
            "WKWebView",
            "UUID()",
            "Date()",
            "Date.now",
            "FileManager",
            "URLSession",
            "Data(contentsOf:",
        ):
            self.assertNotIn(forbidden, fixture)

        for source_file in QUICK_WINDOW_ROOT.rglob("*.swift"):
            source = source_file.read_text()
            if "#Preview" in source:
                preview_source = source[source.index("#Preview") :]
                with self.subTest(source_file=source_file):
                    self.assertNotIn("BrowserSpaceAccessController()", preview_source)
                    self.assertNotIn(
                        "BrowserQuickWindowPreviewFixture.makePages()",
                        preview_source,
                    )

    def test_runtime_uses_exact_space_and_profile_assignments(self) -> None:
        request_source = DOMAIN_REQUEST.read_text()
        model_source = (
            VIEW_ROOT / "Models/BrowserQuickWindowModel.swift"
        ).read_text()
        lease_source = (
            REPOSITORY_ROOT / "CrestMac/Infrastructure/WebKit/BrowserTransientPageLease.swift"
        ).read_text()

        self.assertIn("let spaceAssignment: BrowserSpaceRuntimeAssignment", request_source)
        self.assertIn(
            "hasSamePresentationIdentity",
            DOMAIN_REQUEST_IDENTITY.read_text(),
        )
        self.assertIn("let profileID: UUID", lease_source)
        self.assertIn("pageLease.assignment == assignment", model_source)
        self.assertIn("matching: pageLease.assignment", model_source)
        self.assertIn("browser.deletingSpaceIDs", model_source)
        self.assertNotIn("selectedSpaceID", model_source)
        scene_source = (
            QUICK_WINDOW_ROOT / "BrowserQuickWindowScene.swift"
        ).read_text()
        self.assertIn("hasSamePresentationIdentity", scene_source)

        observation = (
            VIEW_ROOT
            / "Components/BrowserQuickWindowUnlockedContent/Components/BrowserQuickWindowPageObservationModifier.swift"
        ).read_text()
        self.assertIn("model.recordCompletedNavigation()", observation)

    def test_space_picker_row_uses_full_width_button_hit_testing(self) -> None:
        source = (
            VIEW_ROOT
            / "Components/BrowserQuickWindowDestinationControl/Components/BrowserQuickWindowSpacePickerRow.swift"
        ).read_text()
        label_start = source.index("Button(action: select) {")
        button_style = source.index(".buttonStyle(.plain)", label_start)
        label_source = source[label_start:button_style]

        self.assertIn(".frame(maxWidth: .infinity)", label_source)
        self.assertIn(".contentShape(.rect)", label_source)

    def test_mobile_quick_window_dismisses_when_its_exact_runtime_disappears(self) -> None:
        source = MOBILE_TRANSIENT_SURFACE.read_text()
        content_source = MOBILE_TRANSIENT_CONTENT.read_text()
        model_source = MOBILE_TRANSIENT_MODEL.read_text()

        self.assertIn("MobileBrowserTransientOverlayModel", source)
        self.assertIn("if space == nil", content_source)
        self.assertIn("pageLease.assignment == request.spaceAssignment", model_source)
        self.assertIn(
            "browser.space(matching: request.spaceAssignment)",
            model_source,
        )
        self.assertIn("dismissUnavailableRequest", model_source)
        self.assertIn("quickWindowRequest.retargeted(", model_source)


if __name__ == "__main__":
    unittest.main()
