#!/usr/bin/env python3
"""Behavioral coverage for Crest's vertical feature organization guard."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-vertical-structure.py"
DEBT_CONFIGURATION = REPOSITORY_ROOT / "Config" / "VerticalStructureDebt.json"


def load_guard_module():
    spec = importlib.util.spec_from_file_location(
        "crest_vertical_structure_guard", GUARD_SCRIPT
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Scripts/check-vertical-structure.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class VerticalFeatureContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository_root = Path(self.temporary_directory.name)
        for source_root in ("CrestShared", "CrestMac", "CrestMobile"):
            (self.repository_root / source_root).mkdir()
        self.configuration_path = self.repository_root / "debt.json"
        self.write_configuration([])

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_source(self, relative_path: str, source: str) -> None:
        destination = self.repository_root / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(source)

    def write_configuration(self, violations: list[dict[str, str]]) -> None:
        rules: dict[str, dict[str, object]] = {}
        for violation in violations:
            rule = violation["rule"]
            rule_configuration = rules.setdefault(
                rule,
                {
                    "reason": violation["reason"],
                    "violations": [],
                },
            )
            rule_configuration["violations"].append(
                [violation["path"], violation["subject"]]
            )
        self.configuration_path.write_text(
            json.dumps({"rules": rules}, indent=2, sort_keys=True) + "\n"
        )

    def violations(self):
        return self.guard.scan_repository(self.repository_root)

    def violation_keys(self) -> set[tuple[str, str, str]]:
        return {
            (violation.rule, violation.path, violation.subject)
            for violation in self.violations()
        }

    def test_current_repository_matches_the_explicit_debt_ledger(self) -> None:
        configured_debt = self.guard.load_debt_configuration(DEBT_CONFIGURATION)

        audit = self.guard.audit_repository(REPOSITORY_ROOT, configured_debt)

        self.assertEqual(audit.unexpected, [])
        self.assertEqual(audit.stale, [])

    def test_primary_declarations_are_single_and_match_their_files(self) -> None:
        self.write_source(
            "CrestShared/Domain/Two.swift",
            "struct First {}\nstruct Second {}\n",
        )
        self.write_source(
            "CrestShared/Domain/Wrong.swift",
            "struct Right {}\n",
        )
        self.write_source(
            "CrestShared/Domain/Owner+Protocol.swift",
            "protocol Surprise {}\n",
        )

        self.assertEqual(
            self.violation_keys(),
            {
                (
                    "multiple-primary-types",
                    "CrestShared/Domain/Two.swift",
                    "First,Second",
                ),
                (
                    "filename-type-mismatch",
                    "CrestShared/Domain/Wrong.swift",
                    "Right",
                ),
                (
                    "extension-file-primary-type",
                    "CrestShared/Domain/Owner+Protocol.swift",
                    "Surprise",
                ),
                (
                    "extension-file-count",
                    "CrestShared/Domain/Owner+Protocol.swift",
                    "none",
                ),
            },
        )

    def test_indented_top_level_declarations_cannot_bypass_ownership(self) -> None:
        self.write_source(
            "CrestShared/Domain/Indented.swift",
            "    struct First {}\n    struct Second {}\n",
        )

        self.assertIn(
            (
                "multiple-primary-types",
                "CrestShared/Domain/Indented.swift",
                "First,Second",
            ),
            self.violation_keys(),
        )

    def test_multiple_declarations_on_one_line_cannot_bypass_ownership(self) -> None:
        self.write_source(
            "CrestShared/Domain/Inline.swift",
            "struct First {} struct Second {}\n",
        )

        self.assertIn(
            (
                "multiple-primary-types",
                "CrestShared/Domain/Inline.swift",
                "First,Second",
            ),
            self.violation_keys(),
        )

    def test_primary_types_and_extensions_are_separate_file_owners(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner.swift",
            """struct Owner {}
extension Owner: Equatable {}
""",
        )

        self.assertIn(
            (
                "multiple-top-level-declarations",
                "CrestShared/Domain/Owner.swift",
                "Owner,extension Owner",
            ),
            self.violation_keys(),
        )

    def test_plain_files_cannot_group_multiple_extensions(self) -> None:
        self.write_source(
            "CrestShared/Domain/Helpers.swift",
            """extension First {}
