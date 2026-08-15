#!/usr/bin/env python3
"""Structural contracts for the WebExtension manager UI."""

from pathlib import Path
import json
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class BrowserExtensionsViewStructureTests(unittest.TestCase):
    def test_extension_manager_uses_named_files(self) -> None:
        root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView"
        )
        required_files = (
            "BrowserExtensionsView.swift",
            "Components/BrowserExtensionAccessSection.swift",
            "Components/BrowserExtensionEmptyState.swift",
            "Components/BrowserExtensionIssueSection.swift",
            "Components/BrowserExtensionUpdateStatus.swift",
            "Components/BrowserExtensionUpdatesSection.swift",
            "Components/BrowserInstalledExtensionsSection.swift",
            "Components/BrowserManagedExtensionRow.swift",
            "Components/BrowserExtensionRow.swift",
            "Components/BrowserExtensionValueList.swift",
            "Components/SpaceExtensionScopeBanner.swift",
            "Models/BrowserExtensionOperationFailure.swift",
            "Models/BrowserExtensionPlatformActions.swift",
            "Models/BrowserExtensionSummaryPresentation.swift",
            "Models/BrowserExtensionsMetrics.swift",
            "Models/BrowserExtensionsModel.swift",
            "Components/BrowserExtensionPackageImportModifier.swift",
            "Models/BrowserExtensionRenderedIcon.swift",
            "Support/BrowserExtensionsPreviewExtensionPackageStore.swift",
            "Support/BrowserExtensionsPreviewFixture.swift",
            "Support/BrowserExtensionsPreviewUpdateApplier.swift",
            "Support/BrowserExtensionsPreviewUpdateChecker.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((root / relative_path).is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Features/Extensions/BrowserExtensionsView.swift"
            ).exists()
        )
        self.assertFalse((root / "BrowserExtensionManagementSections.swift").exists())
        self.assertFalse((root / "Modifiers").exists())
        self.assertFalse((root / "Previews").exists())

    def test_shared_extension_manager_is_platform_neutral(self) -> None:
        root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView"
        )
        for path in root.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

    def test_sizing_is_owned_by_each_platform(self) -> None:
        for platform_root in ("CrestMac", "CrestMobile"):
            with self.subTest(platform_root=platform_root):
                self.assertTrue(
                    (
                        REPOSITORY_ROOT
                        / platform_root
                        / "Features/Extensions/Components/BrowserPlatformExtensionsViewSizingModifier.swift"
                    ).is_file()
                )

    def test_async_operations_are_owned_by_observable_model(self) -> None:
        root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView"
        )
        view = (root / "BrowserExtensionsView.swift").read_text()
        model = (root / "Models/BrowserExtensionsModel.swift").read_text()

        self.assertIn("@State private var model", view)
        self.assertNotIn("loadUnpackedExtension", view)
        self.assertNotIn("setExtensionEnabled", view)
        self.assertNotIn("removeExtension", view)
        self.assertIn("@Observable", model)
        self.assertIn("loadUnpackedExtension", model)
        self.assertIn("setExtensionEnabled", model)
        self.assertIn("removeExtension", model)

    def test_shared_model_has_no_presentation_or_mac_discovery_state(self) -> None:
        model = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView/Models/BrowserExtensionsModel.swift"
        ).read_text()

        self.assertIn("import Foundation", model)
        self.assertIn("import Observation", model)
        self.assertNotIn("import SwiftUI", model)
        self.assertNotIn("Binding<", model)
        self.assertNotIn("SafariApplication", model)
        self.assertNotIn("BrowserExtensionDiscovery", model)

    def test_platform_actions_replace_shared_options_page_branch(self) -> None:
        row = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionRow.swift"
        ).read_text()

        self.assertIn("platformActions.supportsOptionsPage", row)
        self.assertIn("platformActions.openOptionsPage", row)
        self.assertNotIn("extensionControllerPool.openOptionsPage", row)
        self.assertNotIn("#if os(", row)

        for platform in ("CrestMac", "CrestMobile"):
            actions = (
                REPOSITORY_ROOT
                / platform
                / "Features/Extensions/Support/BrowserPlatformExtensionActions.swift"
            )
            with self.subTest(platform=platform):
                self.assertTrue(actions.is_file())

    def test_mobile_extension_twins_are_documented_inert_stubs(self) -> None:
        """Extensions are macOS-only, so mobile's twins must never do work.

        The shared subsystem compiles into the mobile target because it is tied
        closely to WebKit, but nothing on mobile presents or activates it. Each
        twin says so in its own header, so a later reader cannot mistake these
        for working iOS extension support.
        """
        twins = (
            "CrestMobile/Features/Extensions/Support/BrowserPlatformExtensionActions.swift",
            "CrestMobile/Features/Extensions/Components/BrowserPlatformExtensionsViewSizingModifier.swift",
            "CrestMobile/Features/Settings/Components/BrowserPlatformExtensionAddSection.swift",
        )
        for relative_path in twins:
            source = (REPOSITORY_ROOT / relative_path).read_text()
            prose = " ".join(source.replace("///", " ").split())
            with self.subTest(relative_path=relative_path):
                self.assertIn("macos-only feature", prose.lower())
                self.assertIn("Do not grow this into a working adapter", prose)
                self.assertIn("product decision first", prose)

        actions = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Extensions/Support/BrowserPlatformExtensionActions.swift"
        ).read_text()
        self.assertIn(".none", actions)
        self.assertNotIn("openOptionsPage", actions)

        add_section = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Settings/Components/BrowserPlatformExtensionAddSection.swift"
        ).read_text()
        self.assertIn("EmptyView()", add_section)
        self.assertNotIn("Button", add_section)
        self.assertNotIn("isChoosingExtension", add_section)

        sizing = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Extensions/Components/BrowserPlatformExtensionsViewSizingModifier.swift"
        ).read_text()
        self.assertNotIn(".frame(", sizing)

    def test_shared_production_files_have_one_primary_declaration(self) -> None:
        root = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView"
        )
        declaration = re.compile(
            r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
            r"(?:(?:public|internal|private|fileprivate|package|open|final|"
            r"indirect|nonisolated(?:\(unsafe\))?)\s+)*"
            r"(?:struct|enum|class|actor|protocol|extension)\s+"
            r"([A-Za-z_][A-Za-z0-9_]*)",
            re.MULTILINE,
        )
        for path in root.rglob("*.swift"):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(len(declaration.findall(path.read_text())), 1)

    def test_platform_extension_ui_uses_feature_role_folders(self) -> None:
        mac_root = REPOSITORY_ROOT / "CrestMac/Features/Extensions"
        required_mac_files = (
            "Components/BrowserExtensionDiscoveryRow.swift",
            "Components/BrowserExtensionDiscoverySection.swift",
            "Components/BrowserSafariExtensionImportModifier.swift",
            "Components/BrowserSafariWebExtensionAccessList.swift",
            "Models/BrowserExtensionDiscoveryItem.swift",
            "Models/BrowserExtensionDiscoveryModel.swift",
            "Models/BrowserExtensionDiscoverySource+Presentation.swift",
            "Models/BrowserExtensionDiscoverySource.swift",
            "Support/BrowserExtensionDiscoveryPreviewFixture.swift",
        )
        for relative_path in required_mac_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((mac_root / relative_path).is_file())

        self.assertFalse((mac_root / "BrowserExtensionsView").exists())
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Features/Extensions/BrowserExtensionsView"
            ).exists()
        )

    def test_visible_extension_views_have_direct_deterministic_previews(self) -> None:
        expected_sources = {
            "CrestShared/Features/Extensions/BrowserExtensionsView/BrowserExtensionsView.swift": "BrowserExtensionsView",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionAccessSection.swift": "BrowserExtensionAccessSection",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionEmptyState.swift": "BrowserExtensionEmptyState",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionIconView.swift": "BrowserExtensionIconView",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionIssueSection.swift": "BrowserExtensionIssueSection",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionRow.swift": "BrowserExtensionRow",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionUpdateStatus.swift": "BrowserExtensionUpdateStatus",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionUpdatesSection.swift": "BrowserExtensionUpdatesSection",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserExtensionValueList.swift": "BrowserExtensionValueList",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserInstalledExtensionsSection.swift": "BrowserInstalledExtensionsSection",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/BrowserManagedExtensionRow.swift": "BrowserManagedExtensionRow",
            "CrestShared/Features/Extensions/BrowserExtensionsView/Components/SpaceExtensionScopeBanner.swift": "SpaceExtensionScopeBanner",
            "CrestMac/Features/Extensions/Components/BrowserExtensionDiscoveryRow.swift": "BrowserExtensionDiscoveryRow",
            "CrestMac/Features/Extensions/Components/BrowserExtensionDiscoverySection.swift": "BrowserExtensionDiscoverySection",
            "CrestMac/Features/Extensions/Components/BrowserSafariWebExtensionAccessList.swift": "BrowserSafariWebExtensionAccessList",
        }
        for relative_path, expected_type in expected_sources.items():
            source = (REPOSITORY_ROOT / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertIn("#Preview", source)
                self.assertRegex(
                    source,
                    rf"#Preview[\s\S]*\b{re.escape(expected_type)}\s*\(",
                )
                self.assertNotIn("BrowserSession.preview", source)
                self.assertNotIn("BrowserExtensionControllerPool()", source)

    def test_preview_fixtures_are_isolated_and_fixed(self) -> None:
        shared_fixture = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Extensions/BrowserExtensionsView/Support/BrowserExtensionsPreviewFixture.swift"
        ).read_text()
        self.assertRegex(shared_fixture, r"UUID\s*\(\s*uuid\s*:")
        self.assertNotIn("UUID()", shared_fixture)
        self.assertNotIn("BrowserSession.preview", shared_fixture)
        self.assertIn("BrowserExtensionsPreviewExtensionPackageStore()", shared_fixture)
        self.assertIn("InMemoryBrowserExtensionRegistryPersistence()", shared_fixture)

    def test_family_has_zero_debt_and_exact_repository_total(self) -> None:
        payload = json.loads(
            (REPOSITORY_ROOT / "Config/VerticalStructureDebt.json").read_text()
        )
        violations = [
            (rule, entry)
            for rule, details in payload["rules"].items()
            for entry in details["violations"]
        ]
        self.assertFalse(
            [
                violation
                for violation in violations
                if "Features/Extensions/BrowserExtensionsView" in violation[1][0]
            ]
        )
        self.assertEqual(len(violations), 0)


if __name__ == "__main__":
    unittest.main()
