#!/usr/bin/env python3
"""Vertical ownership and deterministic preview contracts for Space selectors."""

from __future__ import annotations

import json
from pathlib import Path
import re
import runpy
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FAMILY_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/DesignSystem/Components/CrestSpaceSelector"
)
DESIGN_SYSTEM_MODIFIERS = (
    REPOSITORY_ROOT / "CrestShared/DesignSystem/Modifiers"
)
PROJECT = REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj"
DEBT = REPOSITORY_ROOT / "Config/VerticalStructureDebt.json"
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

PRIMARY_OWNERS = {
    "Components/CrestSpaceChipRail/CrestSpaceChipRail.swift": (
        "CrestSpaceChipRail"
    ),
    "Components/CrestSpaceChipRail/Components/CrestSpaceAddChipSurface.swift": (
        "CrestSpaceAddChipSurface"
    ),
    "Components/CrestSpaceChipRail/Components/CrestSpaceChipSurface.swift": (
        "CrestSpaceChipSurface"
    ),
    "Components/CrestSpaceChipRail/Models/CrestSpaceChipAddAction.swift": (
        "CrestSpaceChipAddAction"
    ),
    "Components/CrestSpaceChipRail/Models/CrestSpaceChipCommand.swift": (
        "CrestSpaceChipCommand"
    ),
    "Components/CrestSpaceChipRail/Support/CrestSpaceAddChipStyle.swift": (
        "CrestSpaceAddChipStyle"
    ),
    "Components/CrestSpaceChipRail/Support/CrestSpaceChipCommands.swift": (
        "CrestSpaceChipCommands"
    ),
    "Components/CrestSpaceChipRail/Support/CrestSpaceChipStyle.swift": (
        "CrestSpaceChipStyle"
    ),
    "Components/CrestSpaceIconPicker/CrestSpaceIconPicker.swift": (
        "CrestSpaceIconPicker"
    ),
    "Components/CrestSpaceIconPicker/Support/CrestSpaceIconPickerMetrics.swift": (
        "CrestSpaceIconPickerMetrics"
    ),
    "Components/CrestSpaceMenuPicker/CrestSpaceMenuPicker.swift": (
        "CrestSpaceMenuPicker"
    ),
    "Components/CrestSpaceMenuPicker/Support/CrestSpaceMenuLabelVisibility.swift": (
        "CrestSpaceMenuLabelVisibility"
    ),
    "Models/CrestSpaceIdentity.swift": "CrestSpaceIdentity",
    "Support/CrestSpaceChipMetrics.swift": "CrestSpaceChipMetrics",
    "Support/CrestSpaceSelectorPreviewFixture.swift": (
        "CrestSpaceSelectorPreviewFixture"
    ),
    "Support/CrestSpaceSelectorPreviewVariant.swift": (
        "CrestSpaceSelectorPreviewVariant"
    ),
}

EXTENSION_OWNERS = {
    "Components/CrestSpaceMenuPicker/Support/CrestSpaceMenuPicker+OptionalInitializer.swift": (
        "CrestSpaceMenuPicker"
    ),
    "Components/CrestSpaceMenuPicker/Support/CrestSpaceMenuPicker+RequiredInitializer.swift": (
        "CrestSpaceMenuPicker"
    ),
}

PROMOTED_PRIMARY_OWNERS = {
    "CrestOptionalAccessibilityIdentifier.swift": (
        "CrestOptionalAccessibilityIdentifier"
    ),
    "CrestOptionalAccessibilityValue.swift": "CrestOptionalAccessibilityValue",
}

PROMOTED_EXTENSION_OWNERS = {
    "View+CrestAccessibilityIdentifier.swift": "View",
    "View+CrestAccessibilityValue.swift": "View",
}

