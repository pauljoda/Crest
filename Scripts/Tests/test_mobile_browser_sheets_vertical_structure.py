#!/usr/bin/env python3
"""Vertical ownership contracts for mobile Archive, History, and Passwords."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LEGACY_AGGREGATE = (
    REPOSITORY_ROOT / "CrestMobile/Features/Settings/MobileBrowserSheets.swift"
)
ARCHIVE_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Archive"
HISTORY_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/History"
CREDENTIALS_ROOT = REPOSITORY_ROOT / "CrestMobile/Features/Credentials"
PASSWORD_FAMILY = CREDENTIALS_ROOT / "MobilePasswordSettingsView"
PREVIEW_ROOT = REPOSITORY_ROOT / "CrestMobile/PreviewSupport"
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class MobileBrowserSheetsVerticalStructureTests(unittest.TestCase):
    def test_legacy_settings_aggregate_is_removed(self) -> None:
        self.assertFalse(LEGACY_AGGREGATE.exists())

    def test_each_owner_has_one_matching_file(self) -> None:
        required = {
            ARCHIVE_ROOT / "MobileArchiveView.swift": "MobileArchiveView",
            ARCHIVE_ROOT / "MobileArchiveView/Components/MobileArchiveContent.swift":
                "MobileArchiveContent",
            ARCHIVE_ROOT / "MobileArchiveView/Components/MobileArchiveList.swift":
                "MobileArchiveList",
            HISTORY_ROOT / "MobileHistoryView.swift": "MobileHistoryView",
            HISTORY_ROOT / "MobileHistoryView/Components/MobileHistoryContent.swift":
                "MobileHistoryContent",
            HISTORY_ROOT / "MobileHistoryView/Components/MobileHistoryList.swift":
                "MobileHistoryList",
            CREDENTIALS_ROOT / "MobilePasswordSettingsView.swift":
                "MobilePasswordSettingsView",
            PASSWORD_FAMILY / "Models/MobilePasswordSettingsModel.swift":
                "MobilePasswordSettingsModel",
            PASSWORD_FAMILY / "Components/MobilePasswordSettingsContent.swift":
                "MobilePasswordSettingsContent",
            PASSWORD_FAMILY / "Components/MobilePasswordSpaceSection.swift":
                "MobilePasswordSpaceSection",
            PASSWORD_FAMILY / "Components/MobilePasswordDataSections.swift":
                "MobilePasswordDataSections",
            PASSWORD_FAMILY / "Components/MobilePasswordCredentialSection.swift":
                "MobilePasswordCredentialSection",
            PASSWORD_FAMILY / "Components/MobilePasswordDescriptorList.swift":
                "MobilePasswordDescriptorList",
            PASSWORD_FAMILY / "Components/MobilePasswordSystemPasskeysSection.swift":
                "MobilePasswordSystemPasskeysSection",
            PASSWORD_FAMILY / "Support/MobilePasswordSettingsToolbar.swift":
                "MobilePasswordSettingsToolbar",
            PASSWORD_FAMILY / "Components/MobilePasswordSettingsPresentationModifier.swift":
                "MobilePasswordSettingsPresentationModifier",
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

    def test_root_views_compose_real_components(self) -> None:
        roots = {
            ARCHIVE_ROOT / "MobileArchiveView.swift": "MobileArchiveContent(",
            HISTORY_ROOT / "MobileHistoryView.swift": "MobileHistoryContent(",
            CREDENTIALS_ROOT / "MobilePasswordSettingsView.swift":
                "MobilePasswordSettingsContent(",
        }

        for path, component in roots.items():
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn(component, source)
                self.assertNotRegex(
                    source,
                    r"private\s+var\s+\w+\s*:\s*some\s+View",
                )
                self.assertNotIn("@ViewBuilder", source)
                self.assertIn("#Preview", source)

    def test_visual_owners_have_direct_isolated_previews(self) -> None:
        roots = (ARCHIVE_ROOT, HISTORY_ROOT, PASSWORD_FAMILY)
        visual_files = [
            ARCHIVE_ROOT / "MobileArchiveView.swift",
            HISTORY_ROOT / "MobileHistoryView.swift",
            CREDENTIALS_ROOT / "MobilePasswordSettingsView.swift",
        ]
        for root in roots:
            visual_files.extend(root.rglob("*.swift"))

        for path in sorted(set(visual_files)):
            source = path.read_text()
            declarations = DECLARATION_PATTERN.findall(source)
            if not declarations or not re.search(r":\s*(?:View|ViewModifier|ToolbarContent)\b", source):
                continue
            owner = declarations[0]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("#Preview", source)
                preview = source[source.index("#Preview"):]
                self.assertIn(f"{owner}(", preview)
                self.assertNotIn("BrowserStore.preview()", source)
                self.assertNotIn("UserDefaults", source)
                self.assertNotIn("WKWebsiteDataStore.default", source)
                self.assertNotIn("UUID()", source)
                self.assertNotIn(".now", source)

    def test_preview_graph_is_fixed_and_in_memory(self) -> None:
        source = (PREVIEW_ROOT / "MobileBrowserPreviewFixture.swift").read_text()

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

    def test_space_sensitive_actions_remain_exact_assignment_bound(self) -> None:
        archive = (ARCHIVE_ROOT / "MobileArchiveView.swift").read_text()
        history = (HISTORY_ROOT / "MobileHistoryView.swift").read_text()
        model = (
            PASSWORD_FAMILY / "Models/MobilePasswordSettingsModel.swift"
        ).read_text()
        credential_store = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Settings/BrowserPasswordSettingsPane/Models/BrowserCredentialSpaceStore.swift"
        ).read_text()

        self.assertIn(
            "browser.restoreArchivedTab(tabID, matching: assignment)", archive
        )
        self.assertIn("browser.clearHistory(matching: assignment)", history)
        self.assertIn("selectedUnlockedSpace(", archive)
        self.assertIn("selectedUnlockedSpace(", history)
        self.assertIn("browser.session.space(id: selectedSpaceID)", model)
        self.assertIn("credentials.delete(", model)
        self.assertIn("descriptor.spaceID", credential_store)
        self.assertNotIn("session.spaces[", model)


if __name__ == "__main__":
    unittest.main()