extension Second {}
""",
        )

        self.assertIn(
            (
                "multiple-top-level-declarations",
                "CrestShared/Domain/Helpers.swift",
                "extension First,extension Second",
            ),
            self.violation_keys(),
        )

    def test_primary_types_and_global_helpers_are_separate_file_owners(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner.swift",
            """struct Owner {}
func makeOwner() -> Owner { Owner() }
""",
        )

        self.assertIn(
            (
                "multiple-top-level-declarations",
                "CrestShared/Domain/Owner.swift",
                "Owner,func makeOwner",
            ),
            self.violation_keys(),
        )

    def test_view_files_do_not_hide_other_types(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            """import SwiftUI
struct SampleView: View {
    var body: some View { Text("Sample") }
}
enum SampleMode { case standard }
#Preview { SampleView() }
""",
        )

        keys = self.violation_keys()

        self.assertIn(
            (
                "multiple-primary-types",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleMode,SampleView",
            ),
            keys,
        )
        self.assertIn(
            (
                "view-file-extra-primary",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleMode",
            ),
            keys,
        )

    def test_view_files_do_not_hide_nested_child_views(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            """import SwiftUI
struct SampleView: View {
    struct ChildView: View {
        var body: some View { Text("Child") }
    }

    var body: some View { ChildView() }
}
#Preview { SampleView() }
""",
        )

        self.assertIn(
            (
                "view-file-nested-type",
                "CrestShared/Features/Sample/SampleView.swift",
                "ChildView",
            ),
            self.violation_keys(),
        )

    def test_inline_nested_child_views_cannot_bypass_ownership(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            """import SwiftUI
struct SampleView: View { struct ChildView: View { var body: some View { EmptyView() } }; var body: some View { ChildView() } }
#Preview { SampleView() }
""",
        )

        self.assertIn(
            (
                "view-file-nested-type",
                "CrestShared/Features/Sample/SampleView.swift",
                "ChildView",
            ),
            self.violation_keys(),
        )

    def test_nonvisual_files_allow_scope_dependent_private_helpers_and_aliases(self) -> None:
        self.write_source(
            "CrestMac/Infrastructure/Payload.swift",
            """import AppKit
struct Payload: Codable {
    private enum CodingKeys: String, CodingKey { case value }
    private final class Coordinator {}
    typealias Loader = () async -> String
    enum PublicState { case ready }
    let value: String
}
""",
        )

        keys = self.violation_keys()
        self.assertNotIn(
            (
                "nested-named-type",
                "CrestMac/Infrastructure/Payload.swift",
                "Coordinator",
            ),
            keys,
        )
        self.assertNotIn(
            (
                "nested-named-type",
                "CrestMac/Infrastructure/Payload.swift",
                "Loader",
            ),
            keys,
        )
        self.assertIn(
            (
                "nested-named-type",
                "CrestMac/Infrastructure/Payload.swift",
                "PublicState",
            ),
            keys,
        )

    def test_vertical_folders_keep_visual_and_nonvisual_owners_separate(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SamplePolicy.swift",
            "struct SamplePolicy {}\n",
        )
        self.write_source(
            "CrestShared/Features/Sample/Components/SampleFormatter.swift",
            "struct SampleFormatter {}\n",
        )
        self.write_source(
            "CrestShared/Features/Sample/Models/SampleBadge.swift",
            """import SwiftUI
