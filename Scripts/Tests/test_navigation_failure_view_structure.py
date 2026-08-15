#!/usr/bin/env python3
"""Vertical structure and behavior seams for Crest navigation-failure UI."""

from __future__ import annotations

from pathlib import Path
import re
import runpy
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FAMILY_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Navigation/BrowserNavigationFailureView"
)
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

PRIMARY_OWNERS = {
    "BrowserNavigationFailureView.swift": "BrowserNavigationFailureView",
    "Components/BrowserNavigationFailureContent.swift": (
        "BrowserNavigationFailureContent"
    ),
    "Components/BrowserNavigationFailureActions/BrowserNavigationFailureActions.swift": (
        "BrowserNavigationFailureActions"
    ),
    "Components/BrowserNavigationFailureActions/Components/BrowserNavigationFailureBackButton.swift": (
        "BrowserNavigationFailureBackButton"
    ),
    "Components/BrowserNavigationFailureActions/Components/BrowserNavigationFailureDetailsButton.swift": (
        "BrowserNavigationFailureDetailsButton"
    ),
    "Components/BrowserNavigationFailureActions/Components/BrowserNavigationFailureRetryButton.swift": (
        "BrowserNavigationFailureRetryButton"
    ),
    "Components/BrowserNavigationFailureHeadline.swift": (
        "BrowserNavigationFailureHeadline"
    ),
    "Components/BrowserNavigationFailureStatusIcon.swift": (
        "BrowserNavigationFailureStatusIcon"
    ),
    "Components/BrowserNavigationFailureSuggestions/BrowserNavigationFailureSuggestions.swift": (
        "BrowserNavigationFailureSuggestions"
    ),
    "Components/BrowserNavigationFailureSuggestions/Components/BrowserNavigationFailureSuggestionRow.swift": (
        "BrowserNavigationFailureSuggestionRow"
    ),
    "Components/BrowserNavigationFailureTechnicalDetails/BrowserNavigationFailureTechnicalDetails.swift": (
        "BrowserNavigationFailureTechnicalDetails"
    ),
    "Components/BrowserNavigationFailureTechnicalDetails/Components/BrowserNavigationFailureDetailRow.swift": (
        "BrowserNavigationFailureDetailRow"
    ),
    "Models/BrowserNavigationFailureLayout.swift": (
        "BrowserNavigationFailureLayout"
    ),
    "Models/BrowserNavigationFailurePresentation.swift": (
        "BrowserNavigationFailurePresentation"
    ),
    "Support/BrowserNavigationFailureAppearance.swift": (
        "BrowserNavigationFailureAppearance"
    ),
    "Support/BrowserNavigationFailureMetrics.swift": (
        "BrowserNavigationFailureMetrics"
    ),
    "Support/BrowserNavigationFailurePreviewFixture.swift": (
        "BrowserNavigationFailurePreviewFixture"
    ),
}

EXTENSION_OWNERS = {
    "Support/BrowserNavigationFailure+Presentation.swift": (
        "BrowserNavigationFailure"
    ),
}

VISUAL_OWNERS = {
    relative_path: owner
    for relative_path, owner in PRIMARY_OWNERS.items()
    if relative_path == "BrowserNavigationFailureView.swift"
    or relative_path.startswith("Components/")
}

EXPECTED_DIRECTORIES = {
    "Components",
    "Components/BrowserNavigationFailureActions",
    "Components/BrowserNavigationFailureActions/Components",
    "Components/BrowserNavigationFailureSuggestions",
    "Components/BrowserNavigationFailureSuggestions/Components",
    "Components/BrowserNavigationFailureTechnicalDetails",
    "Components/BrowserNavigationFailureTechnicalDetails/Components",
    "Models",
    "Support",
}

LIVE_OR_NONDETERMINISTIC_PREVIEW_PATTERNS = {
    "production browser graph": re.compile(
        r"\b(?:BrowserSession\s*\.\s*preview|BrowserStore\s*\.\s*production)\b"
    ),
    "persistent state": re.compile(
        r"\b(?:UserDefaults|AppStorage|FileManager|FileHandle|Keychain\w*)\b"
    ),
    "network": re.compile(r"\b(?:URLSession\w*|AsyncImage)\b"),
    "WebKit": re.compile(r"\bWK(?:WebView|WebsiteDataStore|ContentRuleListStore)\b"),
    "disk read": re.compile(
        r"\b(?:Data|NSData|NSImage|String|UIImage)\s*\(\s*contentsOf"
    ),
    "UUID()": re.compile(r"\bUUID\s*\(\s*\)"),
    "Date()": re.compile(r"\bDate\s*\(\s*\)"),
    "Date.now": re.compile(r"(?:\bDate\s*\.\s*now\b|(?<!\w)\.now\b)"),
    "random value": re.compile(
        r"(?:\brandom\s*\(|\.\s*(?:random|randomElement|shuffled)\s*\()"
    ),
}


