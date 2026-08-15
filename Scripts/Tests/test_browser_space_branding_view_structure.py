#!/usr/bin/env python3
"""Structural contracts for the shared Space-branding component family."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
SHARED_SPACES_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Spaces"
VISUAL_ROOT = SHARED_SPACES_ROOT / "Components/BrowserSpaceBranding"
PRESENTATION_MODELS_ROOT = SHARED_SPACES_ROOT / "Models/BrowserSpaceBranding"
SUPPORT_ROOT = SHARED_SPACES_ROOT / "Support/BrowserSpaceBranding"
PREVIEW_FIXTURE = (
    SHARED_SPACES_ROOT / "Support/BrowserSpaceBrandingPreviewFixture.swift"
)

CURRENT_VISUAL_OWNERS = {
    VISUAL_ROOT / "BrowserSpaceBannerBackground.swift": (
        "BrowserSpaceBannerBackground"
    ),
    VISUAL_ROOT / "Components/Banner/BrowserSpaceBannerField.swift": (
        "BrowserSpaceBannerField"
    ),
    VISUAL_ROOT / "Components/Banner/BrowserSpaceGradientField.swift": (
        "BrowserSpaceGradientField"
    ),
    VISUAL_ROOT / "Components/Banner/BrowserSpaceThemeField.swift": (
        "BrowserSpaceThemeField"
    ),
    VISUAL_ROOT / "Components/Banner/BrowserSpaceThemeTexture.swift": (
        "BrowserSpaceThemeTexture"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestBackplateMask.swift": (
        "BrowserSpaceCrestBackplateMask"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestChargeImage.swift": (
        "BrowserSpaceCrestChargeImage"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestChargeView.swift": (
        "BrowserSpaceCrestChargeView"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestField.swift": (
        "BrowserSpaceCrestField"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestIcon.swift": (
        "BrowserSpaceCrestIcon"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestOrdinaryView.swift": (
        "BrowserSpaceCrestOrdinaryView"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestRasterization.swift": (
        "BrowserSpaceCrestRasterization"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestTrimView.swift": (
        "BrowserSpaceCrestTrimView"
    ),
    VISUAL_ROOT / "Components/Identity/BrowserSpaceIdentityIcon.swift": (
        "BrowserSpaceIdentityIcon"
    ),
    VISUAL_ROOT / "Components/Identity/BrowserSpaceIdentityLabel.swift": (
        "BrowserSpaceIdentityLabel"
    ),
    VISUAL_ROOT / "Components/Identity/BrowserSpaceSymbolArtwork.swift": (
        "BrowserSpaceSymbolArtwork"
    ),
    VISUAL_ROOT / "Components/Identity/BrowserSpaceSymbolArtworkContent.swift": (
        "BrowserSpaceSymbolArtworkContent"
    ),
    VISUAL_ROOT / "Components/Shapes/BrowserSpaceChevronLowerBannerShape.swift": (
        "BrowserSpaceChevronLowerBannerShape"
    ),
    VISUAL_ROOT / "Components/Shapes/BrowserSpaceChevronMiddleBannerShape.swift": (
        "BrowserSpaceChevronMiddleBannerShape"
    ),
    VISUAL_ROOT / "Components/Shapes/BrowserSpaceCrestChevronFieldShape.swift": (
        "BrowserSpaceCrestChevronFieldShape"
    ),
    VISUAL_ROOT / "Components/Shapes/BrowserSpaceDiagonalLowerBannerShape.swift": (
        "BrowserSpaceDiagonalLowerBannerShape"
    ),
    VISUAL_ROOT / "Components/Shapes/BrowserSpaceDiagonalMiddleBannerShape.swift": (
        "BrowserSpaceDiagonalMiddleBannerShape"
    ),
}

EXTRACTED_VISUAL_OWNERS = {
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestOrdinaryBar.swift": (
        "BrowserSpaceCrestOrdinaryBar"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestOrdinaryChief.swift": (
        "BrowserSpaceCrestOrdinaryChief"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestOrdinaryShape.swift": (
        "BrowserSpaceCrestOrdinaryShape"
    ),
    VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestOrdinarySymbol.swift": (
        "BrowserSpaceCrestOrdinarySymbol"
    ),
}

COMPONENT_MODEL_OWNERS = {
    VISUAL_ROOT / "Models/BrowserSpaceIdentityArtwork.swift": (
        "BrowserSpaceIdentityArtwork"
    ),
    VISUAL_ROOT / "Models/BrowserSpaceRenderedSymbolArtwork.swift": (
        "BrowserSpaceRenderedSymbolArtwork"
    ),
    VISUAL_ROOT / "Models/BrowserSpaceSymbolArtworkIdentity.swift": (
        "BrowserSpaceSymbolArtworkIdentity"
    ),
    VISUAL_ROOT / "Models/BrowserSpaceTextureGenerator.swift": (
        "BrowserSpaceTextureGenerator"
    ),
}

PRESENTATION_MODEL_OWNERS = {
    PRESENTATION_MODELS_ROOT / "BrowserSpaceBrandingPreset.swift": (
        "BrowserSpaceBrandingPreset"
    ),
    PRESENTATION_MODELS_ROOT
    / "BrowserSpaceGradientAngleAdjustmentDirection.swift": (
        "BrowserSpaceGradientAngleAdjustmentDirection"
    ),
}

SHARED_SUPPORT_PRIMARY_OWNERS = {
    SUPPORT_ROOT / "BrowserSpaceBrandingControlPolicy.swift": (
        "BrowserSpaceBrandingControlPolicy"
    ),
    SUPPORT_ROOT / "BrowserSpaceHeraldicTerm.swift": "BrowserSpaceHeraldicTerm",
    PREVIEW_FIXTURE: "BrowserSpaceBrandingPreviewFixture",
}

HERALDIC_CONFORMANCE_OWNERS = {
    SUPPORT_ROOT
    / "BrowserSpaceBannerPattern+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceBannerPattern"
    ),
    SUPPORT_ROOT / "BrowserSpaceIconStyle+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceIconStyle"
    ),
    SUPPORT_ROOT
    / "BrowserSpaceCrestBackplate+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceCrestBackplate"
    ),
    SUPPORT_ROOT / "BrowserSpaceCrestTrim+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceCrestTrim"
    ),
    SUPPORT_ROOT / "BrowserSpaceCrestSymbol+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceCrestSymbol"
    ),
    SUPPORT_ROOT
    / "BrowserSpaceCrestFieldDivision+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceCrestFieldDivision"
    ),
    SUPPORT_ROOT
    / "BrowserSpaceCrestOrdinary+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceCrestOrdinary"
    ),
    SUPPORT_ROOT
    / "BrowserSpaceCrestChargeLayout+BrowserSpaceHeraldicTerm.swift": (
        "BrowserSpaceCrestChargeLayout"
    ),
}

SHARED_PRESENTATION_EXTENSION_OWNERS = {
    SUPPORT_ROOT / "BrowserSpaceBrandColor+Presentation.swift": (
        "BrowserSpaceBrandColor"
    ),
    SUPPORT_ROOT / "BrowserSpaceBrandColorRole+Presentation.swift": (
        "BrowserSpaceBrandColorRole"
    ),
    SUPPORT_ROOT / "BrowserSpaceHeraldicTerm+Localization.swift": (
        "BrowserSpaceHeraldicTerm"
    ),
    SUPPORT_ROOT / "BrowserSpaceThemeMode+Presentation.swift": (
        "BrowserSpaceThemeMode"
    ),
}

COMPONENT_SUPPORT_EXTENSION_OWNERS = {
    VISUAL_ROOT / "Support/BrowserSpaceCrestOrdinary+Rendering.swift": (
        "BrowserSpaceCrestOrdinary"
    ),
}

PRIMARY_DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z0-9_() ,.]+\n)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect) )*"
    r"(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z0-9_]+)",
    flags=re.MULTILINE,
)
EXTENSION_PATTERN = re.compile(
    r"^\s*(?:(?:public|internal|private|fileprivate|package)\s+)*"
    r"extension\s+([A-Za-z0-9_]+)\b",
    flags=re.MULTILINE,
)
PREVIEW_PATTERN = re.compile(r"#Preview\b[^{]*\{")
NONDETERMINISTIC_PREVIEW_PATTERNS = {
    "UUID()": re.compile(r"\bUUID\s*\(\s*\)"),
    "Date()": re.compile(r"\bDate\s*\(\s*\)"),
    "Date.now": re.compile(r"\bDate\s*\.\s*now\b"),
    "random value": re.compile(
        r"(?:\brandom\s*\(|\.\s*random\s*\(|"
        r"\.\s*(?:randomElement|shuffled)\s*\()"
    ),
}
LIVE_PREVIEW_PATTERNS = {
    "disk-backed data": re.compile(
        r"\b(?:Data|NSData|NSImage|String|UIImage)\s*\(\s*"
        r"contentsOf(?:File)?\s*:"
    ),
    "UserDefaults": re.compile(r"\bUserDefaults\b"),
    "FileManager": re.compile(r"\bFileManager\b"),
    "FileHandle": re.compile(r"\bFileHandle\b"),
    "URLSession": re.compile(r"\bURLSession\w*\b"),
    "WebKit": re.compile(r"\b(?:WKWebView|WKWebsiteDataStore)\b"),
    "CloudKit": re.compile(r"\b(?:CKContainer|CKDatabase)\b"),
    "Keychain": re.compile(
        r"\b(?:SecItem\w*|SecurityBrowserSafeStorage|"
        r"KeychainCredentialVault)\b"
    ),
    "production browser graph": re.compile(
        r"\b(?:BrowserStore\s*\.\s*production|"
        r"BrowserWebsiteDataStore\s*\.\s*persistent)\b"
    ),
}


def preview_sections(source: str) -> list[str]:
    """Return each preview macro's source through the next preview macro."""
    matches = list(PREVIEW_PATTERN.finditer(source))
    return [
        source[match.start() : matches[index + 1].start()]
        if index + 1 < len(matches)
        else source[match.start() :]
        for index, match in enumerate(matches)
    ]


