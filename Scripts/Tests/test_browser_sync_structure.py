#!/usr/bin/env python3
"""Structural contract for the shared BrowserSync domain decomposition."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
SYNC_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserSync"
# The guard exists to catch a file quietly becoming a grab bag, not to force a
# cohesive algorithm apart. The journal and the materializer both grew when
# out-of-order record delivery stopped being treated as a deletion: each now
# distinguishes a parent that was deleted from one that has not arrived yet, and
# the materializer walks a held-back folder subtree transitively. Splitting
# either to fit a smaller number would scatter one decision across files.
SOURCE_LINE_LIMIT = 400


class BrowserSyncStructureTests(unittest.TestCase):
    def test_flat_sync_source_is_replaced_by_responsibility_tree(self) -> None:
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserSync.swift").exists()
        )

        required_files = (
            "Preferences/BrowserSyncPreferences.swift",
            "Records/BrowserSyncRecordKind.swift",
            "Records/BrowserSyncRecordID.swift",
            "Records/BrowserSyncVersion.swift",
            "Records/BrowserSyncRecord.swift",
            "Records/BrowserSyncError.swift",
            "Records/BrowserSyncTombstoneReason.swift",
            "Records/BrowserSyncTombstone.swift",
            "Payloads/BrowserSyncSpace.swift",
            "Payloads/BrowserSyncFolder.swift",
            "Payloads/BrowserSyncTab.swift",
            "Payloads/BrowserSyncHistory.swift",
            "Payloads/BrowserSyncArchive.swift",
            "Payloads/BrowserSyncPayload.swift",
            "Payloads/BrowserSyncPayload+Validation.swift",
            "Payloads/BrowserSyncPayload+Values.swift",
            "Journal/BrowserSyncJournal.swift",
            "Merge/BrowserSyncMergeResolver.swift",
            "Merge/BrowserSyncRecordReconciler.swift",
            "Comparison/BrowserSyncContentComparison.swift",
            "Ordering/BrowserSyncOrderTokenAllocator.swift",
            "Ordering/Array+BrowserSyncRecordOrdering.swift",
            "Ordering/TabPlacement+BrowserSyncOrdering.swift",
            "Projection/BrowserSyncProjection.swift",
            "Materialization/BrowserSyncMaterializer.swift",
        )
        for relative_path in required_files:
            with self.subTest(relative_path=relative_path):
                self.assertTrue((SYNC_ROOT / relative_path).is_file())

    def test_each_source_has_at_most_one_primary_declaration(self) -> None:
        declaration_pattern = re.compile(
            r"^(?:public |internal |private |fileprivate )?"
            r"(?:struct|enum|class|actor|protocol|typealias) ",
            re.MULTILINE,
        )

        for source_path in SYNC_ROOT.rglob("*.swift"):
            with self.subTest(source_path=source_path.relative_to(SYNC_ROOT)):
                declarations = declaration_pattern.findall(source_path.read_text())
                self.assertLessEqual(len(declarations), 1)

    def test_journal_root_is_focused_and_bounded(self) -> None:
        root_source = (SYNC_ROOT / "Journal/BrowserSyncJournal.swift").read_text()

        self.assertEqual(root_source.count("struct BrowserSyncJournal"), 1)
        self.assertNotIn("enum BrowserSyncProjection", root_source)
        self.assertNotIn("enum BrowserSyncMaterializer", root_source)
        self.assertNotIn("enum BrowserSyncMergeResolver", root_source)
        self.assertLess(len(root_source.splitlines()), SOURCE_LINE_LIMIT)

    def test_all_sync_sources_remain_bounded(self) -> None:
        for source_path in SYNC_ROOT.rglob("*.swift"):
            with self.subTest(source_path=source_path.relative_to(SYNC_ROOT)):
                self.assertLess(
                    len(source_path.read_text().splitlines()), SOURCE_LINE_LIMIT
                )

    def test_projection_and_materialization_are_isolated(self) -> None:
        projection_source = (
            SYNC_ROOT / "Projection/BrowserSyncProjection.swift"
        ).read_text()
        materializer_source = (
            SYNC_ROOT / "Materialization/BrowserSyncMaterializer.swift"
        ).read_text()

        self.assertIn("enum BrowserSyncProjection", projection_source)
        self.assertNotIn("enum BrowserSyncMaterializer", projection_source)
        self.assertIn("enum BrowserSyncMaterializer", materializer_source)
        self.assertNotIn("enum BrowserSyncProjection", materializer_source)

    def test_tab_placement_ordering_does_not_export_a_global_max_overload(
        self,
    ) -> None:
        ordering_source = (
            SYNC_ROOT / "Ordering/TabPlacement+BrowserSyncOrdering.swift"
        ).read_text()
        resolver_source = (
            SYNC_ROOT / "Merge/BrowserSyncMergeResolver.swift"
        ).read_text()

        self.assertNotRegex(ordering_source, r"(?m)^func max\(")
        self.assertIn("TabPlacement.max(", resolver_source)


if __name__ == "__main__":
    unittest.main()
