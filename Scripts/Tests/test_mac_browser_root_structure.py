#!/usr/bin/env python3
"""Structural contracts for the macOS BrowserRootView family."""

from __future__ import annotations

import json
import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
FEATURE_ROOT = REPOSITORY_ROOT / "CrestMac/Features/Browser"
FAMILY_ROOT = FEATURE_ROOT / "BrowserRootView"
ROOT_VIEW = FAMILY_ROOT / "BrowserRootView.swift"


class MacBrowserRootStructureTests(unittest.TestCase):
    def test_browser_root_family_is_decomposed_by_responsibility(self) -> None:
        required_files = (
            "Components/BrowserRootShell.swift",
            "Support/BrowserRootMetrics.swift",
            "Support/BrowserRootPreferenceKeys.swift",
            "Models/BrowserRootCommandSurfaceID.swift",
            "Models/BrowserRootModel/BrowserRootModel.swift",
            "Models/BrowserRootModel/BrowserRootModel+Animation.swift",
            "Models/BrowserRootModel/BrowserRootModel+Bindings.swift",
            "Models/BrowserRootModel/BrowserRootModel+CommandPalette.swift",
            "Models/BrowserRootModel/BrowserRootModel+Feedback.swift",
            "Models/BrowserRootModel/BrowserRootModel+Lifecycle.swift",
            "Models/BrowserRootModel/BrowserRootModel+Navigation.swift",
            "Models/BrowserRootModel/BrowserRootModel+PageSynchronization.swift",
            "Models/BrowserRootModel/BrowserRootModel+Sidebar.swift",
            "Models/BrowserRootModel/BrowserRootModel+Utilities.swift",
            "Components/BrowserRootLifecycleModifier.swift",
            "Components/BrowserRootSelectionObserver/BrowserRootSelectionObserver.swift",
            "Models/BrowserRootSelectionSnapshot.swift",
            "Components/Backdrop/BrowserRootBackdrop.swift",
            "Components/Backdrop/BrowserWindowAtmosphere.swift",
            "Components/Chrome/BrowserRootShellControls.swift",
            "Components/CommandPalette/BrowserRootCommandPaletteLayer.swift",
            "Components/Feedback/BrowserURLCopyFeedbackView.swift",
            "Components/Page/BrowserRootPageSurface.swift",
            "Components/Peek/BrowserRootPeekLayer.swift",
            "Components/Sidebar/BrowserFloatingSidebarCardBackground.swift",
            "Components/Sidebar/BrowserRootDockedSidebarLayer.swift",
            "Components/Sidebar/BrowserRootFloatingSidebarLayer.swift",
            "Components/Sidebar/BrowserRootSidebarContent.swift",
            "Components/Sidebar/CollapsedSidebarRevealControl.swift",
            "Components/Utilities/BrowserRootUtilityFanLayer/BrowserRootUtilityFanControl.swift",
            "Components/Utilities/BrowserRootUtilityFanLayer/BrowserRootUtilityFanLayer.swift",
            "Components/NativeWindowControls/BrowserNativeWindowControlsBridge.swift",
            "Components/NativeWindowControls/BrowserNativeWindowControlsHostView.swift",
            "Models/BrowserNativeWindowChromeSnapshot.swift",
            "Components/NativeWindowControls/Support/BrowserNativeWindowControlsPolicy.swift",
            "Support/BrowserRootPreviewFixture.swift",
            "Models/BrowserRootPreviewState.swift",
        )

        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((FAMILY_ROOT / relative_path).is_file())

        self.assertFalse((FEATURE_ROOT / "BrowserRootView.swift").exists())
        for obsolete_bucket in (
            "Infrastructure",
            "Metrics",
            "Modifiers",
            "Policies",
            "Previews",
        ):
            self.assertFalse((FAMILY_ROOT / obsolete_bucket).exists())

    def test_root_file_is_a_thin_model_driven_composition(self) -> None:
        source = ROOT_VIEW.read_text()
        declarations = re.findall(
            r"^(?:@[A-Za-z0-9_() ,.]+\n)*(?:(?:public|internal|private|fileprivate) )?"
            r"(?:struct|class|enum|actor|protocol|extension)\s+([A-Za-z0-9_]+)",
            source,
            flags=re.MULTILINE,
        )

        self.assertEqual(declarations, ["BrowserRootView"])
        production_source = source.split("#Preview", maxsplit=1)[0]
        self.assertLessEqual(len(production_source.splitlines()), 100)
        self.assertIn("@State private var model: BrowserRootModel", source)
        self.assertIn("BrowserRootShell(", source)
        self.assertIn("BrowserRootLifecycleModifier(", source)
        self.assertNotIn("@AppStorage", source)
        self.assertIn("persistSidebarWidth: persistSidebarWidth", source)
        for operation in (
            "func submitAddress",
            "func synchronizePageMetadata",
            "func presentFloatingSidebar",
            "func openPaletteURL",
        ):
            self.assertNotIn(operation, source)

    def test_operational_state_is_owned_by_an_observable_main_actor_model(self) -> None:
        model_root = FAMILY_ROOT / "Models/BrowserRootModel"
        source = (model_root / "BrowserRootModel.swift").read_text()

        self.assertIn("@Observable", source)
        self.assertIn("@MainActor", source)
        self.assertIn("final class BrowserRootModel", source)
        self.assertLessEqual(len(source.splitlines()), 60)

        ownership = {
            "BrowserRootModel+Sidebar.swift": (
                "func toggleSidebar",
                "func commitSidebarWidth",
            ),
            "BrowserRootModel+Navigation.swift": (
                "func submitAddress",
                "func synchronizeAfterSpaceChange",
            ),
            "BrowserRootModel+CommandPalette.swift": (
                "func selectPaletteTab",
                "func openPaletteURL",
            ),
            "BrowserRootModel+PageSynchronization.swift": (
                "func synchronizePageMetadata",
                "func recordCompletedNavigation",
            ),
            "BrowserRootModel+Lifecycle.swift": (
                "func prepareBrowser",
                "func reconcileContentBlocking",
            ),
        }
        for relative_path, operations in ownership.items():
            extension_source = (model_root / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                for operation in operations:
                    self.assertIn(operation, extension_source)

    def test_native_binding_boundaries_ignore_noop_reconciliation_writes(self) -> None:
        bindings = (
            FAMILY_ROOT
            / "Models/BrowserRootModel/BrowserRootModel+Bindings.swift"
        ).read_text()
        transparency_bridge = (
            REPOSITORY_ROOT
            / "CrestMac/Features/WindowAppearance/Components/BrowserWindowTransparencyBridge/BrowserWindowTransparencyBridge.swift"
        ).read_text()
        transparency_host = (
            REPOSITORY_ROOT
            / "CrestMac/Features/WindowAppearance/Components/BrowserWindowTransparencyBridge/Components/BrowserWindowTransparencyHostView.swift"
        ).read_text()

        for value in ("address", "isAddressEditing", "isWindowFocused"):
            self.assertIn(f"guard self.{value} !=", bindings)
        self.assertIn(
            "guard isTransparencyEnabled != oldValue else { return }",
            transparency_host,
        )
        update_body = transparency_bridge.split("func updateNSView", 1)[1].split(
            "static func dismantleNSView", 1
        )[0]
        self.assertNotIn("configureAttachedWindow()", update_body)

    def test_production_sources_have_one_top_level_declaration_and_no_nested_types(
        self,
    ) -> None:
        production_sources = [
            source_path
            for source_path in FAMILY_ROOT.rglob("*.swift")
            if "Previews" not in source_path.parts
        ]
        declaration_pattern = re.compile(
            r"^(?:@[^\n]+\n)*(?:(?:public|internal|private|fileprivate) )?"
            r"(?:final )?(?:struct|class|enum|actor|protocol|extension)\s+"
            r"([A-Za-z0-9_]+)",
            flags=re.MULTILINE,
        )
        nested_pattern = re.compile(
            r"^\s{4,}(?:private )?(?:final )?"
            r"(?:struct|class|enum|actor|protocol|extension)\s+",
            flags=re.MULTILINE,
        )

        for source_path in production_sources:
            source = source_path.read_text()
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(len(declaration_pattern.findall(source)), 1)
                self.assertIsNone(nested_pattern.search(source))
                self.assertNotRegex(
                    source,
                    r"private (?:var|func) [A-Za-z0-9_() :,]+: some View",
                )

    def test_webkit_and_selection_lifecycle_order_is_preserved(self) -> None:
        lifecycle_model = (
            FAMILY_ROOT
            / "Models/BrowserRootModel/BrowserRootModel+Lifecycle.swift"
        ).read_text()
        lifecycle_modifier = (
            FAMILY_ROOT / "Components/BrowserRootLifecycleModifier.swift"
        ).read_text()
        selection_model = (
            FAMILY_ROOT
            / "Models/BrowserRootModel/BrowserRootModel+Navigation.swift"
        ).read_text()

        restore_index = lifecycle_model.index("await pages.restoreExtensions")
        blocking_index = lifecycle_model.index("await pages.prepareContentBlocking")
        ready_index = lifecycle_model.index("hasRestoredExtensions = true")
        selection_index = lifecycle_model.index("synchronizeSelection()")
        self.assertLess(restore_index, blocking_index)
        self.assertLess(blocking_index, ready_index)
        self.assertLess(ready_index, selection_index)

        self.assertIn("BrowserRootSelectionObserver(", lifecycle_modifier)
        self.assertIn("BrowserRuntimeSessionProjection", lifecycle_modifier)
        self.assertIn("model.browser.sessionRevision", lifecycle_modifier)
        self.assertNotIn(
            "BrowserExtensionSessionState(session:",
            lifecycle_modifier,
        )
        self.assertIn("pages.deactivatePagePresentation()", selection_model)

    def test_platform_window_chrome_ownership_is_explicit(self) -> None:
        native_root = FAMILY_ROOT / "Components/NativeWindowControls"
        bridge = (native_root / "BrowserNativeWindowControlsBridge.swift").read_text()
        host = (native_root / "BrowserNativeWindowControlsHostView.swift").read_text()
        policy = (
            native_root / "Support/BrowserNativeWindowControlsPolicy.swift"
        ).read_text()

        self.assertIn("NSViewRepresentable", bridge)
        self.assertIn("final class BrowserNativeWindowControlsHostView", host)
        self.assertIn("restoreWindowChrome()", host)
        self.assertNotIn("nsView.applyBrowserChrome()", bridge)
        self.assertIn("if window.titleVisibility != .hidden", host)
        self.assertIn("guard button.isHidden != shouldHide", host)
        self.assertIn("toolbarIdentifier", policy)
        self.assertIn("buttonTypes", policy)

        for source_path in FAMILY_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

    def test_web_content_does_not_inherit_chrome_animation_transactions(self) -> None:
        page_surface = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Browser/Components/BrowserWebPageSurface/"
            "BrowserWebPageSurface.swift"
        ).read_text()

        self.assertIn("BrowserPlatformWebView(page: page)", page_surface)
        self.assertIn("transaction.animation = nil", page_surface)

    def test_visual_metrics_and_motion_are_semantically_named(self) -> None:
        metrics = (FAMILY_ROOT / "Support/BrowserRootMetrics.swift").read_text()
        shell = (FAMILY_ROOT / "Components/BrowserRootShell.swift").read_text()
        feedback_model = (
            FAMILY_ROOT
            / "Models/BrowserRootModel/BrowserRootModel+Feedback.swift"
        ).read_text()

        for metric in (
            "floatingSidebarBorderWidth",
            "utilityFanAdditionalEdgeOffset",
            "urlCopyFeedbackDuration",
            "commandPaletteZIndex",
            "peekZIndex",
        ):
            self.assertIn(f"static let {metric}", metrics)
        for motion in (
            "CrestMotion.chrome",
            "CrestMotion.floatingPane",
            "CrestMotion.pane",
        ):
            self.assertIn(motion, shell)
        self.assertIn("CrestMotion.feedbackPresentation", feedback_model)
        self.assertNotRegex(shell, r"\.(?:smooth|snappy|easeInOut|easeOut)\(")

    def test_previews_cover_major_states_with_deterministic_fixtures(self) -> None:
        fixture = (FAMILY_ROOT / "Support/BrowserRootPreviewFixture.swift").read_text()

        self.assertIn('#Preview("Browser Root — Docked"', ROOT_VIEW.read_text())
        self.assertIn(
            '#Preview("Window Atmosphere"',
            (FAMILY_ROOT / "Components/Backdrop/BrowserWindowAtmosphere.swift").read_text(),
        )
        self.assertIn(
            '#Preview("Floating Sidebar Background"',
            (
                FAMILY_ROOT
                / "Components/Sidebar/BrowserFloatingSidebarCardBackground.swift"
            ).read_text(),
        )
        self.assertIn(
            '#Preview("URL Copy Feedback"',
            (
                FAMILY_ROOT
                / "Components/Feedback/BrowserURLCopyFeedbackView.swift"
            ).read_text(),
        )

        self.assertRegex(fixture, r"UUID\s*\(\s*uuid:")
        self.assertNotIn("UUID()", fixture)
        self.assertNotIn("URL(string:", fixture)
        self.assertNotIn(".now", fixture)
        self.assertNotRegex(fixture, r"[A-Za-z0-9_\)\]\}]!")

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
                if "BrowserRootView" in violation[1][0]
                and violation[1][0].startswith("CrestMac/")
            ]
        )
        self.assertEqual(len(violations), 0)


if __name__ == "__main__":
    unittest.main()