class BrowserSpaceBrandingViewStructureTests(unittest.TestCase):
    def test_shared_branding_family_uses_the_vertical_feature_topology(self) -> None:
        expected_sources = set(
            CURRENT_VISUAL_OWNERS
            | EXTRACTED_VISUAL_OWNERS
            | COMPONENT_MODEL_OWNERS
            | PRESENTATION_MODEL_OWNERS
            | SHARED_SUPPORT_PRIMARY_OWNERS
            | HERALDIC_CONFORMANCE_OWNERS
            | SHARED_PRESENTATION_EXTENSION_OWNERS
            | COMPONENT_SUPPORT_EXTENSION_OWNERS
        )
        actual_sources = {
            path
            for root in (VISUAL_ROOT, PRESENTATION_MODELS_ROOT, SUPPORT_ROOT)
            for path in root.rglob("*.swift")
        }
        if PREVIEW_FIXTURE.is_file():
            actual_sources.add(PREVIEW_FIXTURE)

        self.assertEqual(actual_sources, expected_sources)
        self.assertFalse(
            (SHARED_SPACES_ROOT / "BrowserSpaceBrandingView").exists()
        )
        self.assertFalse(
            (SHARED_SPACES_ROOT / "BrowserSpaceBrandingView.swift").exists()
        )
        self.assertFalse(
            any(
                SHARED_SPACES_ROOT.rglob(
                    "BrowserSpaceBrandingViewPreviews.swift"
                )
            )
        )

    def test_every_branding_source_has_one_matching_file_scope_owner(self) -> None:
        shared_primary_owners = (
            CURRENT_VISUAL_OWNERS
            | EXTRACTED_VISUAL_OWNERS
            | COMPONENT_MODEL_OWNERS
            | PRESENTATION_MODEL_OWNERS
            | SHARED_SUPPORT_PRIMARY_OWNERS
        )
        for path, owner in shared_primary_owners.items():
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(path.stem, owner)
                source = path.read_text()
                self.assertEqual(PRIMARY_DECLARATION_PATTERN.findall(source), [owner])
                self.assertEqual(EXTENSION_PATTERN.findall(source), [])

        shared_extension_owners = (
            HERALDIC_CONFORMANCE_OWNERS
            | SHARED_PRESENTATION_EXTENSION_OWNERS
            | COMPONENT_SUPPORT_EXTENSION_OWNERS
        )
        for path, owner in shared_extension_owners.items():
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(path.stem.split("+", maxsplit=1)[0], owner)
                source = path.read_text()
                self.assertEqual(PRIMARY_DECLARATION_PATTERN.findall(source), [])
                self.assertEqual(EXTENSION_PATTERN.findall(source), [owner])

    def test_heraldic_conformances_use_the_protocol_named_file_suffix(self) -> None:
        self.assertEqual(len(HERALDIC_CONFORMANCE_OWNERS), 8)
        for path, owner in HERALDIC_CONFORMANCE_OWNERS.items():
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(
                    path.name,
                    f"{owner}+BrowserSpaceHeraldicTerm.swift",
                )
                source = path.read_text()
                self.assertRegex(
                    source,
                    rf"extension\s+{re.escape(owner)}\s*:\s*"
                    r"BrowserSpaceHeraldicTerm\b",
                )

        self.assertEqual(list(SUPPORT_ROOT.glob("*+HeraldicTerm.swift")), [])

    def test_every_visual_owner_has_a_direct_deterministic_colocated_preview(
        self,
    ) -> None:
        self.assertEqual(len(CURRENT_VISUAL_OWNERS), 22)
        visual_owners = CURRENT_VISUAL_OWNERS | EXTRACTED_VISUAL_OWNERS

        for path, owner in visual_owners.items():
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                previews = preview_sections(path.read_text())
                self.assertTrue(previews, f"{owner} has no colocated #Preview")
                self.assertTrue(
                    any(
                        re.search(rf"\b{re.escape(owner)}\s*\(", preview)
                        for preview in previews
                    ),
                    f"No #Preview directly invokes {owner}",
                )
                for preview in previews:
                    self._assert_preview_source_is_deterministic(preview, path)

    def test_preview_fixture_uses_fixed_values_and_no_live_dependencies(self) -> None:
        self.assertTrue(PREVIEW_FIXTURE.is_file())
        source = PREVIEW_FIXTURE.read_text()
        self.assertRegex(source, r"\bUUID\s*\(\s*uuid\s*:")
        self._assert_preview_source_is_deterministic(source, PREVIEW_FIXTURE)

    def test_ordinary_shape_is_a_real_component_instead_of_a_large_helper(
        self,
    ) -> None:
        ordinary_view = (
            VISUAL_ROOT
            / "Components/Crest/BrowserSpaceCrestOrdinaryView.swift"
        )
        ordinary_shape = (
            VISUAL_ROOT
            / "Components/Crest/BrowserSpaceCrestOrdinaryShape.swift"
        )
        self.assertTrue(ordinary_view.is_file())
        self.assertTrue(ordinary_shape.is_file())

        ordinary_view_source = ordinary_view.read_text()
        self.assertNotRegex(
            ordinary_view_source,
            r"\bvar\s+ordinaryShape\s*:\s*some\s+View\b",
        )
        self.assertRegex(
            ordinary_view_source,
            r"\bBrowserSpaceCrestOrdinaryShape\s*\(",
        )
        self.assertIn(
            "struct BrowserSpaceCrestOrdinaryShape: View",
            ordinary_shape.read_text(),
        )
        ordinary_shape_source = ordinary_shape.read_text()
        for child in (
            "BrowserSpaceCrestOrdinaryBar",
            "BrowserSpaceCrestOrdinaryChief",
            "BrowserSpaceCrestOrdinarySymbol",
        ):
            with self.subTest(child=child):
                self.assertRegex(
                    ordinary_shape_source,
                    rf"\b{child}\s*\(",
                )

    def test_shared_branding_sources_are_platform_agnostic(self) -> None:
        expected_sources = set(
            CURRENT_VISUAL_OWNERS
            | EXTRACTED_VISUAL_OWNERS
            | COMPONENT_MODEL_OWNERS
            | PRESENTATION_MODEL_OWNERS
            | SHARED_SUPPORT_PRIMARY_OWNERS
            | HERALDIC_CONFORMANCE_OWNERS
            | SHARED_PRESENTATION_EXTENSION_OWNERS
            | COMPONENT_SUPPORT_EXTENSION_OWNERS
        )
        for source_path in expected_sources:
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(source_path.is_file())
                source = source_path.read_text()
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)
                self.assertNotIn("#else", source)
                self.assertNotIn("#endif", source)

    def test_platform_rendering_and_bridges_are_platform_owned(self) -> None:
        for platform_root, platform_import in (
            ("CrestMac", "import AppKit"),
            ("CrestMobile", "import UIKit"),
        ):
            spaces_root = REPOSITORY_ROOT / platform_root / "Features/Spaces"
            primary_owners = {
                spaces_root
                / "Services/BrowserSpaceBranding/BrowserPlatformSpaceSymbolArtworkRenderer.swift": (
                    "BrowserPlatformSpaceSymbolArtworkRenderer"
                ),
                spaces_root
                / "Support/BrowserSpaceBranding/BrowserPlatformSpaceBrandingStyle.swift": (
                    "BrowserPlatformSpaceBrandingStyle"
                ),
            }
            extension_owners = {
                spaces_root
                / "Support/BrowserSpaceBranding/BrowserSpaceBrandColor+PlatformColor.swift": (
                    "BrowserSpaceBrandColor"
                ),
            }
            expected_sources = set(primary_owners | extension_owners)
            actual_sources = {
                path
                for root in (
                    spaces_root / "Services/BrowserSpaceBranding",
                    spaces_root / "Support/BrowserSpaceBranding",
                )
                for path in root.rglob("*.swift")
            }

            with self.subTest(platform_root=platform_root, contract="topology"):
                self.assertEqual(actual_sources, expected_sources)
                self.assertFalse(
                    (spaces_root / "BrowserSpaceBrandingView").exists()
                )

            for path, owner in primary_owners.items():
                with self.subTest(
                    platform_root=platform_root,
                    path=path.relative_to(REPOSITORY_ROOT),
                ):
                    self.assertTrue(path.is_file())
                    source = path.read_text()
                    self.assertIn(platform_import, source)
                    self.assertEqual(path.stem, owner)
                    self.assertEqual(
                        PRIMARY_DECLARATION_PATTERN.findall(source),
                        [owner],
                    )
                    self.assertEqual(EXTENSION_PATTERN.findall(source), [])

            for path, owner in extension_owners.items():
                with self.subTest(
                    platform_root=platform_root,
                    path=path.relative_to(REPOSITORY_ROOT),
                ):
                    self.assertTrue(path.is_file())
                    source = path.read_text()
                    self.assertIn(platform_import, source)
                    self.assertEqual(
                        PRIMARY_DECLARATION_PATTERN.findall(source),
                        [],
                    )
                    self.assertEqual(EXTENSION_PATTERN.findall(source), [owner])

    def test_existing_rendering_structure_guards_follow_the_new_paths(self) -> None:
        banner = (VISUAL_ROOT / "BrowserSpaceBannerBackground.swift").read_text()
        self.assertIn("struct BrowserSpaceBannerBackground: View", banner)
        self.assertLessEqual(len(banner.splitlines()), 100)

        artwork = (
            VISUAL_ROOT
            / "Components/Identity/BrowserSpaceSymbolArtwork.swift"
        ).read_text()
        self.assertIn("@State private var renderedArtwork", artwork)
        self.assertIn(".task(id: identity)", artwork)
        self.assertNotIn("private var renderedImage", artwork)

        crest_field = (
            VISUAL_ROOT / "Components/Crest/BrowserSpaceCrestField.swift"
        ).read_text()
        self.assertNotIn("GeometryReader", crest_field)

    def _assert_preview_source_is_deterministic(
        self,
        source: str,
        path: pathlib.Path,
    ) -> None:
        for dependency, pattern in (
            NONDETERMINISTIC_PREVIEW_PATTERNS | LIVE_PREVIEW_PATTERNS
        ).items():
            with self.subTest(
                path=path.relative_to(REPOSITORY_ROOT),
                dependency=dependency,
            ):
                self.assertNotRegex(source, pattern)


if __name__ == "__main__":
    unittest.main()
