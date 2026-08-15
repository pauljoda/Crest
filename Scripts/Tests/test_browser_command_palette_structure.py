#!/usr/bin/env python3
"""Vertical structure and isolation contracts for the shared command palette."""

from __future__ import annotations

import pathlib
import re
import runpy
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
PALETTE_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Chrome/Components/BrowserCommandPalette"
)
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

PRIMARY_OWNERS = {
    "BrowserCommandPalette.swift": "BrowserCommandPalette",
    "Components/BrowserCommandPaletteCard/BrowserCommandPaletteCard.swift": (
        "BrowserCommandPaletteCard"
    ),
    "Components/BrowserCommandPaletteCard/Components/BrowserCommandPaletteSearchField.swift": (
        "BrowserCommandPaletteSearchField"
    ),
    "Components/BrowserCommandPaletteCard/Components/BrowserCommandPaletteShellMaterial.swift": (
        "BrowserCommandPaletteShellMaterial"
    ),
    "Components/BrowserCommandPaletteContent.swift": (
        "BrowserCommandPaletteContent"
    ),
    "Components/BrowserCommandPaletteOverlayTransitionModifier.swift": (
        "BrowserCommandPaletteOverlayTransitionModifier"
    ),
    "Components/BrowserCommandPalettePresentationView/BrowserCommandPalettePresentationView.swift": (
        "BrowserCommandPalettePresentationView"
    ),
    "Components/BrowserCommandPalettePresentationView/Components/BrowserCommandPaletteScrim.swift": (
        "BrowserCommandPaletteScrim"
    ),
    "Components/BrowserCommandPaletteResultList/BrowserCommandPaletteResultList.swift": (
        "BrowserCommandPaletteResultList"
    ),
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/BrowserCommandPaletteResultGroupView.swift": (
        "BrowserCommandPaletteResultGroupView"
    ),
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/BrowserCommandPaletteResultRows.swift": (
        "BrowserCommandPaletteResultRows"
    ),
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components/BrowserCommandPaletteResultRow/BrowserCommandPaletteResultRow.swift": (
        "BrowserCommandPaletteResultRow"
    ),
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components/BrowserCommandPaletteResultRow/Components/BrowserCommandPaletteIntentRow.swift": (
        "BrowserCommandPaletteIntentRow"
    ),
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components/BrowserCommandPaletteResultRow/Components/BrowserCommandPaletteRowButtonStyle.swift": (
        "BrowserCommandPaletteRowButtonStyle"
    ),
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components/BrowserCommandPaletteResultRow/Components/BrowserCommandPaletteRowIcon.swift": (
        "BrowserCommandPaletteRowIcon"
    ),
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components/BrowserCommandPaletteResultRow/Components/BrowserCommandPaletteRowTrailing.swift": (
        "BrowserCommandPaletteRowTrailing"
    ),
    "Models/BrowserCommandActionPresentation.swift": (
        "BrowserCommandActionPresentation"
    ),
    "Models/BrowserCommandPaletteCommandRegistry.swift": (
        "BrowserCommandPaletteCommandRegistry"
    ),
    "Models/BrowserCommandPaletteIndexedResult.swift": (
        "BrowserCommandPaletteIndexedResult"
    ),
    "Models/BrowserCommandPaletteInput.swift": "BrowserCommandPaletteInput",
    "Models/BrowserCommandPaletteIntentResult.swift": (
        "BrowserCommandPaletteIntentResult"
    ),
    "Models/BrowserCommandPaletteMode.swift": "BrowserCommandPaletteMode",
    "Models/BrowserCommandPaletteModel.swift": "BrowserCommandPaletteModel",
    "Models/BrowserCommandPaletteOmniboxContext.swift": (
        "BrowserCommandPaletteOmniboxContext"
    ),
    "Models/BrowserCommandPaletteOverlayTransitionState.swift": (
        "BrowserCommandPaletteOverlayTransitionState"
    ),
    "Models/BrowserCommandPalettePreparedResults.swift": (
        "BrowserCommandPalettePreparedResults"
    ),
    "Models/BrowserCommandPalettePresentation.swift": (
        "BrowserCommandPalettePresentation"
    ),
    "Models/BrowserCommandPalettePresentationIdentity.swift": (
        "BrowserCommandPalettePresentationIdentity"
    ),
    "Models/BrowserCommandPaletteQuery.swift": "BrowserCommandPaletteQuery",
    "Models/BrowserCommandPaletteResult.swift": "BrowserCommandPaletteResult",
    "Models/BrowserCommandPaletteResultGroup.swift": (
        "BrowserCommandPaletteResultGroup"
    ),
    "Models/BrowserCommandPaletteResultLimits.swift": (
        "BrowserCommandPaletteResultLimits"
    ),
    "Models/BrowserCommandPaletteSection.swift": "BrowserCommandPaletteSection",
    "Models/BrowserCommandPaletteTarget.swift": "BrowserCommandPaletteTarget",
    "Models/BrowserCommandPaletteTextMatchKind.swift": (
        "BrowserCommandPaletteTextMatchKind"
    ),
    "Services/BrowserCommandPaletteActionPolicy.swift": (
        "BrowserCommandPaletteActionPolicy"
    ),
    "Services/BrowserCommandPaletteResultGroupingPolicy.swift": (
        "BrowserCommandPaletteResultGroupingPolicy"
    ),
    "Services/BrowserCommandPaletteResultPreparation.swift": (
        "BrowserCommandPaletteResultPreparation"
    ),
    "Services/BrowserCommandPaletteResults/BrowserCommandPaletteResults.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteText/BrowserCommandPaletteText.swift": (
        "BrowserCommandPaletteText"
    ),
    "Support/BrowserCommandPaletteLayout.swift": "BrowserCommandPaletteLayout",
    "Support/BrowserCommandPaletteMaterialPolicy.swift": (
        "BrowserCommandPaletteMaterialPolicy"
    ),
    "Support/BrowserCommandPaletteMetrics.swift": (
        "BrowserCommandPaletteMetrics"
    ),
    "Support/BrowserCommandPalettePreviewFixture.swift": (
        "BrowserCommandPalettePreviewFixture"
    ),
}

