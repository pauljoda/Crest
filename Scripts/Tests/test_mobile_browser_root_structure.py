#!/usr/bin/env python3
"""Structural contracts for the decomposed mobile browser root family."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MOBILE_FEATURE_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Browser"
LEGACY_ROOT = MOBILE_FEATURE_ROOT / "MobileBrowserRootView.swift"
VIEW_ROOT = MOBILE_FEATURE_ROOT / "MobileBrowserRootView"
ROOT_VIEW = VIEW_ROOT / "MobileBrowserRootView.swift"
MODEL_ROOT = VIEW_ROOT / "Models/MobileBrowserRootModel"
LIFECYCLE_MODIFIER = VIEW_ROOT / "Components/MobileBrowserRootLifecycleModifier.swift"
SELECTION_ROOT = VIEW_ROOT / "Components/MobileBrowserRootSelectionObserver"
ROOT_COMPONENTS = (
    "Components/MobileBrowserRootContent/MobileBrowserRootContent.swift",
    "Components/MobileBrowserRootSurface.swift",
    "Components/MobileBrowserCommandPaletteLayer.swift",
    "Components/MobileBrowserSidebarSurface.swift",
    "Components/MobileBrowserDetailSurface.swift",
    "Components/MobileRegularBrowserLayout.swift",
    "Components/MobileRegularSideBySideLayout.swift",
    "Components/MobileRegularOverlayLayout.swift",
    "Components/MobileRegularDetailSurface.swift",
    "Components/MobileRegularUtilityFanLayer.swift",
    "Components/MobileCompactBrowserSurface.swift",
    "Components/MobileCompactPageSurface.swift",
    "Components/MobileCompactPageBackdrop.swift",
)


def declarations(source: str) -> list[str]:
    return re.findall(
        r"^(?:@[A-Za-z0-9_() ,.]+\n)*"
        r"(?:(?:public|internal|private|fileprivate) )?"
        r"(?:final )?"
        r"(?:struct|class|enum|actor|protocol|extension)\s+([A-Za-z0-9_]+)",
        source,
        flags=re.MULTILINE,
    )


class MobileBrowserRootStructureTests(unittest.TestCase):
    def test_legacy_monolith_is_replaced_by_a_named_view_family(self) -> None:
        self.assertFalse(LEGACY_ROOT.exists())
        self.assertTrue(ROOT_VIEW.is_file())
        source = ROOT_VIEW.read_text()
        self.assertEqual(declarations(source), ["MobileBrowserRootView"])
        self.assertLessEqual(len(source.splitlines()), 100)
        self.assertIn("@State private var model: MobileBrowserRootModel", source)
        self.assertIn("MobileBrowserRootContent(", source)
        self.assertIn("#Preview", source)

        for former_fragment in (
            "unlockedBrowserSurface",
            "regularBrowserLayout",
            "regularDetailLayer",
            "regularUtilityFanLayer",
            "private func sidebar",
            "private func detail",
            "private var compactPage",
        ):
            self.assertNotIn(former_fragment, source)

        for operation in (
            "pages.select(session:",
            "browser.selectSpace(",
            "browser.selectTab(",
            "pages.reconcileContentBlocking",
            "func synchronizePageMetadata",
            "func recordCompletedNavigation",
        ):
            self.assertNotIn(operation, source)

    def test_components_policies_metrics_and_modifier_are_extracted(self) -> None:
        required_files = (
            "Components/MobileBrowserWindowAtmosphere.swift",
            *ROOT_COMPONENTS,
            "Components/MobileURLCopyFeedback.swift",
            "Components/MobileCollapsedSidebarRevealControl.swift",
            "Components/MobileBrowserDetailView.swift",
            "Components/MobileCompactStartPageToolbar.swift",
            "Components/MobileCompactPageToolbar.swift",
            "Components/MobileCompactDomainChip.swift",
            "Components/MobileBrowserFindBar.swift",
            "Components/MobilePageHistoryControls.swift",
            "Components/MobileCompactIconButton.swift",
            "Components/MobileBrowserStartPage.swift",
            "Components/MobileBrowserWebView/MobileBrowserWebView.swift",
            "Components/MobileBrowserWebView/Support/MobileBrowserWebViewCoordinator.swift",
            "Components/MobileBrowserWebView/MobileBrowserWebHostView.swift",
            "Models/MobileStartPageSearchDestination.swift",
            "Models/MobileStartPageForegroundTone.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Animation.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Bindings.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+CommandPalette.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Commands.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Lifecycle.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Navigation.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+PageSynchronization.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Selection.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Sidebar.swift",
            "Models/MobileBrowserRootModel/MobileBrowserRootModel+Utilities.swift",
            "Support/MobileFullTabPresentationPolicy.swift",
            "Support/MobileRegularBrowserBackdropPolicy.swift",
            "Support/MobileBrowserViewportPolicy.swift",
            "Support/MobileBrowserRootPreferences.swift",
            "Support/MobileBrowserRootSelectionChange.swift",
            "Support/MobileCompactPageChromePolicy.swift",
            "Support/MobileStartPageSearchPolicy.swift",
            "Support/MobileStartPageAppearancePolicy.swift",
            "Support/MobileCompactDomainChipLayout.swift",
            "Support/MobileBrowserChromeLayout.swift",
            "Support/MobileBrowserRootLayout.swift",
            "Components/MobileDownloadRiskConfirmationModifier.swift",
            "Components/MobileBrowserRootLifecycleModifier.swift",
            "Models/MobileBrowserRootLockSnapshot.swift",
            "Components/MobileBrowserRootSelectionObserver/MobileBrowserRootSelectionObserver.swift",
            "Models/MobileBrowserRootSelectionSnapshot.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((VIEW_ROOT / relative_path).is_file())

        for obsolete_bucket in ("Metrics", "Modifiers", "Policies", "Previews"):
            self.assertFalse((VIEW_ROOT / obsolete_bucket).exists())

    def test_production_files_own_one_top_level_declaration(self) -> None:
        for path in VIEW_ROOT.rglob("*.swift"):
            if "Previews" in path.parts:
                continue
            with self.subTest(path=path.relative_to(VIEW_ROOT)):
                self.assertEqual(len(declarations(path.read_text())), 1)

    def test_visual_components_and_root_have_deterministic_previews(self) -> None:
        previewed_paths = (
            "MobileBrowserRootView.swift",
            *ROOT_COMPONENTS,
            "Components/MobileBrowserDetailView.swift",
            "Components/MobileBrowserFindBar.swift",
            "Components/MobileBrowserStartPage.swift",
            "Components/MobileBrowserWebView/MobileBrowserWebView.swift",
            "Components/MobileBrowserWindowAtmosphere.swift",
            "Components/MobileCollapsedSidebarRevealControl.swift",
            "Components/MobileCompactDomainChip.swift",
            "Components/MobileCompactIconButton.swift",
            "Components/MobileCompactPageToolbar.swift",
            "Components/MobileCompactStartPageToolbar.swift",
            "Components/MobilePageHistoryControls.swift",
            "Components/MobileURLCopyFeedback.swift",
            "Components/MobileBrowserRootLifecycleModifier.swift",
            "Components/MobileBrowserRootSelectionObserver/MobileBrowserRootSelectionObserver.swift",
            "Components/MobileDownloadRiskConfirmationModifier.swift",
        )
        for relative_path in previewed_paths:
            path = VIEW_ROOT / relative_path
            source = path.read_text()
            expected_type = path.stem
            with self.subTest(path=relative_path):
                self.assertIn("#Preview", source)
                self.assertRegex(
                    source,
                    rf"#Preview[\s\S]*\b{re.escape(expected_type)}\s*\(",
                )
                self.assertNotIn("UUID(uuidString:", source)
                self.assertNotIn("UserDefaults.standard", source)
                self.assertNotIn("WKWebsiteDataStore.default", source)

    def test_raw_geometry_is_confined_to_named_metrics(self) -> None:
        chip_source = (
            VIEW_ROOT / "Components/MobileCompactDomainChip.swift"
        ).read_text()
        self.assertNotRegex(chip_source, r"(?:frame|padding)\([^\n]*(?:36|44|14)")

    def test_session_runtime_projections_are_revision_driven(self) -> None:
        source = LIFECYCLE_MODIFIER.read_text()

        self.assertIn("@State private var runtimeSessionProjection", source)
        self.assertIn("model.browser.sessionRevision", source)
        self.assertNotIn("BrowserExtensionSessionState(session:", source)
        # Page residency follows the tab-to-Space map, never an extension signal.
        self.assertIn("tabRuntimeAssignments", source)
        self.assertIn("model.reconcileResidentPages()", source)
        self.assertNotIn("extensionState", source)

    def test_compact_start_page_still_clears_address_on_each_transition(self) -> None:
        source = (VIEW_ROOT / "Components/MobileBrowserStartPage.swift").read_text()
        self.assertIn(".onChange(of: usesCommandPalette, initial: true)", source)
        self.assertRegex(source, r"if !current\s*\{\s*address = \"\"")

    def test_mobile_workflows_are_split_into_named_model_extensions(self) -> None:
        model = (MODEL_ROOT / "MobileBrowserRootModel.swift").read_text()
        self.assertIn("@Observable", model)
        self.assertIn("@MainActor", model)
        self.assertIn("final class MobileBrowserRootModel", model)

        ownership = {
            "MobileBrowserRootModel+Lifecycle.swift": (
                "func prepareBrowser",
                "func reconcileContentBlocking",
            ),
            "MobileBrowserRootModel+Selection.swift": (
                "var selectionSnapshot",
                "func synchronizeSelection",
                "func synchronizeLockTransition",
            ),
            "MobileBrowserRootModel+Navigation.swift": (
                "func submitAddress",
                "func switchSpace",
            ),
            "MobileBrowserRootModel+Commands.swift": (
                "func commandContext",
                "func selectPreviousSpaceFromCommand",
            ),
            "MobileBrowserRootModel+Sidebar.swift": (
                "func toggleSidebar",
                "func commitSidebarWidth",
            ),
            "MobileBrowserRootModel+PageSynchronization.swift": (
                "func synchronizePageMetadata",
                "func recordCompletedNavigation",
            ),
        }
        for filename, operations in ownership.items():
            source = (MODEL_ROOT / filename).read_text()
            with self.subTest(filename=filename):
                self.assertEqual(declarations(source), ["MobileBrowserRootModel"])
                for operation in operations:
                    self.assertIn(operation, source)

    def test_selection_and_webkit_lifecycle_order_remains_explicit(self) -> None:
        lifecycle = (MODEL_ROOT / "MobileBrowserRootModel+Lifecycle.swift").read_text()
        self.assertNotIn("Extension", lifecycle)
        blocking_index = lifecycle.index("await pages.prepareContentBlocking")
        ready_index = lifecycle.index("hasPreparedBrowser = true")
        selection_index = lifecycle.index("synchronizeSelection()")
        self.assertLess(blocking_index, ready_index)
        self.assertLess(ready_index, selection_index)

        observer = (SELECTION_ROOT / "MobileBrowserRootSelectionObserver.swift").read_text()
        selection = (VIEW_ROOT / "Models/MobileBrowserRootSelectionSnapshot.swift").read_text()
        lock = (VIEW_ROOT / "Models/MobileBrowserRootLockSnapshot.swift").read_text()
        self.assertIn("sessionRevision", selection)
        self.assertIn("BrowserTabRuntimeAssignment", selection)
        self.assertIn("selectedProfileID", selection)
        self.assertIn("sessionRevision", lock)
        self.assertIn("MobileBrowserPresentation", lock)
        self.assertIn(".onChange(of: selection)", observer)
        self.assertIn(".onChange(of: lock, initial: true)", observer)

    def test_new_root_owners_match_their_filenames(self) -> None:
        source_paths = [
            *MODEL_ROOT.glob("*.swift"),
            LIFECYCLE_MODIFIER,
            *SELECTION_ROOT.glob("*.swift"),
            VIEW_ROOT / "Models/MobileBrowserRootLockSnapshot.swift",
            VIEW_ROOT / "Models/MobileBrowserRootSelectionSnapshot.swift",
            VIEW_ROOT / "Support/MobileBrowserRootSelectionChange.swift",
        ]
        nested_pattern = re.compile(
            r"^\s{4,}(?:private )?(?:final )?"
            r"(?:struct|class|enum|actor|protocol|extension)\s+",
            flags=re.MULTILINE,
        )
        for path in source_paths:
            source = path.read_text()
            names = declarations(source)
            expected_name = path.stem.split("+", maxsplit=1)[0]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(names, [expected_name])
                self.assertIsNone(nested_pattern.search(source))

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
                if "MobileBrowserRootView" in violation[1][0]
            ]
        )
        self.assertEqual(len(violations), 0)


if __name__ == "__main__":
    unittest.main()
