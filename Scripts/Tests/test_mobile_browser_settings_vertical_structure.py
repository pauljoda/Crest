#!/usr/bin/env python3
"""Vertical ownership contracts for the mobile Settings surface."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SETTINGS_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Settings"
FAMILY_ROOT = SETTINGS_ROOT / "MobileBrowserSettingsView"
ROOT_VIEW = SETTINGS_ROOT / "MobileBrowserSettingsView.swift"
PREVIEW_ROOT = REPOSITORY_ROOT / "CrestMobile/PreviewSupport"
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class MobileBrowserSettingsVerticalStructureTests(unittest.TestCase):
    def test_each_settings_owner_has_one_matching_file(self) -> None:
        required = {
            ROOT_VIEW: "MobileBrowserSettingsView",
            FAMILY_ROOT / "Components/MobileBrowserSettingsContent.swift":
                "MobileBrowserSettingsContent",
            FAMILY_ROOT / "Components/MobileBrowserRegularSettingsLayout.swift":
                "MobileBrowserRegularSettingsLayout",
            FAMILY_ROOT / "Components/MobileBrowserCompactSettingsLayout.swift":
                "MobileBrowserCompactSettingsLayout",
            FAMILY_ROOT / "Components/MobileBrowserSettingsDestinationList.swift":
                "MobileBrowserSettingsDestinationList",
            FAMILY_ROOT / "Components/MobileBrowserSettingsDestinationView.swift":
                "MobileBrowserSettingsDestinationView",
            FAMILY_ROOT / "Components/MobileSettingsDestinationRow.swift":
                "MobileSettingsDestinationRow",
            FAMILY_ROOT / "Components/MobileCredentialSettingsView.swift":
                "MobileCredentialSettingsView",
            FAMILY_ROOT / "Components/MobileSpaceSettingsView/MobileSpaceSettingsView.swift":
                "MobileSpaceSettingsView",
            FAMILY_ROOT / "Components/MobileSpaceSettingsView/Components/MobileSpaceSelectionSection.swift":
                "MobileSpaceSelectionSection",
            FAMILY_ROOT / "Components/MobileSpaceSettingsView/Components/MobileSpaceCustomizationSection.swift":
                "MobileSpaceCustomizationSection",
            FAMILY_ROOT / "Components/MobileSpaceSettingsView/Components/MobileSpaceCustomizationPreview.swift":
                "MobileSpaceCustomizationPreview",
            FAMILY_ROOT / "Components/MobileSpaceSettingsView/Components/MobileSpaceCustomizationControls.swift":
                "MobileSpaceCustomizationControls",
            FAMILY_ROOT / "Components/MobileSpaceSettingsView/Components/MobileSpaceBrowsingSection.swift":
                "MobileSpaceBrowsingSection",
            FAMILY_ROOT / "Components/MobileSpaceSettingsView/Components/MobilePrivateSpaceSettingsSection.swift":
                "MobilePrivateSpaceSettingsSection",
            FAMILY_ROOT / "Models/MobileSettingsDestinationFilter.swift":
                "MobileSettingsDestinationFilter",
            PREVIEW_ROOT / "MobileBrowserPreviewFixture.swift":
                "MobileBrowserPreviewFixture",
        }

        for path, owner in required.items():
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(
                    DECLARATION_PATTERN.findall(path.read_text()),
                    [owner],
                )

    def test_root_composes_content_instead_of_view_fragments(self) -> None:
        source = ROOT_VIEW.read_text()

        self.assertIn("MobileBrowserSettingsContent(", source)
        self.assertNotIn("private var destinationList: some View", source)
        self.assertNotIn("private func destinationView", source)
        self.assertNotIn("private struct ", source)
        self.assertIn("#Preview", source)
        self.assertIn(
            "MobileBrowserSettingsView(",
            source[source.index("#Preview"):],
        )

    def test_every_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        visual_files = [ROOT_VIEW]
        visual_files.extend((FAMILY_ROOT / "Components").rglob("*.swift"))

        for path in sorted(visual_files):
            source = path.read_text()
            declarations = DECLARATION_PATTERN.findall(source)
            if ": View" not in source or not declarations:
                continue
            owner = declarations[0]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("#Preview", source)
                preview = source[source.index("#Preview"):]
                self.assertIn(f"{owner}(", preview)
                self.assertNotIn("UUID()", source)
                self.assertNotIn(".now", source)
                self.assertNotIn("UserDefaults", source)
                self.assertNotIn("WKWebsiteDataStore.default", source)
                self.assertNotIn("WKContentRuleListStore.default", source)

    def test_preview_graph_is_fixed_and_in_memory(self) -> None:
        source = (
            PREVIEW_ROOT / "MobileBrowserPreviewFixture.swift"
        ).read_text()

        self.assertRegex(source, r"UUID\(\s*uuid:")
        self.assertIn("InMemoryBrowserSessionPersistence()", source)
        self.assertIn("usesEphemeralWebsiteDataStores: true", source)
        self.assertIn("ruleListStore: nil", source)
        self.assertNotIn("BrowserStore.preview()", source)
        self.assertNotIn("UserDefaults", source)
        self.assertNotIn("FileManager", source)
        self.assertNotIn("URLSession", source)
        self.assertNotIn("UUID()", source)
        self.assertNotIn(".now", source)

    def test_destination_and_space_routing_remain_identity_bound(self) -> None:
        destination = (
            FAMILY_ROOT / "Components/MobileBrowserSettingsDestinationView.swift"
        ).read_text()
        space = (
            FAMILY_ROOT
            / "Components/MobileSpaceSettingsView/MobileSpaceSettingsView.swift"
        ).read_text()

        for case in (
            ".general", ".links", ".spaces", ".sync", ".privacy",
            ".passwords", ".advanced",
        ):
            self.assertIn(f"case {case}:", destination)
        # Extensions are macOS-only and shortcuts are a desktop concern, so both
        # land on the same empty arm the mobile shell never routes to.
        self.assertIn("case .extensions, .shortcuts:", destination)
        self.assertIn("pages.permissionCenter", destination)
        self.assertNotIn("extensionControllerPool", destination)
        self.assertIn("browser.session.space(id: selectedSpaceID)", space)
        self.assertNotIn("spaces[", space)

    def test_navigation_rows_keep_stable_ids_and_full_hit_targets(self) -> None:
        regular = (
            FAMILY_ROOT / "Components/MobileBrowserSettingsDestinationList.swift"
        ).read_text()
        compact = (
            FAMILY_ROOT / "Components/MobileBrowserCompactSettingsLayout.swift"
        ).read_text()

        self.assertIn(".frame(maxWidth: .infinity, alignment: .leading)", regular)
        self.assertIn(".contentShape(.rect)", regular)
        self.assertIn('"settings-\\(destination.rawValue)"', regular)
        self.assertIn('"settings-\\(destination.rawValue)"', compact)


if __name__ == "__main__":
    unittest.main()