EXTENSION_OWNERS = {
    "Models/BrowserCommandPaletteMode+OmniboxDisposition.swift": (
        "BrowserCommandPaletteMode"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Actions.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Commands.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+History.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Intent.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Omnibox.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+OtherSpaces.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Ranking.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Saved.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Tabs.swift": (
        "BrowserCommandPaletteResults"
    ),
    "Services/BrowserCommandPaletteText/Support/BrowserCommandPaletteText+Folding.swift": (
        "BrowserCommandPaletteText"
    ),
    "Services/BrowserCommandPaletteText/Support/BrowserCommandPaletteText+Matching.swift": (
        "BrowserCommandPaletteText"
    ),
    "Services/BrowserCommandPaletteText/Support/BrowserCommandPaletteText+Scoring.swift": (
        "BrowserCommandPaletteText"
    ),
    "Support/AnyTransition+BrowserCommandPaletteOverlay.swift": "AnyTransition",
    "Support/BrowserShortcutCommand+PaletteSymbol.swift": "BrowserShortcutCommand",
    "Support/View+BrowserCommandPaletteExitCommand.swift": "View",
    "Support/View+BrowserCommandPaletteHoverSelection.swift": "View",
    "Support/View+BrowserCommandPaletteMorph.swift": "View",
}

VISUAL_OWNERS = {
    relative_path: owner
    for relative_path, owner in PRIMARY_OWNERS.items()
    if relative_path == "BrowserCommandPalette.swift"
    or relative_path.startswith("Components/")
}

EXPECTED_DIRECTORIES = {
    "Components",
    "Components/BrowserCommandPaletteCard",
    "Components/BrowserCommandPaletteCard/Components",
    "Components/BrowserCommandPalettePresentationView",
    "Components/BrowserCommandPalettePresentationView/Components",
    "Components/BrowserCommandPaletteResultList",
    "Components/BrowserCommandPaletteResultList/Components",
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView",
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components",
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows",
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components",
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components/BrowserCommandPaletteResultRow",
    "Components/BrowserCommandPaletteResultList/Components/BrowserCommandPaletteResultGroupView/Components/BrowserCommandPaletteResultRows/Components/BrowserCommandPaletteResultRow/Components",
    "Models",
    "Services",
    "Services/BrowserCommandPaletteResults",
    "Services/BrowserCommandPaletteResults/Support",
    "Services/BrowserCommandPaletteText",
    "Services/BrowserCommandPaletteText/Support",
    "Support",
}