def without_whitespace(source: str) -> str:
    return re.sub(r"\s+", "", source)


class NavigationFailureViewStructureTests(unittest.TestCase):
    def source(self, relative_path: str) -> str:
        path = FAMILY_ROOT / relative_path
        self.assertTrue(path.is_file(), relative_path)
        return path.read_text()

    def test_family_has_the_exact_vertical_topology(self) -> None:
        expected_sources = set(PRIMARY_OWNERS) | set(EXTENSION_OWNERS)
        actual_sources = {
            str(path.relative_to(FAMILY_ROOT))
            for path in FAMILY_ROOT.rglob("*.swift")
        }
        self.assertEqual(actual_sources, expected_sources)

        actual_directories = {
            str(path.relative_to(FAMILY_ROOT))
            for path in FAMILY_ROOT.rglob("*")
            if path.is_dir()
        }
        self.assertEqual(actual_directories, EXPECTED_DIRECTORIES)

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Features/Navigation/BrowserNavigationFailureView.swift"
            ).exists()
        )
        self.assertFalse((FAMILY_ROOT / "Policies").exists())
        self.assertFalse((FAMILY_ROOT / "Previews").exists())
        self.assertEqual(list(FAMILY_ROOT.rglob("*Previews.swift")), [])

    def test_every_source_has_one_matching_file_scope_declaration(self) -> None:
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_declarations = VERTICAL_GUARD["_top_level_global_content"]

        for relative_path, owner in PRIMARY_OWNERS.items():
            source = self.source(relative_path)
            primaries = primary_declarations(source)
            extensions = extension_declarations(source)
            globals_ = global_declarations(source)
            with self.subTest(relative_path=relative_path):
                self.assertEqual(
                    len(primaries) + len(extensions) + len(globals_),
                    1,
                )
                self.assertEqual(len(primaries), 1)
                self.assertEqual(primaries[0].name, owner)
                self.assertEqual(extensions, [])
                self.assertEqual(globals_, [])
                self.assertEqual(Path(relative_path).stem, owner)

        for relative_path, owner in EXTENSION_OWNERS.items():
            source = self.source(relative_path)
            primaries = primary_declarations(source)
            extensions = extension_declarations(source)
            globals_ = global_declarations(source)
            with self.subTest(relative_path=relative_path):
                self.assertEqual(primaries, [])
                self.assertEqual(len(extensions), 1)
                self.assertEqual(extensions[0].target, owner)
                self.assertEqual(globals_, [])
                self.assertEqual(Path(relative_path).stem.split("+", 1)[0], owner)

    def test_root_is_a_small_stateful_shell_composing_real_content(self) -> None:
        root = self.source("BrowserNavigationFailureView.swift")

        self.assertIn("struct BrowserNavigationFailureView: View", root)
        self.assertIn("@State private var showsDetails = false", root)
        self.assertIn("BrowserNavigationFailureContent(", root)
        self.assertIn("retry: retry", root)
        self.assertIn("goBack: goBack", root)
        self.assertIn("toggleDetails: toggleDetails", root)
        self.assertNotIn("BrowserNavigationFailureStatusIcon(", root)
        self.assertNotIn("BrowserNavigationFailureHeadline(", root)
        self.assertNotIn("BrowserNavigationFailureSuggestions(", root)
        self.assertNotIn("BrowserNavigationFailureActions(", root)
        self.assertNotIn("BrowserNavigationFailureTechnicalDetails(", root)
        self.assertNotRegex(root, r"private\s+(?:var|func)\s+\w+[^\n]*some\s+View")

        for contract in (
            ".frame(maxWidth: .infinity, maxHeight: .infinity)",
            ".background(.background)",
            ".accessibilityElement(children: .contain)",
            '.accessibilityIdentifier("navigation-failure")',
        ):
            self.assertIn(contract, root)

    def test_content_preserves_component_order_layout_and_details_transition(self) -> None:
        content = self.source(
            "Components/BrowserNavigationFailureContent.swift"
        )
        compact = without_whitespace(content)

        ordered_owners = (
            "BrowserNavigationFailureStatusIcon(",
            "BrowserNavigationFailureHeadline(",
            "BrowserNavigationFailureSuggestions(",
            "BrowserNavigationFailureActions(",
            "BrowserNavigationFailureTechnicalDetails(",
        )
        offsets = [compact.index(owner) for owner in ordered_owners]
        self.assertEqual(offsets, sorted(offsets))
        self.assertIn("ifshowsDetails{", compact)
        self.assertIn(".transition(.opacity)", content)
        self.assertIn(
            "maxWidth: BrowserNavigationFailureMetrics.maximumContentWidth",
            content,
        )
        self.assertIn("alignment: layout.frameAlignment", content)
        self.assertIn(".padding(.horizontal, layout.horizontalPadding)", content)
        self.assertIn(".padding(.vertical, layout.verticalPadding)", content)
        self.assertIn("retry: retry", content)
        self.assertIn("goBack: goBack", content)
        self.assertIn("toggleDetails: toggleDetails", content)

    def test_actions_preserve_compact_and_regular_order_and_exact_callbacks(self) -> None:
        actions = self.source(
            "Components/BrowserNavigationFailureActions/BrowserNavigationFailureActions.swift"
        )
        compact_source, regular_source = actions.split("} else {", maxsplit=1)

        compact_order = (
            "BrowserNavigationFailureRetryButton(",
            "BrowserNavigationFailureBackButton(",
            "BrowserNavigationFailureDetailsButton(",
        )
        regular_order = (
            "BrowserNavigationFailureDetailsButton(",
            "BrowserNavigationFailureBackButton(",
            "Spacer(minLength: CrestSpacing.extraExtraLarge)",
            "BrowserNavigationFailureRetryButton(",
        )
        compact_offsets = [compact_source.index(owner) for owner in compact_order]
        regular_offsets = [regular_source.index(owner) for owner in regular_order]
        self.assertEqual(compact_offsets, sorted(compact_offsets))
        self.assertEqual(regular_offsets, sorted(regular_offsets))
        self.assertGreaterEqual(actions.count("if canGoBack"), 2)
        self.assertIn("action: retry", actions)
        self.assertIn("action: goBack", actions)
        self.assertIn("action: toggleDetails", actions)

    def test_action_components_preserve_style_accessibility_and_callbacks(self) -> None:
        contracts = {
            "Components/BrowserNavigationFailureActions/Components/BrowserNavigationFailureRetryButton.swift": (
                'Button("Try Again", systemImage: "arrow.clockwise", action: action)',
                ".buttonStyle(.borderedProminent)",
                '.accessibilityHint("Retries the failed address")',
                '.accessibilityIdentifier("navigation-failure-retry")',
            ),
            "Components/BrowserNavigationFailureActions/Components/BrowserNavigationFailureBackButton.swift": (
                'Button("Go Back", systemImage: "chevron.backward", action: action)',
                ".buttonStyle(.bordered)",
                '.accessibilityHint("Returns to the last page")',
                '.accessibilityIdentifier("navigation-failure-back")',
            ),
            "Components/BrowserNavigationFailureActions/Components/BrowserNavigationFailureDetailsButton.swift": (
                "Button(action: action)",
                ".buttonStyle(.bordered)",
                'showsDetails ? "Hide Details" : "Details"',
                '.accessibilityIdentifier("navigation-failure-details")',
            ),
        }

        for relative_path, required_tokens in contracts.items():
            source = self.source(relative_path)
            with self.subTest(relative_path=relative_path):
                for token in required_tokens:
                    self.assertIn(token, source)
                self.assertIn(".controlSize(.large)", source)

    def test_details_animation_branding_and_technical_copy_are_preserved(self) -> None:
        root = self.source("BrowserNavigationFailureView.swift")
        appearance = self.source(
            "Support/BrowserNavigationFailureAppearance.swift"
        )
        details = self.source(
            "Components/BrowserNavigationFailureTechnicalDetails/BrowserNavigationFailureTechnicalDetails.swift"
        )
        compact_details = without_whitespace(details)
        presentation = self.source(
            "Models/BrowserNavigationFailurePresentation.swift"
        )
        browser_codes = self.source(
            "Support/BrowserNavigationFailure+Presentation.swift"
        )

        for token in (
            "withAnimation(",
            "BrowserVisualAccessibilityPolicy.animation(",
            "CrestMotion.recovery",
            "reduceMotion: reduceMotion",
            "showsDetails.toggle()",
        ):
            self.assertIn(token, root)
        self.assertIn("branding?.primaryColor", appearance)

        for token in (
            'BrowserNavigationFailureDetailRow(label:"Address"',
            'BrowserNavigationFailureDetailRow(label:"ErrorDomain"',
            'BrowserNavigationFailureDetailRow(label:"ErrorNumber"',
            'label:"LoadingStage"',
            'String(localized:"Beforecontentloaded")',
            'String(localized:"Aftercontentstartedloading")',
        ):
            self.assertIn(token, compact_details)
        for token in (
            "You’re offline",
            "This site took too long to respond",
            "A secure connection couldn’t be made",
            "The web content process stopped repeatedly.",
        ):
            self.assertIn(token, presentation)
        for token in (
            "CREST_INTERNET_DISCONNECTED",
            "CREST_CERTIFICATE_INVALID",
            "CREST_WEB_PROCESS_STOPPED",
            "CREST_NAVIGATION_FAILED",
        ):
            self.assertIn(token, browser_codes)

    def test_every_visual_owner_has_a_direct_deterministic_colocated_preview(
        self,
    ) -> None:
        direct_preview_exists = VERTICAL_GUARD["_direct_preview_exists"]
        self.assertEqual(len(VISUAL_OWNERS), 12)

        for relative_path, owner in VISUAL_OWNERS.items():
            source = self.source(relative_path)
            with self.subTest(relative_path=relative_path):
                self.assertTrue(
                    direct_preview_exists(source, owner),
                    f"No colocated #Preview directly invokes {owner}",
                )
                for subject, pattern in LIVE_OR_NONDETERMINISTIC_PREVIEW_PATTERNS.items():
                    self.assertNotRegex(source, pattern, subject)

    def test_preview_fixture_is_fixed_non_http_and_dependency_free(self) -> None:
        fixture = self.source(
            "Support/BrowserNavigationFailurePreviewFixture.swift"
        )

        self.assertIn("enum BrowserNavigationFailurePreviewFixture", fixture)
        self.assertIn("URLError(.notConnectedToInternet)", fixture)
        self.assertIn("URLError(.secureConnectionFailed)", fixture)
        self.assertIn("BrowserSpaceBranding(colors:", fixture)
        self.assertRegex(fixture, r"crest-preview://|URL\s*\(\s*filePath:")
        self.assertNotRegex(fixture, r"https?://")
        for subject, pattern in LIVE_OR_NONDETERMINISTIC_PREVIEW_PATTERNS.items():
            with self.subTest(subject=subject):
                self.assertNotRegex(fixture, pattern)

    def test_platform_consumers_keep_exact_page_callbacks_and_layouts(self) -> None:
        mac = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Browser/Components/BrowserWebPageSurface/Components/BrowserWebPageFailureOverlay.swift"
        ).read_text()
        mobile = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Browser/MobileBrowserRootView/Components/MobileBrowserDetailView.swift"
        ).read_text()

        for platform, source in (("mac", mac), ("mobile", mobile)):
            with self.subTest(platform=platform):
                self.assertIn("retry: page.retryAfterNavigationFailure", source)
                self.assertIn("goBack: page.returnFromNavigationFailure", source)
                self.assertIn("retry: page.retryAfterProcessFailure", source)
        self.assertGreaterEqual(mac.count("layout: .regular"), 2)
        self.assertGreaterEqual(
            mobile.count("layout: isCompact ? .compact : .regular"),
            2,
        )

    def test_geometry_keeps_named_metrics_and_design_tokens(self) -> None:
        visual_source = "\n".join(
            self.source(relative_path) for relative_path in VISUAL_OWNERS
        )
        self.assertIn("BrowserNavigationFailureMetrics", visual_source)
        self.assertIn("CrestSpacing", visual_source)
        self.assertNotIn("spacing: 10", visual_source)
        self.assertNotIn(".padding(18)", visual_source)


if __name__ == "__main__":
    unittest.main()