struct SampleBadge: View {
    var body: some View { EmptyView() }
}
#Preview { SampleBadge() }
""",
        )

        keys = self.violation_keys()

        self.assertIn(
            (
                "feature-root-nonvisual",
                "CrestShared/Features/Sample/SamplePolicy.swift",
                "SamplePolicy",
            ),
            keys,
        )
        self.assertIn(
            (
                "components-nonvisual",
                "CrestShared/Features/Sample/Components/SampleFormatter.swift",
                "SampleFormatter",
            ),
            keys,
        )
        self.assertIn(
            (
                "nonvisual-folder-visual",
                "CrestShared/Features/Sample/Models/SampleBadge.swift",
                "SampleBadge",
            ),
            keys,
        )

    def test_extension_only_files_do_not_bypass_visual_feature_roles(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SamplePolicy+Support.swift",
            "extension SamplePolicy {}\n",
        )
        self.write_source(
            "CrestShared/Features/Sample/Components/SampleCard+Support.swift",
            "extension SampleCard {}\n",
        )

        keys = self.violation_keys()

        self.assertIn(
            (
                "feature-root-nonvisual",
                "CrestShared/Features/Sample/SamplePolicy+Support.swift",
                "SamplePolicy+Support",
            ),
            keys,
        )
        self.assertIn(
            (
                "components-nonvisual",
                "CrestShared/Features/Sample/Components/SampleCard+Support.swift",
                "SampleCard+Support",
            ),
            keys,
        )

    def test_arbitrary_feature_peer_folders_are_rejected(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Helpers/Thing.swift",
            "struct Thing {}\n",
        )

        self.assertIn(
            (
                "feature-folder-role",
                "CrestShared/Features/Sample/Helpers/Thing.swift",
                "Helpers",
            ),
            self.violation_keys(),
        )

    def test_named_visual_families_may_own_standard_vertical_buckets(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            """import SwiftUI
struct SampleView: View {
    var body: some View { Text("Sample") }
}
#Preview { SampleView() }
""",
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView/Components/SampleCard.swift",
            """import SwiftUI
struct SampleCard: View {
    var body: some View { Text("Card") }
}
#Preview { SampleCard() }
""",
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView/Models/SampleState.swift",
            "struct SampleState {}\n",
        )

        self.assertEqual(self.violations(), [])

    def test_nested_component_families_may_own_models_and_support(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/Card/Models/CardState.swift",
            "struct CardState {}\n",
        )
        self.write_source(
            "CrestShared/Features/Sample/Components/Card/Support/CardMetrics.swift",
            "struct CardMetrics {}\n",
        )

        self.assertEqual(self.violations(), [])

    def test_visual_types_cannot_hide_below_nested_nonvisual_folders(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Models/Rows/CardView.swift",
            """import SwiftUI
struct CardView: View {
    var body: some View { Text("Card") }
}
#Preview { CardView() }
""",
        )

        self.assertIn(
            (
                "nonvisual-folder-visual",
                "CrestShared/Features/Sample/Models/Rows/CardView.swift",
                "CardView",
            ),
            self.violation_keys(),
        )

    def test_component_family_root_rejects_nonvisual_support_types(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/Card/CardState.swift",
            "struct CardState {}\n",
        )

        self.assertIn(
            (
                "components-nonvisual",
                "CrestShared/Features/Sample/Components/Card/CardState.swift",
                "CardState",
            ),
            self.violation_keys(),
        )

    def test_visual_types_have_a_direct_colocated_preview(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/SampleCard.swift",
            """import SwiftUI
struct SampleCard: View {
    var body: some View { Text("Sample") }
}
#Preview { EmptyView() }
""",
        )
        self.write_source(
            "CrestShared/Features/Sample/Components/PreviewedCard.swift",
            """import SwiftUI
struct PreviewedCard: View {
    var body: some View { Text("Previewed") }
}
#Preview { PreviewedCard() }
""",
        )

        self.assertIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Components/SampleCard.swift",
                "SampleCard",
            ),
            self.violation_keys(),
        )
        self.assertNotIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Components/PreviewedCard.swift",
                "PreviewedCard",
            ),
            self.violation_keys(),
        )

    def test_invisible_modifiers_and_platform_bridges_do_not_require_previews(
        self,
    ) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/SampleModifier.swift",
            """import SwiftUI
struct SampleModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}
""",
        )
        self.write_source(
            "CrestMac/Features/Sample/Components/SampleBridge.swift",
            """import SwiftUI
struct SampleBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
""",
        )

        keys = self.violation_keys()
        self.assertNotIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Components/SampleModifier.swift",
                "SampleModifier",
            ),
            keys,
        )
        self.assertNotIn(
            (
                "missing-direct-preview",
                "CrestMac/Features/Sample/Components/SampleBridge.swift",
                "SampleBridge",
            ),
            keys,
        )

    def test_context_owned_style_surfaces_do_not_require_direct_previews(self) -> None:
        self.write_source(
            "CrestShared/DesignSystem/Components/SampleStyle/Styles/SampleStyleSurface.swift",
            """import SwiftUI
