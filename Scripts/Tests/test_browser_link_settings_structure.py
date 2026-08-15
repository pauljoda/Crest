#!/usr/bin/env python3
"""Vertical structure and safety seams for Browser Link Settings."""

from __future__ import annotations

from pathlib import Path
import re
import runpy
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SHARED_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Settings/BrowserLinkSettingsPane"
)
MAC_EDITOR_ROOT = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Settings/BrowserPlatformLinkRouteEditor"
)
MOBILE_EDITOR_ROOT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Settings/BrowserPlatformLinkRouteEditor"
)
MAC_GUIDANCE_ROOT = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Settings/BrowserPlatformLinkSettingsGuidance"
)
MOBILE_GUIDANCE_ROOT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Settings/BrowserPlatformLinkSettingsGuidance"
)
APPLICATION_UPDATE = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserLinkPreferences/Models/BrowserLinkRouteFieldUpdate.swift"
)
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

SHARED_OWNERS = {
    "BrowserLinkSettingsPane.swift": "BrowserLinkSettingsPane",
    "Components/BrowserLinkSettingsContent.swift": "BrowserLinkSettingsContent",
    "Components/BrowserExternalLinkDestinationSection.swift": (
        "BrowserExternalLinkDestinationSection"
    ),
    "Components/BrowserLinkRoutingSection.swift": "BrowserLinkRoutingSection",
    "Components/BrowserPeekSettingsSection.swift": "BrowserPeekSettingsSection",
    "Components/BrowserQuickWindowSettingsSection.swift": (
        "BrowserQuickWindowSettingsSection"
    ),
    "Models/BrowserLinkSettingsGuidanceKind.swift": (
        "BrowserLinkSettingsGuidanceKind"
    ),
    "Support/BrowserLinkSettingsPreviewAuthenticator.swift": (
        "BrowserLinkSettingsPreviewAuthenticator"
    ),
    "Support/BrowserLinkSettingsPreviewFixture.swift": (
        "BrowserLinkSettingsPreviewFixture"
    ),
    "Support/BrowserLinkSettingsSpacePolicy.swift": (
        "BrowserLinkSettingsSpacePolicy"
    ),
}

EDITOR_OWNERS = {
    "BrowserPlatformLinkRouteEditor.swift": (
        "BrowserPlatformLinkRouteEditor"
    ),
    "Components/BrowserPlatformLinkRouteEditorContent.swift": (
        "BrowserPlatformLinkRouteEditorContent"
    ),
    "Support/BrowserPlatformLinkRouteLayout.swift": (
        "BrowserPlatformLinkRouteLayout"
    ),
}

GUIDANCE_OWNERS = {
    "BrowserPlatformLinkSettingsGuidance.swift": (
        "BrowserPlatformLinkSettingsGuidance"
    ),
}

VISUAL_SHARED = {
    path: owner
    for path, owner in SHARED_OWNERS.items()
    if path == "BrowserLinkSettingsPane.swift" or path.startswith("Components/")
}
VISUAL_EDITOR = {
    path: owner
    for path, owner in EDITOR_OWNERS.items()
    if path == "BrowserPlatformLinkRouteEditor.swift"
    or path.startswith("Components/")
}

