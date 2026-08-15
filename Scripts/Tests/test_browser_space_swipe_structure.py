#!/usr/bin/env python3
"""Vertical ownership and behavior contracts for Space paging and swiping."""

from __future__ import annotations

import json
from pathlib import Path
import re
import runpy
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROJECT = REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj"
DEBT = REPOSITORY_ROOT / "Config/VerticalStructureDebt.json"
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

PRIMARY_OWNERS = {
    "CrestShared/Application/BrowserStore/Navigation/BrowserSpaceSwipeDirection.swift": (
        "BrowserSpaceSwipeDirection"
    ),
    "CrestShared/Features/Chrome/Components/BrowserSpacePager/BrowserSpacePager.swift": (
        "BrowserSpacePager"
    ),
    "CrestShared/Features/Chrome/Components/BrowserSpacePager/Models/BrowserSpacePagerRecenterRequest.swift": (
        "BrowserSpacePagerRecenterRequest"
    ),
    "CrestShared/Features/Chrome/Components/BrowserSpacePager/Support/BrowserSpacePagerPolicy.swift": (
        "BrowserSpacePagerPolicy"
    ),
    "CrestShared/Features/Chrome/Components/BrowserSpaceSwipeModifier/BrowserSpaceSwipeModifier.swift": (
        "BrowserSpaceSwipeModifier"
    ),
    "CrestShared/Features/Chrome/Components/BrowserSpaceSwipeModifier/Support/BrowserSpaceSwipePolicy.swift": (
        "BrowserSpaceSwipePolicy"
    ),
    "CrestShared/Features/Sidebar/Support/BrowserSpaceContentSelectionPolicy.swift": (
        "BrowserSpaceContentSelectionPolicy"
    ),
    "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/BrowserPlatformHorizontalScrollerSuppressor.swift": (
        "BrowserPlatformHorizontalScrollerSuppressor"
    ),
    "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/Components/BrowserPlatformHorizontalScrollerObserverView.swift": (
        "BrowserPlatformHorizontalScrollerObserverView"
    ),
    "CrestMac/Features/Sidebar/Models/BrowserSidebarMouseButtonAction.swift": (
        "BrowserSidebarMouseButtonAction"
    ),
    "CrestMac/Features/Sidebar/Support/BrowserSidebarMouseButtonPolicy.swift": (
        "BrowserSidebarMouseButtonPolicy"
    ),
    "CrestMobile/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/BrowserPlatformHorizontalScrollerSuppressor.swift": (
        "BrowserPlatformHorizontalScrollerSuppressor"
    ),
}

EXTENSION_OWNERS = {
    "CrestShared/Features/Chrome/Components/BrowserSpaceSwipeModifier/Support/View+BrowserSpaceSwipeGesture.swift": (
        "View"
    ),
    "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/Support/BrowserSpacePagerPolicy+HorizontalScroller.swift": (
        "BrowserSpacePagerPolicy"
    ),
}

SHARED_FILES = {
    path
    for path in (*PRIMARY_OWNERS, *EXTENSION_OWNERS)
    if path.startswith("CrestShared/")
}

MAC_FILES = {
    path
    for path in (*PRIMARY_OWNERS, *EXTENSION_OWNERS)
    if path.startswith("CrestMac/")
}

VISUAL_OWNERS = {
    "CrestShared/Features/Chrome/Components/BrowserSpacePager/BrowserSpacePager.swift": (
        "BrowserSpacePager"
    ),
    "CrestShared/Features/Chrome/Components/BrowserSpaceSwipeModifier/BrowserSpaceSwipeModifier.swift": (
        "BrowserSpaceSwipeModifier"
    ),
    "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/BrowserPlatformHorizontalScrollerSuppressor.swift": (
        "BrowserPlatformHorizontalScrollerSuppressor"
    ),
    "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/Components/BrowserPlatformHorizontalScrollerObserverView.swift": (
        "BrowserPlatformHorizontalScrollerObserverView"
    ),
    "CrestMobile/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/BrowserPlatformHorizontalScrollerSuppressor.swift": (
        "BrowserPlatformHorizontalScrollerSuppressor"
    ),
}