struct SampleStyleSurface: View {
    var body: some View { Text("Rendered only by its style") }
}
""",
        )

        self.assertNotIn(
            (
                "missing-direct-preview",
                "CrestShared/DesignSystem/Components/SampleStyle/Styles/SampleStyleSurface.swift",
                "SampleStyleSurface",
            ),
            self.violation_keys(),
        )

    def test_app_storage_effect_boundaries_do_not_require_live_previews(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            """import SwiftUI
struct SampleView: View {
    @AppStorage("sample") private var sample = false
    var body: some View { Text(String(sample)) }
}
""",
        )

        self.assertNotIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView",
            ),
            self.violation_keys(),
        )

    def test_commented_preview_references_do_not_satisfy_direct_coverage(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/CommentedCard.swift",
            """import SwiftUI
struct CommentedCard: View {
    var body: some View { Text("Sample") }
}
#Preview {
    EmptyView()
    // CommentedCard()
}
""",
        )

        self.assertIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Components/CommentedCard.swift",
                "CommentedCard",
            ),
            self.violation_keys(),
        )

    def test_preview_construction_must_be_part_of_the_rendered_expression(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/DiscardedCard.swift",
            """import SwiftUI
struct DiscardedCard: View {
    var body: some View { Text("Sample") }
}
#Preview {
    let _ = DiscardedCard()
    EmptyView()
}
""",
        )

        self.assertIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Components/DiscardedCard.swift",
                "DiscardedCard",
            ),
            self.violation_keys(),
        )

    def test_preview_construction_inside_an_unused_factory_is_not_direct_coverage(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/FactoryCard.swift",
            """import SwiftUI
struct FactoryCard: View {
    var body: some View { Text("Sample") }
}
#Preview {
    let factory = { FactoryCard() }
    EmptyView()
}
""",
        )

        self.assertIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Components/FactoryCard.swift",
                "FactoryCard",
            ),
            self.violation_keys(),
        )

    def test_preview_construction_inside_a_rendered_wrapper_is_direct_coverage(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/WrappedCard.swift",
            """import SwiftUI
struct WrappedCard: View {
    var body: some View { Text("Sample") }
}
#Preview {
    Group {
        WrappedCard()
    }
}
""",
        )

        self.assertNotIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Components/WrappedCard.swift",
                "WrappedCard",
            ),
            self.violation_keys(),
        )

    def test_typealiases_do_not_inherit_the_next_declarations_conformance(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Models/SampleAlias.swift",
            """import SwiftUI
typealias SampleAlias = String
struct SampleAliasCard: View {
    var body: some View { Text("Sample") }
}
#Preview { SampleAliasCard() }
""",
        )

        self.assertNotIn(
            (
                "missing-direct-preview",
                "CrestShared/Features/Sample/Models/SampleAlias.swift",
                "SampleAlias",
            ),
            self.violation_keys(),
        )

    def test_generic_constraints_do_not_make_models_visual(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Models/Container.swift",
            "struct Container<Content: View> {}\n",
        )

        self.assertEqual(self.violations(), [])

    def test_large_root_view_helpers_are_component_boundaries(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(124)
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            f"""import SwiftUI
struct SampleView: View {{
    var body: some View {{ content }}

    private var content: some View {{
        VStack {{
{repeated_rows}
        }}
    }}
}}
#Preview {{ SampleView() }}
""",
        )

        self.assertIn(
            (
                "large-computed-view-helper",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView.content",
            ),
            self.violation_keys(),
        )

    def test_multiline_view_builder_functions_are_component_boundaries(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(124)
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            f"""import SwiftUI
struct SampleView: View {{
    var body: some View {{ content() }}