PRIMARY_DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^\n]*\))?\s*\n)*"
    r"(?:(?:public|internal|package|private|fileprivate|open|final|indirect|"
    r"nonisolated|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_]\w*)",
    re.MULTILINE,
)
EXTENSION_PATTERN = re.compile(
    r"^(?:(?:public|internal|package|private|fileprivate)\s+)*"
    r"extension\s+([A-Za-z_]\w*)\b",
    re.MULTILINE,
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
    "UserDefaults": re.compile(r"\b(?:UserDefaults|AppStorage)\b"),
    "FileManager": re.compile(r"\bFileManager\b"),
    "FileHandle": re.compile(r"\bFileHandle\b"),
    "network": re.compile(r"\b(?:URLSession\w*|AsyncImage)\b"),
    "WebKit": re.compile(r"\b(?:WKWebView|WKWebsiteDataStore)\b"),
    "Keychain": re.compile(r"\b(?:SecItem\w*|Keychain\w*)\b"),
    "production browser graph": re.compile(
        r"\b(?:BrowserStore\s*\.\s*production|"
        r"BrowserWebsiteDataStore\s*\.\s*persistent|"
        r"BrowserSession\s*\.\s*preview)\b"
    ),
}


def preview_sections(source: str) -> list[str]:
    """Return each preview macro through the start of the next macro."""
    matches = list(PREVIEW_PATTERN.finditer(source))
    return [
        source[match.start() : matches[index + 1].start()]
        if index + 1 < len(matches)
        else source[match.start() :]
        for index, match in enumerate(matches)
    ]


def without_whitespace(source: str) -> str:
    return re.sub(r"\s+", "", source)


