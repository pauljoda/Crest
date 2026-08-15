#!/usr/bin/env python3
"""Ownership contracts for Crest's portable archive and browser import stack."""

from pathlib import Path
import json
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FEATURE_ROOT = REPOSITORY_ROOT / "CrestShared/Features/DataPortability"


class DataPortabilityStructureTests(unittest.TestCase):
    def test_portable_values_and_policies_are_feature_owned(self) -> None:
        required_files = (
            "Models/BrowserPortableArchive.swift",
            "Models/PortableArchivedTab.swift",
            "Models/PortableFolder.swift",
            "Models/PortableHistoryEntry.swift",
            "Models/PortableSpace.swift",
            "Models/PortableTab.swift",
            "Models/BrowserPortableImport.swift",
            "Models/BrowserPortableImportSummary.swift",
            "Models/BrowserPortableArchiveError.swift",
            "Models/BrowserBookmarkMigrationSource.swift",
            "Models/BrowserBookmarkMigrationError.swift",
            "Models/BrowserHistoryMigrationSource.swift",
            "Models/BrowserHistoryMigrationError.swift",
            "Models/BrowserImportDestination.swift",
            "Models/BrowserImportReviewPlan.swift",
            "Models/BrowserImportSpaceCustomization.swift",
            "Models/BrowserImportSpaceReview.swift",
            "Support/Policies/ArchiveLimits.swift",
            "Support/Policies/ArchiveValidation.swift",
            "Support/Policies/BrowserBookmarkValueSanitizer.swift",
            "Services/BrowserBookmarkMigration.swift",
            "Services/History/BrowserHistoryMigration.swift",
            "Services/History/BrowserHistorySQLiteDatabase.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((FEATURE_ROOT / relative_path).is_file())

        for legacy_path in (
            "CrestShared/Domain/BrowserPortableArchive.swift",
            "CrestShared/Domain/BrowserBookmarkMigration.swift",
            "CrestShared/Domain/BrowserBookmarkSourceAdapters.swift",
            "CrestShared/Domain/BrowserNetscapeBookmarkAdapter.swift",
            "CrestShared/Domain/BrowserHistoryMigrationTypes.swift",
            "CrestShared/Domain/BrowserImportReviewPlan.swift",
            "CrestShared/Infrastructure/BrowserPortableArchiveFile.swift",
            "CrestShared/Infrastructure/BrowserHistoryMigration.swift",
        ):
            with self.subTest(legacy_path=legacy_path):
                self.assertFalse((REPOSITORY_ROOT / legacy_path).exists())

    def test_portable_models_policies_codecs_and_services_are_framework_neutral(self) -> None:
        forbidden_imports = (
            "import AppKit",
            "import SwiftUI",
            "import UIKit",
            "import UniformTypeIdentifiers",
            "import SQLite3",
        )
        violations: list[str] = []
        for folder in ("Models", "Support/Policies", "Services/Codecs"):
            root = FEATURE_ROOT / folder
            for path in root.rglob("*.swift"):
                source = path.read_text()
                for forbidden_import in forbidden_imports:
                    if forbidden_import in source:
                        violations.append(
                            f"{path.relative_to(REPOSITORY_ROOT)}: {forbidden_import}"
                        )

        self.assertEqual(
            violations,
            [],
            "Portable code must not own presentation or platform infrastructure:\n"
            + "\n".join(violations),
        )

    def test_cross_platform_file_and_sqlite_bridges_are_explicit_infrastructure(self) -> None:
        required_files = (
            "Services/Documents/BrowserPortableArchiveDocument.swift",
            "Services/Documents/BrowserBookmarkHTMLDocument.swift",
            "Services/FileIO/BrowserPortableArchiveFileIO.swift",
            "Services/FileIO/BrowserBookmarkMigrationFileIO.swift",
            "Services/FileIO/BrowserTabMigrationFileIO.swift",
            "Services/History/BrowserHistorySQLiteDatabase.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((FEATURE_ROOT / relative_path).is_file())

    def test_each_data_portability_file_has_at_most_one_top_level_type(self) -> None:
        declaration_prefixes = (
            "actor ",
            "class ",
            "enum ",
            "final class ",
            "protocol ",
            "struct ",
        )
        violations: list[str] = []
        for path in FEATURE_ROOT.rglob("*.swift"):
            declarations = [
                line.strip()
                for line in path.read_text().splitlines()
                if line == line.lstrip()
                and line.startswith(declaration_prefixes)
            ]
            if len(declarations) > 1:
                violations.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}: {declarations}"
                )

        self.assertEqual(
            violations,
            [],
            "Split top-level production types into matching files:\n"
            + "\n".join(violations),
        )

    def test_portable_archive_values_are_matching_file_scope_owners(self) -> None:
        archive_source = (FEATURE_ROOT / "Models/BrowserPortableArchive.swift").read_text()
        self.assertNotIn("extension BrowserPortableArchive", archive_source)

        for owner in (
            "PortableArchivedTab",
            "PortableFolder",
            "PortableHistoryEntry",
            "PortableSpace",
            "PortableTab",
        ):
            path = FEATURE_ROOT / f"Models/{owner}.swift"
            with self.subTest(owner=owner):
                self.assertTrue(path.is_file())
                self.assertIn(f"struct {owner}", path.read_text())

    def test_feature_uses_only_vertical_role_folders(self) -> None:
        self.assertEqual(
            sorted(path.name for path in FEATURE_ROOT.iterdir()),
            ["Components", "Models", "Services", "Support"],
        )

    def test_data_portability_section_is_a_real_component_family(self) -> None:
        family_root = FEATURE_ROOT / "Components/BrowserDataPortabilitySection"
        required_files = (
            "BrowserDataPortabilitySection.swift",
            "Components/BrowserDataPortabilityContent.swift",
            "Components/BrowserDataPortabilityDocumentPresenter.swift",
            "Components/BrowserDataPortabilityExportControls.swift",
            "Components/BrowserDataPortabilityExternalImportControls.swift",
            "Components/BrowserDataPortabilityFootnotes.swift",
            "Components/BrowserDataPortabilityMacRequirement.swift",
            "Components/BrowserDataPortabilityProgressStatus.swift",
            "Models/BrowserDataPortabilityModel.swift",
            "Models/BrowserDataPortabilityOperationMessage.swift",
            "Models/BrowserDataPortabilityOperationStatus.swift",
            "Services/BrowserDataPortabilityOperating.swift",
            "Services/LiveBrowserDataPortabilityOperations.swift",
            "Support/BrowserDataPortabilityPreviewAuthenticator.swift",
            "Support/BrowserDataPortabilityPreviewFixture.swift",
            "Support/BrowserDataPortabilityPreviewOperations.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((family_root / relative_path).is_file())

        root_source = (family_root / "BrowserDataPortabilitySection.swift").read_text()
        self.assertIn("BrowserDataPortabilityContent(", root_source)
        self.assertIn("BrowserDataPortabilityDocumentPresenter(", root_source)
        self.assertNotIn("Task {", root_source)
        self.assertNotIn("private func prepare", root_source)

    def test_section_views_have_one_matching_owner_and_direct_preview(self) -> None:
        family_root = FEATURE_ROOT / "Components/BrowserDataPortabilitySection"
        declaration = re.compile(
            r"(?m)^(?:@\w+(?:\([^\n]*\))?\s*)*(?:private\s+)?"
            r"(?:final\s+)?(?:struct|class|enum|actor|protocol|typealias)\s+(\w+)"
        )
        view_owner = re.compile(r"\bstruct\s+(\w+)\s*(?:<[^>{}]+>)?\s*:\s*View\b")
        for path in family_root.rglob("*.swift"):
            source = path.read_text()
            owners = declaration.findall(source)
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(owners, [path.stem])
            match = view_owner.search(source)
            if match:
                with self.subTest(preview=path.relative_to(REPOSITORY_ROOT)):
                    self.assertIn("#Preview", source)
                    self.assertIn(f"{match.group(1)}(", source.split("#Preview", 1)[1])

    def test_preview_graph_is_fixed_and_cannot_reach_live_data(self) -> None:
        fixture = (
            FEATURE_ROOT
            / "Components/BrowserDataPortabilitySection/Support/BrowserDataPortabilityPreviewFixture.swift"
        ).read_text()
        self.assertRegex(fixture, r"UUID\(\s+uuid: \(")
        self.assertIn("Date(timeIntervalSince1970:", fixture)
        self.assertIn("InMemoryBrowserSessionPersistence()", fixture)
        self.assertIn("BrowserDataPortabilityPreviewOperations()", fixture)
        self.assertIn("BrowserDataPortabilityPreviewAuthenticator()", fixture)
        for forbidden in (
            "UserDefaults",
            "SystemBrowserDeviceAuthenticator",
            "BrowserStore.production",
            "BrowserStore.preview",
            "FileManager",
            "URLSession",
            "Data(contentsOf:",
            "WKWebView",
            "UUID()",
            "Date.now",
            ".standard",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, fixture)

    def test_data_portability_has_no_vertical_debt(self) -> None:
        debt = json.loads(
            (REPOSITORY_ROOT / "Config/VerticalStructureDebt.json").read_text()
        )
        violations = [
            (rule, violation)
            for rule, payload in debt["rules"].items()
            for violation in payload["violations"]
            if violation[0].startswith("CrestShared/Features/DataPortability/")
        ]
        self.assertEqual(violations, [])


if __name__ == "__main__":
    unittest.main()