    @ViewBuilder
    private func content(
        showsRows: Bool = true
    ) -> some View {{
        if showsRows {{
            VStack {{
{repeated_rows}
            }}
        }}
    }}
}}
#Preview {{ SampleView() }}
""",
        )

        self.assertIn(
            (
                "large-computed-view-helper",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView.content",
            ),
            self.violation_keys(),
        )

    def test_attributed_computed_view_properties_are_component_boundaries(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(124)
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            f"""import SwiftUI
struct SampleView: View {{
    var body: some View {{ content }}

    @ViewBuilder private var content: some View {{
        VStack {{
{repeated_rows}
        }}
    }}
}}
#Preview {{ SampleView() }}
""",
        )

        self.assertIn(
            (
                "large-computed-view-helper",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView.content",
            ),
            self.violation_keys(),
        )

    def test_large_root_view_bodies_are_component_boundaries(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(184)
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            f"""import SwiftUI
struct SampleView: View {{
    var body: some View {{
        VStack {{
{repeated_rows}
        }}
    }}
}}
#Preview {{ SampleView() }}
""",
        )

        self.assertIn(
            (
                "large-root-view-body",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView.body",
            ),
            self.violation_keys(),
        )

    def test_cohesive_root_view_bodies_can_remain_local(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(40)
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            f"""import SwiftUI
struct SampleView: View {{
    var body: some View {{
        VStack {{
{repeated_rows}
        }}
    }}
}}
#Preview {{ SampleView() }}
""",
        )

        self.assertNotIn(
            (
                "large-root-view-body",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView.body",
            ),
            self.violation_keys(),
        )

    def test_large_component_bodies_remain_local_component_implementations(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(24)
        )
        self.write_source(
            "CrestShared/Features/Sample/Components/SampleCard.swift",
            f"""import SwiftUI
struct SampleCard: View {{
    var body: some View {{
        VStack {{
{repeated_rows}
        }}
    }}
}}
#Preview {{ SampleCard() }}
""",
        )

        self.assertNotIn(
            (
                "large-root-view-body",
                "CrestShared/Features/Sample/Components/SampleCard.swift",
                "SampleCard.body",
            ),
            self.violation_keys(),
        )

    def test_module_qualified_root_view_bodies_are_component_boundaries(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(184)
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            f"""import SwiftUI
struct SampleView: SwiftUI.View {{
    var body: some SwiftUI.View {{
        VStack {{
{repeated_rows}
        }}
    }}
}}
#Preview {{ SampleView() }}
""",
        )

        self.assertIn(
            (
                "large-root-view-body",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView.body",
            ),
            self.violation_keys(),
        )

    def test_extension_owned_root_view_bodies_are_component_boundaries(self) -> None:
        repeated_rows = "\n".join(
            f'            Text("Row {index}")' for index in range(184)
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            f"""import SwiftUI
struct SampleView {{}}
extension SampleView: View {{
    var body: some View {{
        VStack {{
{repeated_rows}
        }}
    }}
}}
#Preview {{ SampleView() }}
""",
        )

        self.assertIn(
            (
                "large-root-view-body",
                "CrestShared/Features/Sample/SampleView.swift",
                "SampleView.body",
            ),
            self.violation_keys(),
        )

    def test_previews_reject_live_dependencies_and_require_isolated_app_storage(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/UnsafeCard.swift",
            """import SwiftUI
struct UnsafeCard: View {
    @AppStorage("sample") private var sample = false
    var body: some View { Text(String(sample)) }
}
#Preview {
    let defaults = UserDefaults.standard
    UnsafeCard()
}
""",
        )

        keys = self.violation_keys()

        self.assertIn(
            (
                "preview-live-dependency",
                "CrestShared/Features/Sample/Components/UnsafeCard.swift",
                "UserDefaults",
            ),
            keys,
        )
        self.assertIn(
            (
                "preview-live-app-storage",
                "CrestShared/Features/Sample/Components/UnsafeCard.swift",
                "@AppStorage",
            ),
            keys,
        )

    def test_previews_reject_disk_webkit_and_named_defaults_even_when_injected(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/UnsafePreviewCard.swift",
            """import SwiftUI