VISUAL_OWNERS = {
    "Components/CrestSpaceChipRail/CrestSpaceChipRail.swift": (
        "CrestSpaceChipRail"
    ),
    "Components/CrestSpaceChipRail/Components/CrestSpaceAddChipSurface.swift": (
        "CrestSpaceAddChipSurface"
    ),
    "Components/CrestSpaceChipRail/Components/CrestSpaceChipSurface.swift": (
        "CrestSpaceChipSurface"
    ),
    "Components/CrestSpaceChipRail/Support/CrestSpaceAddChipStyle.swift": (
        "CrestSpaceAddChipStyle"
    ),
    "Components/CrestSpaceChipRail/Support/CrestSpaceChipCommands.swift": (
        "CrestSpaceChipCommands"
    ),
    "Components/CrestSpaceChipRail/Support/CrestSpaceChipStyle.swift": (
        "CrestSpaceChipStyle"
    ),
    "Components/CrestSpaceIconPicker/CrestSpaceIconPicker.swift": (
        "CrestSpaceIconPicker"
    ),
    "Components/CrestSpaceMenuPicker/CrestSpaceMenuPicker.swift": (
        "CrestSpaceMenuPicker"
    ),
    "Components/CrestSpaceMenuPicker/Support/CrestSpaceMenuLabelVisibility.swift": (
        "CrestSpaceMenuLabelVisibility"
    ),
}

PROMOTED_VISUAL_OWNERS = {
    "CrestOptionalAccessibilityIdentifier.swift": (
        "CrestOptionalAccessibilityIdentifier"
    ),
    "CrestOptionalAccessibilityValue.swift": "CrestOptionalAccessibilityValue",
}

EXPECTED_DIRECTORIES = {
    "Components",
    "Components/CrestSpaceChipRail",
    "Components/CrestSpaceChipRail/Components",
    "Components/CrestSpaceChipRail/Models",
    "Components/CrestSpaceChipRail/Support",
    "Components/CrestSpaceIconPicker",
    "Components/CrestSpaceIconPicker/Support",
    "Components/CrestSpaceMenuPicker",
    "Components/CrestSpaceMenuPicker/Support",
    "Models",
    "Support",
}