class BrowserSpaceSwipeStructureTests(unittest.TestCase):
    def source(self, relative_path: str) -> str:
        return (REPOSITORY_ROOT / relative_path).read_text()

    def test_slice_uses_exact_vertical_owners(self) -> None:
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_content = VERTICAL_GUARD["_top_level_global_content"]

        for relative_path, owner in PRIMARY_OWNERS.items():
            path = REPOSITORY_ROOT / relative_path
            with self.subTest(relative_path=relative_path):
                self.assertTrue(path.is_file())
                source = path.read_text()
                self.assertEqual(
                    [declaration.name for declaration in primary_declarations(source)],
                    [owner],
                )
                self.assertEqual(extension_declarations(source), [])
                self.assertEqual(global_content(source), [])

        for relative_path, owner in EXTENSION_OWNERS.items():
            path = REPOSITORY_ROOT / relative_path
            with self.subTest(relative_path=relative_path):
                self.assertTrue(path.is_file())
                source = path.read_text()
                self.assertEqual(primary_declarations(source), [])
                extensions = extension_declarations(source)
                self.assertEqual(len(extensions), 1)
                self.assertEqual(extensions[0].target, owner)
                self.assertEqual(global_content(source), [])

        for obsolete_root in (
            "CrestShared/Features/Chrome/BrowserSpaceSwipe",
            "CrestMac/Features/Chrome/BrowserSpaceSwipe",
            "CrestMobile/Features/Chrome/BrowserSpaceSwipe",
        ):
            self.assertFalse((REPOSITORY_ROOT / obsolete_root).exists())

    def test_shared_owners_are_platform_neutral(self) -> None:
        for relative_path in SHARED_FILES:
            source = self.source(relative_path)
            with self.subTest(relative_path=relative_path):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        direct_preview_exists = VERTICAL_GUARD["_direct_preview_exists"]
        forbidden_preview_tokens = (
            "BrowserStore",
            "BrowserPagePool",
            "BrowserSession.preview",
            "UserDefaults",
            ".standard",
            "WebKit",
            "WKWeb",
            "URLSession",
            "FileManager",
            "Date(",
            "UUID(",
        )

        for relative_path, owner in VISUAL_OWNERS.items():
            source = self.source(relative_path)
            preview_suffix = source[source.index("#Preview") :]
            with self.subTest(relative_path=relative_path):
                self.assertTrue(direct_preview_exists(source, owner))
                for token in forbidden_preview_tokens:
                    self.assertNotIn(token, preview_suffix)

        pager_preview = self.source(
            "CrestShared/Features/Chrome/Components/BrowserSpacePager/BrowserSpacePager.swift"
        )
        self.assertIn("@Previewable @State var selectedSpaceID", pager_preview)
        self.assertIn("isInteractionLocked: true", pager_preview)
        self.assertIn("BrowserSpaceBrandingPreviewFixture.simpleSpace", pager_preview)
        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Features/Chrome/BrowserSpaceSwipe/Previews"
            ).exists()
        )

    def test_pager_preserves_runtime_and_scroll_identity(self) -> None:
        pager = self.source(
            "CrestShared/Features/Chrome/Components/BrowserSpacePager/BrowserSpacePager.swift"
        )

        runtime_identity = ".id(BrowserSpaceRuntimeAssignment(space: space))"
        scroll_identity = ".id(space.id)"
        self.assertIn(runtime_identity, pager)
        self.assertIn(scroll_identity, pager)
        self.assertLess(pager.index(runtime_identity), pager.index(scroll_identity))
        self.assertIn("LazyHStack(spacing: 0)", pager)
        self.assertIn("selectSpace(spaceID)", pager)
        self.assertIn("settledSpace(visibleSpaceID)", pager)

    def test_delayed_unlock_recenter_is_invalidated_by_new_input(self) -> None:
        pager = self.source(
            "CrestShared/Features/Chrome/Components/BrowserSpacePager/BrowserSpacePager.swift"
        )
        request = self.source(
            "CrestShared/Features/Chrome/Components/BrowserSpacePager/Models/BrowserSpacePagerRecenterRequest.swift"
        )

        self.assertEqual(pager.count("recenterRevision &+= 1"), 2)
        self.assertIn(".onChange(of: selectedSpaceID, initial: true)", pager)
        self.assertIn(".onChange(of: isInteractionLocked)", pager)
        self.assertIn("BrowserSpacePagerRecenterRequest(", pager)
        self.assertIn("request.isCurrent(", pager)
        self.assertIn("visibleSpaceID = request.spaceID", pager)
        for token in (
            "self.revision == revision",
            "spaceID == selectedSpaceID",
            "&& !isInteractionLocked",
        ):
            self.assertIn(token, request)

    def test_swipe_retains_drag_threshold_and_rtl_semantics(self) -> None:
        modifier = self.source(
            "CrestShared/Features/Chrome/Components/BrowserSpaceSwipeModifier/BrowserSpaceSwipeModifier.swift"
        )
        policy = self.source(
            "CrestShared/Features/Chrome/Components/BrowserSpaceSwipeModifier/Support/BrowserSpaceSwipePolicy.swift"
        )

        self.assertIn("minimumDragRecognitionDistance", modifier)
        self.assertIn("predictedEndTranslation", modifier)
        self.assertIn("static let minimumDragRecognitionDistance", policy)
        self.assertIn(
            "BrowserChromeDirectionPolicy.semanticHorizontalTranslation",
            policy,
        )
        self.assertIn("semanticTranslation < 0 ? .next : .previous", policy)

    def test_sidebar_selection_keeps_immediate_activation_and_exact_settlement_guards(
        self,
    ) -> None:
        policy = self.source(
            "CrestShared/Features/Sidebar/Support/BrowserSpaceContentSelectionPolicy.swift"
        )
        mac_sidebar = self.source("CrestMac/Features/Sidebar/BrowserSidebar.swift")
        mobile_sidebar = self.source(
            "CrestMobile/Features/Sidebar/MobileBrowserSidebar.swift"
        )

        self.assertIn("defersWebContentUntilPagerSettles = false", policy)
        self.assertIn("rootObserverDefersSpaceChanges = false", policy)
        for source in (mac_sidebar, mobile_sidebar):
            self.assertIn("BrowserSpaceRuntimeAssignment(space: space)", source)
            self.assertIn(
                "BrowserSidebarAccessPolicy.canSettlePageSelection(",
                source,
            )
            self.assertIn("pages.select(session: browser.session)", source)
            self.assertIn("pages.deactivatePagePresentation()", source)

    def test_platform_scroller_suppressors_remain_parallel_native_adapters(
        self,
    ) -> None:
        mac = self.source(
            "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/BrowserPlatformHorizontalScrollerSuppressor.swift"
        )
        observer = self.source(
            "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/Components/BrowserPlatformHorizontalScrollerObserverView.swift"
        )
        policy_extension = self.source(
            "CrestMac/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/Support/BrowserSpacePagerPolicy+HorizontalScroller.swift"
        )
        mobile = self.source(
            "CrestMobile/Features/Chrome/Components/BrowserPlatformHorizontalScrollerSuppressor/BrowserPlatformHorizontalScrollerSuppressor.swift"
        )

        self.assertIn("NSViewRepresentable", mac)
        self.assertIn("BrowserPlatformHorizontalScrollerObserverView", mac)
        self.assertIn("final class BrowserPlatformHorizontalScrollerObserverView", observer)
        self.assertIn("BrowserSpacePagerPolicy.hideHorizontalScroller", observer)
        self.assertIn("extension BrowserSpacePagerPolicy", policy_extension)
        self.assertIn("scrollView.horizontalScroller = nil", policy_extension)
        self.assertIn("Color.clear", mobile)
        self.assertIn(".allowsHitTesting(false)", mobile)

    def test_slice_has_no_repository_vertical_structure_violations(self) -> None:
        owned_paths = set(PRIMARY_OWNERS) | set(EXTENSION_OWNERS)
        violations = [
            (violation.key, violation.path, violation.detail)
            for violation in VERTICAL_GUARD["scan_repository"](REPOSITORY_ROOT)
            if violation.path in owned_paths
        ]
        self.assertEqual(violations, [])

    def test_project_contains_each_owner_in_the_correct_target(self) -> None:
        project = PROJECT.read_text()
        target_sources = {
            target: self.project_target_sources(project, target)
            for target in ("Crest", "CrestMobile")
        }

        for relative_path in SHARED_FILES:
            filename = Path(relative_path).name
            for target in target_sources:
                with self.subTest(target=target, filename=filename):
                    self.assertIn(filename, target_sources[target])

        for relative_path in MAC_FILES:
            filename = Path(relative_path).name
            with self.subTest(target="Crest", filename=filename):
                self.assertIn(filename, target_sources["Crest"])

        suppressor_filename = "BrowserPlatformHorizontalScrollerSuppressor.swift"
        self.assertIn(suppressor_filename, target_sources["Crest"])
        self.assertIn(suppressor_filename, target_sources["CrestMobile"])
        self.assertEqual(
            project.count(
                "/* BrowserPlatformHorizontalScrollerSuppressor.swift */ = "
                "{isa = PBXFileReference;"
            ),
            2,
        )
        self.assertNotIn("BrowserSpacePagerPreviews.swift", project)

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

    def test_vertical_debt_has_no_slice_entries(self) -> None:
        debt = json.loads(DEBT.read_text())
        owned_names = {
            Path(relative_path).name
            for relative_path in (*PRIMARY_OWNERS, *EXTENSION_OWNERS)
        } | {"BrowserSpaceSwipe"}
        entries = [
            (rule, violation)
            for rule, body in debt["rules"].items()
            for violation in body["violations"]
            if any(name in violation[0] for name in owned_names)
        ]
        self.assertEqual(entries, [])


if __name__ == "__main__":
    unittest.main()