class BrowserCommandPaletteStructureTests(unittest.TestCase):
    def test_palette_family_has_the_exact_vertical_component_topology(self) -> None:
        expected_sources = set(PRIMARY_OWNERS) | set(EXTENSION_OWNERS)
        actual_sources = {
            str(path.relative_to(PALETTE_ROOT))
            for path in PALETTE_ROOT.rglob("*.swift")
        }
        self.assertEqual(actual_sources, expected_sources)

        actual_directories = {
            str(path.relative_to(PALETTE_ROOT))
            for path in PALETTE_ROOT.rglob("*")
            if path.is_dir()
        }
        self.assertEqual(actual_directories, EXPECTED_DIRECTORIES)

    def test_every_source_has_one_matching_file_scope_declaration(self) -> None:
        for relative_path, owner in PRIMARY_OWNERS.items():
            source_path = PALETTE_ROOT / relative_path
            with self.subTest(relative_path=relative_path):
                self.assertTrue(source_path.is_file())
                self.assertEqual(source_path.stem, owner)
                source = source_path.read_text()
                file_scope_declarations = VERTICAL_GUARD[
                    "_primary_declarations"
                ](source)
                file_scope_extensions = VERTICAL_GUARD[
                    "_top_level_extensions"
                ](source)
                file_scope_globals = VERTICAL_GUARD[
                    "_top_level_global_content"
                ](source)
                self.assertEqual(
                    len(file_scope_declarations)
                    + len(file_scope_extensions)
                    + len(file_scope_globals),
                    1,
                )
                self.assertEqual(
                    PRIMARY_DECLARATION_PATTERN.findall(source),
                    [owner],
                )
                self.assertEqual(EXTENSION_PATTERN.findall(source), [])

        for relative_path, owner in EXTENSION_OWNERS.items():
            source_path = PALETTE_ROOT / relative_path
            with self.subTest(relative_path=relative_path):
                self.assertTrue(source_path.is_file())
                self.assertEqual(
                    source_path.stem.split("+", maxsplit=1)[0],
                    owner,
                )
                source = source_path.read_text()
                file_scope_declarations = VERTICAL_GUARD[
                    "_primary_declarations"
                ](source)
                file_scope_extensions = VERTICAL_GUARD[
                    "_top_level_extensions"
                ](source)
                file_scope_globals = VERTICAL_GUARD[
                    "_top_level_global_content"
                ](source)
                self.assertEqual(file_scope_declarations, [])
                self.assertEqual(len(file_scope_extensions), 1)
                self.assertEqual(file_scope_globals, [])
                self.assertEqual(PRIMARY_DECLARATION_PATTERN.findall(source), [])
                self.assertEqual(EXTENSION_PATTERN.findall(source), [owner])

    def test_result_limits_and_text_match_kind_are_top_level_models(self) -> None:
        limits_path = PALETTE_ROOT / "Models/BrowserCommandPaletteResultLimits.swift"
        match_kind_path = (
            PALETTE_ROOT / "Models/BrowserCommandPaletteTextMatchKind.swift"
        )
        self.assertEqual(
            PRIMARY_DECLARATION_PATTERN.findall(limits_path.read_text()),
            ["BrowserCommandPaletteResultLimits"],
        )
        self.assertEqual(
            PRIMARY_DECLARATION_PATTERN.findall(match_kind_path.read_text()),
            ["BrowserCommandPaletteTextMatchKind"],
        )

        results = (
            PALETTE_ROOT
            / "Services/BrowserCommandPaletteResults/BrowserCommandPaletteResults.swift"
        ).read_text()
        text = (
            PALETTE_ROOT
            / "Services/BrowserCommandPaletteText/BrowserCommandPaletteText.swift"
        ).read_text()
        self.assertNotRegex(results, r"\benum\s+Limits\b")
        self.assertNotRegex(text, r"\benum\s+MatchKind\b")
        self.assertIn("BrowserCommandPaletteResultLimits", results)
        matching = (
            PALETTE_ROOT
            / "Services/BrowserCommandPaletteText/Support/BrowserCommandPaletteText+Matching.swift"
        ).read_text()
        self.assertIn("BrowserCommandPaletteTextMatchKind", matching)

    def test_action_policy_requires_exact_unlocked_source_and_target(self) -> None:
        policy = without_whitespace(
            (
                PALETTE_ROOT
                / "Services/BrowserCommandPaletteActionPolicy.swift"
            ).read_text()
        )

        for contract in (
            "staticfuncisSourceAvailable(_source:BrowserTabRuntimeAssignment",
            "staticfunctarget(_target:BrowserTabRuntimeAssignment,fromsource:BrowserTabRuntimeAssignment",
            "staticfuncavailableOtherSpaces(fromsource:BrowserTabRuntimeAssignment",
            "browser.session.selectedSpaceID==source.spaceID",
            "BrowserSpaceRuntimeAssignment(spaceID:source.spaceID,profileID:source.profileID)",
            "space.selectedTabID==source.tabID",
            "space.tabs.first(where:{$0.id==source.tabID})",
            "BrowserSpaceRuntimeAssignment(spaceID:target.spaceID,profileID:target.profileID)",
            "space.tabs.first(where:{$0.id==target.tabID})",
            "space.id!=source.spaceID",
            "BrowserSpaceRuntimeAssignment(space:space)",
        ):
            with self.subTest(contract=contract):
                self.assertIn(contract, policy)

        self.assertGreaterEqual(
            policy.count("!accessController.isLocked(space)"),
            3,
        )
        self.assertGreaterEqual(
            policy.count(
                "selectedSource(matching:source,in:browser,accessController:accessController)"
            ),
            3,
        )

        model = without_whitespace(
            (PALETTE_ROOT / "Models/BrowserCommandPaletteModel.swift").read_text()
        )
        for contract in (
            "BrowserTabRuntimeAssignment(tabID:selectedTabID,spaceID:space.id,profileID:space.profile.id)",
            "isSourceAvailableAction(sourceAssignment)",
            "selectTabAction(sourceAssignment,target)",
            "selectTabInSpaceAction?(sourceAssignment,target)",
            "openURLAction(sourceAssignment,url)",
        ):
            with self.subTest(contract=contract):
                self.assertIn(contract, model)

        for relative_path in (
            "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+Tabs.swift",
            "Services/BrowserCommandPaletteResults/Support/BrowserCommandPaletteResults+OtherSpaces.swift",
        ):
            target_builder = without_whitespace(
                (PALETTE_ROOT / relative_path).read_text()
            )
            with self.subTest(relative_path=relative_path):
                self.assertIn(
                    "BrowserTabRuntimeAssignment(tabID:tab.id,spaceID:space.id,profileID:space.profile.id)",
                    target_builder,
                )

        for platform_model in (
            REPOSITORY_ROOT
            / "CrestMac/Features/Browser/BrowserRootView/Models/BrowserRootModel/BrowserRootModel+CommandPalette.swift",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Browser/MobileBrowserRootView/Models/MobileBrowserRootModel/MobileBrowserRootModel+CommandPalette.swift",
        ):
            source = platform_model.read_text()
            with self.subTest(platform_model=platform_model):
                self.assertIn(
                    "BrowserCommandPaletteActionPolicy.availableOtherSpaces",
                    source,
                )
                self.assertIn(
                    "BrowserCommandPaletteActionPolicy.isSourceAvailable",
                    source,
                )
                self.assertIn(
                    "BrowserCommandPaletteActionPolicy.target",
                    source,
                )

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        self.assertEqual(len(VISUAL_OWNERS), 16)
        for relative_path, owner in VISUAL_OWNERS.items():
            source_path = PALETTE_ROOT / relative_path
            previews = preview_sections(source_path.read_text())
            with self.subTest(relative_path=relative_path):
                self.assertTrue(previews, f"{owner} has no colocated #Preview")
                self.assertTrue(
                    any(
                        re.search(
                            rf"\b{re.escape(owner)}\s*(?:<[^>]+>)?\s*\(",
                            preview,
                        )
                        for preview in previews
                    ),
                    f"No #Preview directly invokes {owner}",
                )
                for preview in previews:
                    self._assert_preview_is_deterministic(preview, source_path)

    def test_preview_fixture_is_fixed_non_http_and_favicon_complete(self) -> None:
        fixture_path = (
            PALETTE_ROOT / "Support/BrowserCommandPalettePreviewFixture.swift"
        )
        fixture = fixture_path.read_text()

        self.assertRegex(fixture, r"\bUUID\s*\(\s*uuid\s*:")
        self.assertIn("Date(timeIntervalSinceReferenceDate: offset)", fixture)
        self.assertIn('with: "crest-preview://"', fixture)
        self.assertNotRegex(
            fixture,
            r"URL\s*\(\s*string\s*:\s*\"https?://",
        )
        self.assertIn("private static let faviconData = Data([", fixture)
        self.assertRegex(
            fixture,
            r"faviconData\s*=\s*Data\s*\(\s*\[\s*0x89\s*,\s*0x50",
        )
        tab_count = len(re.findall(r"\bBrowserTab\s*\(", fixture))
        self.assertGreater(tab_count, 0)
        self.assertEqual(
            tab_count,
            len(re.findall(r"\bfaviconData\s*:\s*faviconData\b", fixture)),
        )
        self._assert_preview_is_deterministic(fixture, fixture_path)

    def test_obsolete_paths_and_aggregate_previews_are_absent(self) -> None:
        for obsolete_path in (
            REPOSITORY_ROOT
            / "CrestShared/Features/Chrome/BrowserCommandPalette",
            REPOSITORY_ROOT
            / "CrestShared/Features/Chrome/BrowserChromeLayout/Models/BrowserCommandPaletteMode.swift",
            PALETTE_ROOT / "Previews",
            PALETTE_ROOT / "BrowserCommandPalettePreviews.swift",
            PALETTE_ROOT / "BrowserCommandPaletteResultGroupPreviews.swift",
        ):
            with self.subTest(obsolete_path=obsolete_path):
                self.assertFalse(obsolete_path.exists())

        self.assertEqual(
            list(
                REPOSITORY_ROOT.rglob("BrowserCommandPalettePreviews.swift")
            ),
            [],
        )
        self.assertEqual(
            list(
                REPOSITORY_ROOT.rglob(
                    "BrowserCommandPaletteResultGroupPreviews.swift"
                )
            ),
            [],
        )

    def test_shared_palette_is_platform_neutral_and_keeps_platform_seams(
        self,
    ) -> None:
        for source_path in PALETTE_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

        search_field = (
            PALETTE_ROOT
            / "Components/BrowserCommandPaletteCard/Components/BrowserCommandPaletteSearchField.swift"
        ).read_text()
        self.assertIn("BrowserPlatformAddressInputModifier", search_field)
        self.assertIn(".lineLimit(1)", search_field)

        exit_command = (
            PALETTE_ROOT
            / "Support/View+BrowserCommandPaletteExitCommand.swift"
        ).read_text()
        self.assertIn("BrowserPlatformPaletteExitCommandModifier", exit_command)

    def test_palette_shell_identity_retains_mode_and_exact_source(self) -> None:
        identity = (
            PALETTE_ROOT
            / "Models/BrowserCommandPalettePresentationIdentity.swift"
        ).read_text()
        for contract in (
            "let mode: BrowserCommandPaletteMode?",
            "let focusRequest: Int?",
            "let source: BrowserTabRuntimeAssignment?",
            "let otherSpaces: [BrowserSpaceRuntimeAssignment]",
        ):
            self.assertIn(contract, identity)
        self.assertEqual(
            identity.count(
                "self.otherSpaces = otherSpaces.map(BrowserSpaceRuntimeAssignment.init)"
            ),
            2,
        )

        mac_layer = without_whitespace(
            (
                REPOSITORY_ROOT
                / "CrestMac/Features/Browser/BrowserRootView/Components/CommandPalette/BrowserRootCommandPaletteLayer.swift"
            ).read_text()
        )
        mobile_layer = without_whitespace(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Features/Browser/MobileBrowserRootView/Components/MobileBrowserCommandPaletteLayer.swift"
            ).read_text()
        )
        self.assertIn(
            ".id(BrowserCommandPalettePresentationIdentity(mode:mode,source:source,otherSpaces:otherSpaces))",
            mac_layer,
        )
        self.assertIn(
            ".id(BrowserCommandPalettePresentationIdentity(mode:mode,source:sourceAssignment,otherSpaces:otherSpaces))",
            mobile_layer,
        )
        self.assertIn("model.isPaletteSourceAvailable(source)", mac_layer)
        self.assertIn("isSourceAvailable(sourceAssignment)", mobile_layer)
        self.assertIn(
            "space:BrowserCommandPalettePreviewFixture.currentSpace",
            mobile_layer,
        )
        self.assertIn(
            "selectedTabID:BrowserCommandPalettePreviewFixture.selectedTabID",
            mobile_layer,
        )
        self.assertNotIn("selectedTabID:nil", mobile_layer)

        mac_model = without_whitespace(
            (
                REPOSITORY_ROOT
                / "CrestMac/Features/Browser/BrowserRootView/Models/BrowserRootModel/BrowserRootModel+CommandPalette.swift"
            ).read_text()
        )
        for shell, source in (("mac", mac_model), ("mobile", mobile_layer)):
            with self.subTest(shell=shell):
                self.assertIn(
                    "BrowserTabRuntimeAssignment(tabID:",
                    source,
                )
                self.assertIn("spaceID:space.id", source)
                self.assertIn("profileID:space.profile.id", source)

        mac_start_page = without_whitespace(
            (
                REPOSITORY_ROOT
                / "CrestMac/Features/Browser/Components/BrowserStartPage/Components/BrowserStartPageCommandPalette.swift"
            ).read_text()
        )
        mobile_start_page = without_whitespace(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Features/Browser/MobileBrowserRootView/Components/MobileBrowserStartPageStack.swift"
            ).read_text()
        )
        self.assertIn(
            "BrowserCommandPalettePresentationIdentity(source:sourceAssignment)",
            mac_start_page,
        )
        self.assertIn(
            "BrowserCommandPalettePresentationIdentity(focusRequest:focusRequest,source:sourceAssignment)",
            mobile_start_page,
        )
        for source in (mac_start_page, mobile_start_page):
            self.assertIn("tabID:selectedTabID", source)
            self.assertIn("spaceID:space.id", source)
            self.assertIn("profileID:space.profile.id", source)

    def test_root_composes_content_and_model_preserves_async_publication(self) -> None:
        palette = (PALETTE_ROOT / "BrowserCommandPalette.swift").read_text()
        self.assertIn("@State private var model", palette)
        self.assertIn("BrowserCommandPaletteContent(", palette)
        self.assertNotIn("@FocusState", palette)
        self.assertNotIn("@ViewBuilder", palette)

        model = (PALETTE_ROOT / "Models/BrowserCommandPaletteModel.swift").read_text()
        for contract in (
            "rebuildTask?.cancel()",
            "Task.detached",
            "guard !Task.isCancelled",
            "guard query == prepared.query",
            "publishedQuery = prepared.query",
        ):
            self.assertIn(contract, model)

    def _assert_preview_is_deterministic(
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