import WebKit
struct UnsafePreviewCard: View {
    @AppStorage("sample") private var sample = false
    var body: some View { Text(String(sample)) }
}
#Preview {
    let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/sample"))
    let store = WKWebsiteDataStore.default()
    UnsafePreviewCard()
        .defaultAppStorage(UserDefaults(suiteName: "real.saved.suite")!)
}
""",
        )

        keys = self.violation_keys()
        relative_path = (
            "CrestShared/Features/Sample/Components/UnsafePreviewCard.swift"
        )
        for subject in (
            "Data(contentsOf:)",
            "UserDefaults",
            "WKWebsiteDataStore.default",
        ):
            with self.subTest(subject=subject):
                self.assertIn(
                    ("preview-live-dependency", relative_path, subject),
                    keys,
                )
        self.assertIn(
            ("preview-live-app-storage", relative_path, "@AppStorage"),
            keys,
        )

    def test_preview_detection_ignores_commented_preview_markers(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/CommentMarkerCard.swift",
            """import SwiftUI
// #Preview { CommentMarkerCard() }
struct CommentMarkerCard: View {
    @AppStorage("sample") private var sample = false
    var body: some View { Text(String(sample)) }
}
#Preview { CommentMarkerCard() }
""",
        )

        self.assertIn(
            (
                "preview-live-app-storage",
                "CrestShared/Features/Sample/Components/CommentMarkerCard.swift",
                "@AppStorage",
            ),
            self.violation_keys(),
        )

    def test_preview_detection_rejects_module_qualified_app_storage(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/QualifiedStorageCard.swift",
            """import SwiftUI
struct QualifiedStorageCard: View {
    @SwiftUI.AppStorage("sample") private var sample = false
    var body: some View { Text(String(sample)) }
}
#Preview { QualifiedStorageCard() }
""",
        )

        self.assertIn(
            (
                "preview-live-app-storage",
                "CrestShared/Features/Sample/Components/QualifiedStorageCard.swift",
                "@AppStorage",
            ),
            self.violation_keys(),
        )

    def test_previewed_visual_implementation_cannot_load_remote_or_default_web_content(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/RemoteCard.swift",
            """import SwiftUI
import WebKit
struct RemoteCard: View {
    var body: some View {
        AsyncImage(url: URL(string: "https://example.com/image.png"))
    }

    private func makeWebView() -> WKWebView {
        WKWebView()
    }
}
#Preview { RemoteCard() }
""",
        )

        keys = self.violation_keys()
        relative_path = "CrestShared/Features/Sample/Components/RemoteCard.swift"
        self.assertIn(
            ("preview-live-dependency", relative_path, "AsyncImage"),
            keys,
        )

    def test_previewed_visual_implementation_rejects_configured_and_swiftui_web_views(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/WebContentCard.swift",
            """import SwiftUI
import WebKit
struct WebContentCard: View {
    var body: some View { WebView(url: URL(string: "https://example.com")!) }

    private func makeWebView() -> WKWebView {
        WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
    }
}
#Preview { WebContentCard() }
""",
        )

        keys = self.violation_keys()
        relative_path = "CrestShared/Features/Sample/Components/WebContentCard.swift"
        self.assertIn(
            ("preview-live-dependency", relative_path, "WKWebView"),
            keys,
        )
        self.assertIn(
            ("preview-live-dependency", relative_path, "WebView"),
            keys,
        )
        self.assertIn(
            ("preview-live-dependency", relative_path, "WKWebView"),
            keys,
        )

    def test_preview_fixture_identity_must_be_deterministic(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/RandomCard.swift",
            """import SwiftUI
struct RandomCard: View {
    let id: UUID
    var body: some View { Text(id.uuidString) }
}
#Preview { RandomCard(id: UUID()) }
""",
        )

        self.assertIn(
            (
                "preview-nondeterministic-fixture",
                "CrestShared/Features/Sample/Components/RandomCard.swift",
                "UUID()",
            ),
            self.violation_keys(),
        )

    def test_preview_fixture_accepts_fixed_identity_and_date_values(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/FixedCard.swift",
            """import SwiftUI