FORBIDDEN_PREVIEW_PATTERNS = {
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


class BrowserLinkSettingsStructureTests(unittest.TestCase):
    def source(self, root: Path, relative_path: str) -> str:
        path = root / relative_path
        self.assertTrue(path.is_file(), str(path))
        return path.read_text()

    def test_exact_vertical_topology_and_old_paths_are_absent(self) -> None:
        self.assertEqual(
            {
                str(path.relative_to(SHARED_ROOT))
                for path in SHARED_ROOT.rglob("*.swift")
            },
            set(SHARED_OWNERS),
        )
        for root in (MAC_EDITOR_ROOT, MOBILE_EDITOR_ROOT):
            self.assertEqual(
                {
                    str(path.relative_to(root))
                    for path in root.rglob("*.swift")
                },
                set(EDITOR_OWNERS),
            )
        for root in (MAC_GUIDANCE_ROOT, MOBILE_GUIDANCE_ROOT):
            self.assertEqual(
                {
                    str(path.relative_to(root))
                    for path in root.rglob("*.swift")
                },
                set(GUIDANCE_OWNERS),
            )

        for obsolete in (
            REPOSITORY_ROOT
            / "CrestShared/Features/Settings/BrowserLinkSettingsPane.swift",
            SHARED_ROOT / "Previews",
            REPOSITORY_ROOT / "CrestMac/Features/Settings/Platform/Links",
            REPOSITORY_ROOT / "CrestMobile/Features/Settings/Platform/Links",
            REPOSITORY_ROOT
            / "CrestMac/Features/Settings/BrowserLinkSettingsPane",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Settings/BrowserLinkSettingsPane",
        ):
            self.assertFalse(obsolete.exists(), str(obsolete))

    def test_every_source_has_one_matching_file_scope_declaration(self) -> None:
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_declarations = VERTICAL_GUARD["_top_level_global_content"]
        all_sources = [
            (SHARED_ROOT, relative_path, owner)
            for relative_path, owner in SHARED_OWNERS.items()
        ]
        for root in (MAC_EDITOR_ROOT, MOBILE_EDITOR_ROOT):
            all_sources.extend(
                (root, relative_path, owner)
                for relative_path, owner in EDITOR_OWNERS.items()
            )
        for root in (MAC_GUIDANCE_ROOT, MOBILE_GUIDANCE_ROOT):
            all_sources.extend(
                (root, relative_path, owner)
                for relative_path, owner in GUIDANCE_OWNERS.items()
            )
        all_sources.append(
            (
                APPLICATION_UPDATE.parent,
                APPLICATION_UPDATE.name,
                "BrowserLinkRouteFieldUpdate",
            )
        )

        for root, relative_path, owner in all_sources:
            source = self.source(root, relative_path)
            primaries = primary_declarations(source)
            with self.subTest(path=str(root / relative_path)):
                self.assertEqual(len(primaries), 1)
                self.assertEqual(primaries[0].name, owner)
                self.assertEqual(extension_declarations(source), [])
                self.assertEqual(global_declarations(source), [])
                self.assertEqual(Path(relative_path).stem, owner)

    def test_root_is_a_small_injectable_shell_composing_real_content(self) -> None:
        root = self.source(SHARED_ROOT, "BrowserLinkSettingsPane.swift")
        self.assertIn("BrowserLinkSettingsContent(", root)
        self.assertIn("init(", root)
        self.assertIn("links: BrowserLinkPreferenceStore", root)
        self.assertRegex(
            root,
            r"links:\s*BrowserLinkPreferenceStore\s*=\s*\.shared",
        )
        self.assertNotIn("BrowserExternalLinkDestinationSection(", root)
        self.assertNotIn("BrowserLinkRoutingSection(", root)
        self.assertNotRegex(root, r"private\s+(?:var|func)\s+\w+[^\n]*some\s+View")

    def test_route_edits_are_field_level_and_uuid_scoped(self) -> None:
        update = APPLICATION_UPDATE.read_text()
        store = (
            REPOSITORY_ROOT
            / "CrestShared/Application/BrowserLinkPreferences/BrowserLinkPreferenceStore.swift"
        ).read_text()
        section = self.source(
            SHARED_ROOT,
            "Components/BrowserLinkRoutingSection.swift",
        )
        for case_name in (
            "isEnabled(Bool)",
            "match(BrowserLinkRouteMatch)",
            "pattern(String)",
            "destinationSpaceID(SpaceID)",
        ):
            self.assertIn(case_name, update)
        self.assertIn("firstIndex(where: { $0.id == id })", store)
        self.assertIn("field.apply(to: &preferences.routes[index])", store)
        self.assertIn("updateRoute(route.id, field)", section)
        self.assertNotIn("update: links.updateRoute", section)

        for root in (MAC_EDITOR_ROOT, MOBILE_EDITOR_ROOT):
            for relative_path in (
                "BrowserPlatformLinkRouteEditor.swift",
                "Components/BrowserPlatformLinkRouteEditorContent.swift",
            ):
                editor = self.source(root, relative_path)
                self.assertIn(
                    "let update: (BrowserLinkRouteFieldUpdate) -> Void",
                    editor,
                )
                self.assertNotIn("let update: (BrowserLinkRoute) -> Void", editor)

    def test_space_resolution_and_routing_exclude_unavailable_spaces(self) -> None:
        content = self.source(
            SHARED_ROOT,
            "Components/BrowserLinkSettingsContent.swift",
        )
        policy = self.source(
            SHARED_ROOT,
            "Support/BrowserLinkSettingsSpacePolicy.swift",
        )
        routing = (
            REPOSITORY_ROOT
            / "CrestShared/Domain/BrowserTransientBrowsing/ExternalLinks/BrowserLinkRoutingPolicy.swift"
        ).read_text()
        self.assertIn("browser.deletingSpaceIDs", content)
        self.assertIn("BrowserLinkSettingsSpacePolicy.resolvedExternalSpaceID", content)
        self.assertIn("unavailableSpaceIDs", policy)
        self.assertIn("unavailableSpaceIDs", routing)

        consumers = {
            "CrestMac/Features/Browser/BrowserRootView/Components/BrowserExternalLinkHandler.swift": (
                "unavailableSpaceIDs: browser.deletingSpaceIDs"
            ),
            "CrestMac/Features/QuickWindow/BrowserQuickWindowScene.swift": (
                "unavailableSpaceIDs: initialContext.browser.deletingSpaceIDs"
            ),
            "CrestMobile/App/MobileBrowserWindowScene/Models/MobileBrowserWindowSceneModel.swift": (
                "unavailableSpaceIDs: browser.deletingSpaceIDs"
            ),
        }
        for relative_path, contract in consumers.items():
            source = (REPOSITORY_ROOT / relative_path).read_text()
            self.assertIn(contract, source)

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        owners = [
            (SHARED_ROOT, path, owner)
            for path, owner in VISUAL_SHARED.items()
        ]
        for root in (MAC_EDITOR_ROOT, MOBILE_EDITOR_ROOT):
            owners.extend(
                (root, path, owner)
                for path, owner in VISUAL_EDITOR.items()
            )
        for root in (MAC_GUIDANCE_ROOT, MOBILE_GUIDANCE_ROOT):
            owners.extend(
                (root, path, owner)
                for path, owner in GUIDANCE_OWNERS.items()
            )

        for root, relative_path, owner in owners:
            source = self.source(root, relative_path)
            preview_offset = source.rfind("#Preview")
            with self.subTest(path=str(root / relative_path)):
                self.assertGreaterEqual(preview_offset, 0)
                suffix = source[preview_offset:]
                self.assertRegex(suffix, rf"\b{re.escape(owner)}\s*\(")
                for label, pattern in FORBIDDEN_PREVIEW_PATTERNS.items():
                    self.assertIsNone(pattern.search(suffix), label)

        fixture = self.source(
            SHARED_ROOT,
            "Support/BrowserLinkSettingsPreviewFixture.swift",
        )
        authenticator = self.source(
            SHARED_ROOT,
            "Support/BrowserLinkSettingsPreviewAuthenticator.swift",
        )
        combined = fixture + authenticator
        self.assertIn("InMemoryBrowserSessionPersistence()", fixture)
        self.assertIn("InMemoryCredentialVault()", fixture)
        self.assertIn("InMemoryBrowserLinkPreferencesPersistence(", fixture)
        self.assertIn("browsingMode: .privateBrowsing", fixture)
        self.assertIn("UUID(\n", fixture)
        for label, pattern in FORBIDDEN_PREVIEW_PATTERNS.items():
            self.assertIsNone(pattern.search(combined), label)

    def test_generated_project_contains_new_owners_and_no_obsolete_paths(self) -> None:
        project = (
            REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj"
        ).read_text()
        for filename in (
            "BrowserLinkSettingsContent.swift",
            "BrowserLinkSettingsPreviewAuthenticator.swift",
            "BrowserLinkSettingsPreviewFixture.swift",
            "BrowserLinkSettingsSpacePolicy.swift",
            "BrowserLinkRouteFieldUpdate.swift",
            "BrowserPlatformLinkRouteEditorContent.swift",
        ):
            self.assertIn(filename, project)
        self.assertNotIn("BrowserLinkSettingsComponentPreviews.swift", project)


if __name__ == "__main__":
    unittest.main()