class CrestSpaceSelectorStructureTests(unittest.TestCase):
    def source(self, relative_path: str) -> str:
        path = FAMILY_ROOT / relative_path
        self.assertTrue(path.is_file(), relative_path)
        return path.read_text()

    def promoted_source(self, relative_path: str) -> str:
        path = DESIGN_SYSTEM_MODIFIERS / relative_path
        self.assertTrue(path.is_file(), relative_path)
        return path.read_text()

    def test_family_has_exact_vertical_topology_without_aggregate_previews(self) -> None:
        expected_sources = set(PRIMARY_OWNERS) | set(EXTENSION_OWNERS)
        actual_sources = {
            path.relative_to(FAMILY_ROOT).as_posix()
            for path in FAMILY_ROOT.rglob("*.swift")
        }
        self.assertEqual(actual_sources, expected_sources)

        actual_directories = {
            path.relative_to(FAMILY_ROOT).as_posix()
            for path in FAMILY_ROOT.rglob("*")
            if path.is_dir()
        }
        self.assertEqual(actual_directories, EXPECTED_DIRECTORIES)

        for legacy_role in (
            "Extensions",
            "Metrics",
            "Modifiers",
            "Previews",
            "Styles",
        ):
            self.assertFalse((FAMILY_ROOT / legacy_role).exists())
        self.assertEqual(list(FAMILY_ROOT.rglob("*Previews.swift")), [])

    def test_every_source_has_one_matching_file_scope_declaration(self) -> None:
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_declarations = VERTICAL_GUARD["_top_level_global_content"]

        primary_paths = {
            **{
                FAMILY_ROOT / relative_path: owner
                for relative_path, owner in PRIMARY_OWNERS.items()
            },
            **{
                DESIGN_SYSTEM_MODIFIERS / relative_path: owner
                for relative_path, owner in PROMOTED_PRIMARY_OWNERS.items()
            },
        }
        extension_paths = {
            **{
                FAMILY_ROOT / relative_path: owner
                for relative_path, owner in EXTENSION_OWNERS.items()
            },
            **{
                DESIGN_SYSTEM_MODIFIERS / relative_path: owner
                for relative_path, owner in PROMOTED_EXTENSION_OWNERS.items()
            },
        }

        for source_path, owner in primary_paths.items():
            source = source_path.read_text()
            primaries = primary_declarations(source)
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual([item.name for item in primaries], [owner])
                self.assertEqual(extension_declarations(source), [])
                self.assertEqual(global_declarations(source), [])
                self.assertEqual(source_path.stem, owner)

        for source_path, owner in extension_paths.items():
            source = source_path.read_text()
            extensions = extension_declarations(source)
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(primary_declarations(source), [])
                self.assertEqual([item.target for item in extensions], [owner])
                self.assertEqual(global_declarations(source), [])
                self.assertEqual(source_path.stem.split("+", 1)[0], owner)

    def test_every_visual_owner_has_a_direct_colocated_preview(self) -> None:
        direct_preview_exists = VERTICAL_GUARD["_direct_preview_exists"]
        visual_sources = {
            **{
                FAMILY_ROOT / relative_path: owner
                for relative_path, owner in VISUAL_OWNERS.items()
            },
            **{
                DESIGN_SYSTEM_MODIFIERS / relative_path: owner
                for relative_path, owner in PROMOTED_VISUAL_OWNERS.items()
            },
        }
        self.assertEqual(len(visual_sources), 11)

        for source_path, owner in visual_sources.items():
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(
                    direct_preview_exists(source_path.read_text(), owner),
                    f"No direct #Preview invokes {owner}",
                )

    def test_preview_fixture_is_fixed_empty_and_dependency_free(self) -> None:
        fixture = self.source("Support/CrestSpaceSelectorPreviewFixture.swift")
        self.assertRegex(fixture, r"UUID\(\s*uuid:\s*\(")
        self.assertIn("folders: []", fixture)
        self.assertIn("tabs: []", fixture)
        self.assertIn("selectedTabID: nil", fixture)
        self.assertIn("accessPolicy: .deviceOwnerAuthentication", fixture)
        self.assertIn("branding: .initial(accent: accent, symbol: symbol)", fixture)
        self.assertIn("CrestSpaceSelectorPreviewVariant", fixture)

        forbidden_patterns = (
            *VERTICAL_GUARD["LIVE_PREVIEW_PATTERNS"],
            *VERTICAL_GUARD["NONDETERMINISTIC_PREVIEW_PATTERNS"],
            ("BrowserSession.preview", re.compile(r"BrowserSession\s*\.\s*preview")),
            ("URL", re.compile(r"\bURL\s*\(")),
            ("HTTP address", re.compile(r"https?://")),
            ("BrowserStore", re.compile(r"\bBrowserStore\b")),
            (
                "authentication API",
                re.compile(
                    r"\b(?:LocalAuthentication|LAContext|LAPolicy|"
                    r"evaluatePolicy|BrowserDeviceAuthenticator|"
                    r"SystemBrowserDeviceAuthenticator)\b"
                ),
            ),
        )
        for subject, pattern in forbidden_patterns:
            with self.subTest(subject=subject):
                self.assertIsNone(pattern.search(fixture))

    def test_direct_previews_render_fixed_meaningful_states(self) -> None:
        preview_sources = "\n".join(
            self.source(relative_path) for relative_path in VISUAL_OWNERS
        )
        self.assertIn("CrestSpaceSelectorPreviewFixture.identities", preview_sources)
        self.assertIn("CrestSpaceSelectorPreviewFixture.spaces", preview_sources)
        self.assertIn("@Previewable @State", preview_sources)
        self.assertIn(".deviceOwnerAuthentication", self.source(
            "Support/CrestSpaceSelectorPreviewFixture.swift"
        ))
        self.assertIn("Disabled Dark", self.source(
            "Components/CrestSpaceChipRail/CrestSpaceChipRail.swift"
        ))
        self.assertGreaterEqual(preview_sources.count(".environment(\\.displayScale, 2)"), 9)

    def test_button_style_surface_seam_forwards_exact_pressed_state_and_label(self) -> None:
        surface_contracts = (
            (
                "Components/CrestSpaceChipRail/Components/CrestSpaceAddChipSurface.swift",
                "struct CrestSpaceAddChipSurface<LabelContent: View>: View",
            ),
            (
                "Components/CrestSpaceChipRail/Components/CrestSpaceChipSurface.swift",
                "struct CrestSpaceChipSurface<LabelContent: View>: View",
            ),
        )
        for relative_path, declaration in surface_contracts:
            source = self.source(relative_path)
            with self.subTest(relative_path=relative_path):
                self.assertIn(declaration, source)
                self.assertIn("let isPressed: Bool", source)
                self.assertIn("let label: LabelContent", source)
                self.assertNotIn("ButtonStyleConfiguration", source)
                self.assertNotIn("configuration.", source)

        for relative_path in (
            "Components/CrestSpaceChipRail/Support/CrestSpaceAddChipStyle.swift",
            "Components/CrestSpaceChipRail/Support/CrestSpaceChipStyle.swift",
        ):
            source = self.source(relative_path)
            with self.subTest(relative_path=relative_path):
                self.assertIn("isPressed: configuration.isPressed", source)
                self.assertIn("label: configuration.label", source)

    def test_selector_behavior_contracts_are_preserved(self) -> None:
        rail = self.source(
            "Components/CrestSpaceChipRail/CrestSpaceChipRail.swift"
        )
        for token in (
            "ForEach(spaces)",
            "if let add",
            "selection = identity.id",
            "CrestSpaceChipCommands(commands: commands?(identity) ?? [])",
            ".crestCollectionMotion(ids: spaces.map(\\.id))",
            ".scrollIndicators(.hidden)",
        ):
            self.assertIn(token, rail)

        icon_picker = self.source(
            "Components/CrestSpaceIconPicker/CrestSpaceIconPicker.swift"
        )
        for token in (
            "if space.id != spaces.last?.id",
            "selectSpace(space.id)",
            "selectionTint ?? space.branding.primaryColor.color",
            ".contentShape(.rect)",
            ".buttonStyle(.plain)",
            "case (true, true):",
            "case (false, false):",
        ):
            self.assertIn(token, icon_picker)

        menu_picker = self.source(
            "Components/CrestSpaceMenuPicker/CrestSpaceMenuPicker.swift"
        )
        self.assertIn("Picker(label, selection: $selection)", menu_picker)
        self.assertIn(".tag(tag(identity))", menu_picker)

    def test_slice_has_no_repository_vertical_structure_violations(self) -> None:
        owned_paths = {
            path.relative_to(REPOSITORY_ROOT).as_posix()
            for path in FAMILY_ROOT.rglob("*.swift")
        } | {
            (DESIGN_SYSTEM_MODIFIERS / relative_path)
            .relative_to(REPOSITORY_ROOT)
            .as_posix()
            for relative_path in (
                *PROMOTED_PRIMARY_OWNERS,
                *PROMOTED_EXTENSION_OWNERS,
            )
        }
        violations = [
            violation.key
            for violation in VERTICAL_GUARD["scan_repository"](REPOSITORY_ROOT)
            if violation.path in owned_paths
        ]
        self.assertEqual(violations, [])

    def test_project_contains_every_shared_owner_and_no_aggregate_preview(self) -> None:
        project = PROJECT.read_text()
        filenames = {
            Path(relative_path).name
            for relative_path in (
                *PRIMARY_OWNERS,
                *EXTENSION_OWNERS,
                *PROMOTED_PRIMARY_OWNERS,
                *PROMOTED_EXTENSION_OWNERS,
            )
        }
        target_sources = {
            target: self.project_target_sources(project, target)
            for target in ("Crest", "CrestMobile")
        }
        for target, sources in target_sources.items():
            for filename in filenames:
                with self.subTest(target=target, filename=filename):
                    self.assertIn(filename, sources)
        self.assertNotIn("CrestSpaceSelectorPreviews.swift", project)

    def project_target_sources(self, project: str, target: str) -> set[str]:
        target_match = re.search(
            rf"[0-9A-F]{{24}} /\* {re.escape(target)} \*/ = \{{\n"
            r"\s+isa = PBXNativeTarget;"
            r"(?P<body>.*?)\n\t\t\};",
            project,
            re.DOTALL,
        )
        self.assertIsNotNone(target_match, target)
        target_body = target_match.group("body")
        phase_match = re.search(
            r"buildPhases = \(\s*"
            r"(?P<phase>[0-9A-F]{24}) /\* Sources \*/",
            target_body,
        )
        self.assertIsNotNone(phase_match, target)
        phase_id = phase_match.group("phase")
        phase_match = re.search(
            rf"{phase_id} /\* Sources \*/ = \{{\n"
            r"\s+isa = PBXSourcesBuildPhase;"
            r"(?P<body>.*?)\n\t\t\};",
            project,
            re.DOTALL,
        )
        self.assertIsNotNone(phase_match, target)
        return set(
            re.findall(
                r"/\* ([^*]+\.swift) in Sources \*/",
                phase_match.group("body"),
            )
        )

    def test_vertical_debt_has_no_selector_entries(self) -> None:
        debt = json.loads(DEBT.read_text())
        selector_entries = [
            (rule, violation)
            for rule, body in debt["rules"].items()
            for violation in body["violations"]
            if "CrestSpaceSelector" in violation[0]
        ]
        self.assertEqual(selector_entries, [])


if __name__ == "__main__":
    unittest.main()