struct FixedCard: View {
    let id: UUID
    let date: Date
    var body: some View { Text(id.uuidString + date.description) }
}
#Preview {
    FixedCard(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        date: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
""",
        )

        self.assertNotIn(
            "preview-nondeterministic-fixture",
            {violation.rule for violation in self.violations()},
        )

    def test_rendered_preview_implementation_and_static_fixtures_are_deterministic(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/DynamicCard.swift",
            """import SwiftUI
private let previewID = UUID()
struct DynamicCard: View {
    let id: UUID
    var body: some View { Text(Date().description + id.uuidString) }
}
#Preview { DynamicCard(id: previewID) }
""",
        )

        keys = self.violation_keys()
        relative_path = "CrestShared/Features/Sample/Components/DynamicCard.swift"
        self.assertIn(
            ("preview-nondeterministic-fixture", relative_path, "Date()"),
            keys,
        )
        self.assertIn(
            ("preview-nondeterministic-fixture", relative_path, "UUID()"),
            keys,
        )

    def test_preview_rejects_random_collections_but_accepts_fixture_names_and_enum_cases(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Components/FixtureCard.swift",
            """import SwiftUI
struct FixtureCard: View {
    let vault: InMemoryKeychainVault
    let phase: FixturePhase
    let value: Int?
    var body: some View { Text(String(describing: value)) }
}
#Preview {
    FixtureCard(
        vault: InMemoryKeychainVault(),
        phase: .now,
        value: [1, 2, 3].randomElement()
    )
}
""",
        )

        keys = self.violation_keys()
        relative_path = "CrestShared/Features/Sample/Components/FixtureCard.swift"
        self.assertIn(
            ("preview-nondeterministic-fixture", relative_path, "random"),
            keys,
        )
        self.assertNotIn(
            ("preview-live-dependency", relative_path, "Security Keychain"),
            keys,
        )
        self.assertNotIn(
            ("preview-nondeterministic-fixture", relative_path, "now"),
            keys,
        )

    def test_named_extension_files_have_one_matching_owner(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+Equatable.swift",
            """extension Owner: Equatable {}
extension Unrelated: Equatable {}
""",
        )

        self.assertIn(
            (
                "extension-file-count",
                "CrestShared/Domain/Owner+Equatable.swift",
                "Owner,Unrelated",
            ),
            self.violation_keys(),
        )

    def test_named_extension_file_accepts_one_matching_owner(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+Equatable.swift",
            "extension Owner: Equatable {}\n",
        )

        self.assertEqual(self.violations(), [])

    def test_named_extension_suffix_matches_its_declared_conformance(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+Codable.swift",
            "extension Owner: Equatable {}\n",
        )

        self.assertIn(
            (
                "extension-file-conformance-mismatch",
                "CrestShared/Domain/Owner+Codable.swift",
                "Equatable",
            ),
            self.violation_keys(),
        )

    def test_known_conformance_suffix_requires_the_conformance(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+Codable.swift",
            "extension Owner {}\n",
        )

        self.assertIn(
            (
                "extension-file-conformance-mismatch",
                "CrestShared/Domain/Owner+Codable.swift",
                "none",
            ),
            self.violation_keys(),
        )

    def test_conformance_suffix_does_not_accept_partial_protocol_names(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+Codable.swift",
            "extension Owner: NotCodable {}\n",
        )

        self.assertIn(
            (
                "extension-file-conformance-mismatch",
                "CrestShared/Domain/Owner+Codable.swift",
                "NotCodable",
            ),
            self.violation_keys(),
        )

    def test_primary_associated_types_preserve_the_protocol_conformance_name(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+FooProtocol.swift",
            "extension Owner: FooProtocol<Bar> {}\n",
        )

        self.assertNotIn(
            "extension-file-conformance-mismatch",
            {violation.rule for violation in self.violations()},
        )

    def test_named_extension_files_reject_unrelated_global_content(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+Equatable.swift",
            """extension Owner: Equatable {}
func unrelatedHelper() {}
""",
        )

        self.assertIn(
            (
                "extension-file-global-content",
                "CrestShared/Domain/Owner+Equatable.swift",
                "func unrelatedHelper",
            ),
            self.violation_keys(),
        )

    def test_named_extension_files_reject_global_operator_declarations(self) -> None:
        self.write_source(
            "CrestShared/Domain/Owner+Equatable.swift",
            """extension Owner: Equatable {}
prefix operator +++
""",
        )

        self.assertIn(
            (
                "extension-file-global-content",
                "CrestShared/Domain/Owner+Equatable.swift",
                "operator +++",
            ),
            self.violation_keys(),
        )

    def test_visual_extension_conformances_follow_visual_folder_and_preview_rules(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Models/Card+View.swift",
            """import SwiftUI
extension Card: View {
    var body: some View { Text("Card") }
}
""",
        )

        keys = self.violation_keys()
        relative_path = "CrestShared/Features/Sample/Models/Card+View.swift"
        self.assertIn(
            ("nonvisual-folder-visual", relative_path, "Card"),
            keys,
        )
        self.assertIn(
            ("missing-direct-preview", relative_path, "Card"),
            keys,
        )

    def test_visual_extensions_cannot_add_a_second_view_or_hide_its_primary_in_models(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/Models/OtherView.swift",
            "struct OtherView {}\n",
        )
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            """import SwiftUI
struct SampleView: View {
    var body: some View { Text("Sample") }
}
extension OtherView: View {
    var body: some View { Text("Other") }
}
#Preview {
    SampleView()
    OtherView()
}
""",
        )

        keys = self.violation_keys()
        self.assertIn(
            (
                "multiple-view-types",
                "CrestShared/Features/Sample/SampleView.swift",
                "OtherView,SampleView",
            ),
            keys,
        )
        self.assertIn(
            (
                "nonvisual-folder-visual",
                "CrestShared/Features/Sample/Models/OtherView.swift",
                "OtherView",
            ),
            keys,
        )

    def test_visual_extension_inference_never_crosses_platform_roots(self) -> None:
        self.write_source(
            "CrestMac/Features/Sample/Models/ExternalCard.swift",
            "struct ExternalCard {}\n",
        )
        self.write_source(
            "CrestMobile/Features/Sample/Components/ExternalCard+View.swift",
            """import SwiftUI
extension ExternalCard: View {
    var body: some View { Text("External") }
}
#Preview { ExternalCard() }
""",
        )

        self.assertNotIn(
            (
                "nonvisual-folder-visual",
                "CrestMac/Features/Sample/Models/ExternalCard.swift",
                "ExternalCard",
            ),
            self.violation_keys(),
        )

    def test_debt_ledger_is_exact_and_rejects_stale_entries(self) -> None:
        relative_path = "CrestShared/Domain/Wrong.swift"
        self.write_source(relative_path, "struct Right {}\n")
        self.write_configuration(
            [
                {
                    "rule": "filename-type-mismatch",
                    "path": relative_path,
                    "subject": "Right",
                    "reason": "Existing migration debt.",
                }
            ]
        )
        configured_debt = self.guard.load_debt_configuration(
            self.configuration_path
        )

        matching_audit = self.guard.audit_repository(
            self.repository_root, configured_debt
        )

        self.assertEqual(matching_audit.unexpected, [])
        self.assertEqual(matching_audit.stale, [])

        self.write_source(relative_path, "struct Wrong {}\n")
        stale_audit = self.guard.audit_repository(
            self.repository_root, configured_debt
        )

        self.assertEqual(stale_audit.unexpected, [])
        self.assertEqual(
            [violation.key for violation in stale_audit.stale],
            [
                (
                    "filename-type-mismatch",
                    relative_path,
                    "Right",
                )
            ],
        )

    def test_repository_contract_documents_the_vertical_organization_rules(self) -> None:
        contract = (
            REPOSITORY_ROOT / "Documentation/RepositoryGuardrails.md"
        ).read_text()

        for required_phrase in (
            "Features/<Feature>",
            "Components`, `Models`, `Services`, and `Support",
            "exactly one file-scope declaration per Swift file",
            "an extension lives alone in a matching `Type+Concern.swift` file",
            "A view file contains its single view declaration",
            "Root screens compose real, narrowly scoped `View` types",
            "deterministic `#Preview` beside the component",
            "keeping macOS and mobile shells",
        ):
            with self.subTest(required_phrase=required_phrase):
                self.assertIn(required_phrase, contract)


if __name__ == "__main__":
    unittest.main()
