#!/usr/bin/env python3
"""Vertical, preview, and identity contracts for credential detail UI."""

from __future__ import annotations

import json
from pathlib import Path
import re
import runpy
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SHARED_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Credentials/BrowserCredentialDetailView"
)
MODEL_TESTS = REPOSITORY_ROOT / "CrestTests/BrowserCredentialDetailModelTests.swift"
CLIPBOARD_TESTS = (
    REPOSITORY_ROOT / "CrestTests/BrowserCredentialClipboardTests.swift"
)
VERTICAL_GUARD = runpy.run_path(
    str(REPOSITORY_ROOT / "Scripts/check-vertical-structure.py")
)

SHARED_PRIMARY_OWNERS = {
    "BrowserCredentialDetailView.swift": "BrowserCredentialDetailView",
    "Components/BrowserCredentialDetailContent.swift": (
        "BrowserCredentialDetailContent"
    ),
    "Components/BrowserCredentialAccountSection.swift": (
        "BrowserCredentialAccountSection"
    ),
    "Components/BrowserCredentialErrorSection.swift": (
        "BrowserCredentialErrorSection"
    ),
    "Components/BrowserCredentialPasswordSection/BrowserCredentialPasswordSection.swift": (
        "BrowserCredentialPasswordSection"
    ),
    "Components/BrowserCredentialPasswordSection/Components/BrowserCredentialPasswordActions.swift": (
        "BrowserCredentialPasswordActions"
    ),
    "Components/BrowserCredentialPasswordSection/Components/BrowserCredentialPasswordValue.swift": (
        "BrowserCredentialPasswordValue"
    ),
    "Components/BrowserCredentialPasswordSection/Components/BrowserCredentialCopyConfirmation.swift": (
        "BrowserCredentialCopyConfirmation"
    ),
    "Models/BrowserCredentialDetailModel.swift": "BrowserCredentialDetailModel",
    "Models/BrowserCredentialDetailOperationToken.swift": (
        "BrowserCredentialDetailOperationToken"
    ),
    "Models/BrowserCredentialDetailPresentationIdentity.swift": (
        "BrowserCredentialDetailPresentationIdentity"
    ),
    "Models/BrowserCredentialDetailRequest.swift": (
        "BrowserCredentialDetailRequest"
    ),
    "Models/BrowserCredentialRevealer.swift": "BrowserCredentialRevealer",
    "Models/BrowserCredentialClipboardWriter.swift": (
        "BrowserCredentialClipboardWriter"
    ),
    "Support/BrowserCredentialDetailPreviewFixture.swift": (
        "BrowserCredentialDetailPreviewFixture"
    ),
}

SHARED_EXTENSION_OWNERS = {
    "Support/View+BrowserCredentialDetailSizing.swift": "View",
}

SHARED_VISUAL_OWNERS = {
    path: owner
    for path, owner in SHARED_PRIMARY_OWNERS.items()
    if path == "BrowserCredentialDetailView.swift"
    or path.startswith("Components/")
}

SHARED_PLATFORM_OWNERS = {
    "Components/BrowserPlatformCredentialDetailSizingModifier.swift": (
        "BrowserPlatformCredentialDetailSizingModifier"
    ),
    "Services/BrowserCredentialClipboard.swift": "BrowserCredentialClipboard",
}

MAC_ONLY_OWNERS = {
    "Services/BrowserCredentialPasteboard.swift": "BrowserCredentialPasteboard",
    "Services/BrowserSystemCredentialPasteboard.swift": (
        "BrowserSystemCredentialPasteboard"
    ),
}

PLATFORM_ROOTS = {
    "Crest": REPOSITORY_ROOT / "CrestMac/Features/Credentials",
    "CrestMobile": REPOSITORY_ROOT / "CrestMobile/Features/Credentials",
}

FORBIDDEN_PREVIEW_PATTERNS = {
    "production or sample browser graph": re.compile(
        r"\bBrowser(?:Session|Store)\s*\.\s*(?:preview|production)\b"
    ),
    "persistent state": re.compile(
        r"\b(?:UserDefaults|AppStorage|FileManager|FileHandle|Keychain\w*)\b"
    ),
    "system authentication": re.compile(
        r"\b(?:SystemBrowserDeviceAuthenticator|LAContext)\b"
    ),
    "system clipboard": re.compile(r"\b(?:NSPasteboard|UIPasteboard)\b"),
    "network": re.compile(r"\b(?:URLSession\w*|AsyncImage)\b"),
    "WebKit": re.compile(r"\bWK(?:WebView|WebsiteDataStore)\b"),
    "disk read": re.compile(
        r"\b(?:Data|NSData|NSImage|String|UIImage)\s*\(\s*contentsOf"
    ),
    "UUID()": re.compile(r"\bUUID\s*\(\s*\)"),
    "Date()": re.compile(r"\bDate\s*\(\s*\)"),
    "Date.now": re.compile(r"(?:\bDate\s*\.\s*now\b|(?<!\w)\.now\b)"),
    "random value": re.compile(
        r"(?:\brandom\s*\(|\.\s*(?:random|randomElement|shuffled)\s*\()"
    ),
}


class BrowserCredentialDetailStructureTests(unittest.TestCase):
    def source(self, root: Path, relative_path: str) -> str:
        path = root / relative_path
        self.assertTrue(path.is_file(), str(path))
        return path.read_text()

    def test_exact_vertical_topology_and_obsolete_paths_are_absent(self) -> None:
        expected_sources = set(SHARED_PRIMARY_OWNERS) | set(
            SHARED_EXTENSION_OWNERS
        )
        actual_sources = {
            str(path.relative_to(SHARED_ROOT))
            for path in SHARED_ROOT.rglob("*.swift")
        }
        self.assertEqual(actual_sources, expected_sources)

        for root in PLATFORM_ROOTS.values():
            for relative_path in SHARED_PLATFORM_OWNERS:
                self.assertTrue((root / relative_path).is_file())
        for relative_path in MAC_ONLY_OWNERS:
            self.assertTrue(
                (PLATFORM_ROOTS["Crest"] / relative_path).is_file()
            )
            self.assertFalse(
                (PLATFORM_ROOTS["CrestMobile"] / relative_path).exists()
            )

        obsolete_files = (
            SHARED_ROOT
            / "Extensions/View+BrowserCredentialDetailSizing.swift",
            SHARED_ROOT
            / "Previews/BrowserCredentialDetailViewPreviews.swift",
            SHARED_ROOT / "Components/BrowserCredentialPasswordSection.swift",
            SHARED_ROOT / "Components/BrowserCredentialPasswordValue.swift",
            REPOSITORY_ROOT
            / "CrestMac/Features/Credentials/BrowserCredentialDetailView/BrowserCredentialClipboard.swift",
            REPOSITORY_ROOT
            / "CrestMac/Features/Credentials/BrowserCredentialDetailView/BrowserPlatformCredentialDetailSizingModifier.swift",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Credentials/BrowserCredentialDetailView/BrowserCredentialClipboard.swift",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Credentials/BrowserCredentialDetailView/BrowserPlatformCredentialDetailSizingModifier.swift",
        )
        for path in obsolete_files:
            with self.subTest(path=path):
                self.assertFalse(path.exists(), str(path))

        obsolete_source_roots = (
            SHARED_ROOT / "Extensions",
            SHARED_ROOT / "Previews",
            REPOSITORY_ROOT
            / "CrestMac/Features/Credentials/BrowserCredentialDetailView",
            REPOSITORY_ROOT
            / "CrestMobile/Features/Credentials/BrowserCredentialDetailView",
        )
        for root in obsolete_source_roots:
            with self.subTest(root=root):
                self.assertEqual(list(root.rglob("*.swift")), [])

    def test_every_source_has_one_matching_file_scope_declaration(self) -> None:
        primary_declarations = VERTICAL_GUARD["_primary_declarations"]
        extension_declarations = VERTICAL_GUARD["_top_level_extensions"]
        global_declarations = VERTICAL_GUARD["_top_level_global_content"]

        primary_sources = [
            (SHARED_ROOT, relative_path, owner)
            for relative_path, owner in SHARED_PRIMARY_OWNERS.items()
        ]
        for root in PLATFORM_ROOTS.values():
            primary_sources.extend(
                (root, relative_path, owner)
                for relative_path, owner in SHARED_PLATFORM_OWNERS.items()
            )
        primary_sources.extend(
            (PLATFORM_ROOTS["Crest"], relative_path, owner)
            for relative_path, owner in MAC_ONLY_OWNERS.items()
        )

        for root, relative_path, owner in primary_sources:
            source = self.source(root, relative_path)
            declarations = primary_declarations(source)
            with self.subTest(path=root / relative_path):
                self.assertEqual(len(declarations), 1)
                self.assertEqual(declarations[0].name, owner)
                self.assertEqual(extension_declarations(source), [])
                self.assertEqual(global_declarations(source), [])
                self.assertEqual(Path(relative_path).stem, owner)

        for relative_path, owner in SHARED_EXTENSION_OWNERS.items():
            source = self.source(SHARED_ROOT, relative_path)
            extensions = extension_declarations(source)
            with self.subTest(path=SHARED_ROOT / relative_path):
                self.assertEqual(primary_declarations(source), [])
                self.assertEqual(len(extensions), 1)
                self.assertEqual(extensions[0].target, owner)
                self.assertEqual(global_declarations(source), [])
                self.assertEqual(
                    Path(relative_path).stem.split("+", maxsplit=1)[0],
                    owner,
                )

    def test_root_and_password_section_compose_real_components(self) -> None:
        root = self.source(SHARED_ROOT, "BrowserCredentialDetailView.swift")
        content = self.source(
            SHARED_ROOT,
            "Components/BrowserCredentialDetailContent.swift",
        )
        password = self.source(
            SHARED_ROOT,
            "Components/BrowserCredentialPasswordSection/BrowserCredentialPasswordSection.swift",
        )

        self.assertIn("BrowserCredentialDetailContent(", root)
        self.assertNotIn("BrowserCredentialAccountSection(", root)
        self.assertNotIn("BrowserCredentialPasswordSection(", root)
        self.assertNotRegex(root, r"private\s+(?:var|func)\s+\w+[^\n]*some\s+View")

        for component in (
            "BrowserCredentialAccountSection(",
            "BrowserCredentialPasswordSection(",
            "BrowserCredentialErrorSection(",
        ):
            self.assertIn(component, content)

        for component in (
            "BrowserCredentialPasswordActions(",
            "BrowserCredentialPasswordValue(",
            "BrowserCredentialCopyConfirmation(",
        ):
            self.assertIn(component, password)
        self.assertNotIn("private var revealButton: some View", password)
        self.assertNotIn("private var copyButton: some View", password)

    def test_requests_bind_credential_and_runtime_identity_at_every_caller(self) -> None:
        model = self.source(
            SHARED_ROOT,
            "Models/BrowserCredentialDetailModel.swift",
        )
        request = self.source(
            SHARED_ROOT,
            "Models/BrowserCredentialDetailRequest.swift",
        )
        identity = self.source(
            SHARED_ROOT,
            "Models/BrowserCredentialDetailPresentationIdentity.swift",
        )
        revealer = self.source(
            SHARED_ROOT,
            "Models/BrowserCredentialRevealer.swift",
        )
        token = self.source(
            SHARED_ROOT,
            "Models/BrowserCredentialDetailOperationToken.swift",
        )

        root = self.source(SHARED_ROOT, "BrowserCredentialDetailView.swift")
        shared_caller = (
            REPOSITORY_ROOT
            / "CrestShared/Features/Settings/BrowserPasswordSettingsPane/BrowserPasswordSettingsPane.swift"
        ).read_text()
        mobile_model = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Credentials/MobilePasswordSettingsView/Models/MobilePasswordSettingsModel.swift"
        ).read_text()
        mobile_shell = (
            REPOSITORY_ROOT
            / "CrestMobile/Features/Credentials/MobilePasswordSettingsView/Components/MobilePasswordSettingsPresentationModifier.swift"
        ).read_text()

        for field in (
            "let descriptor: CredentialDescriptor",
            "let spaceAssignment: BrowserSpaceRuntimeAssignment",
            "let spaceName: String",
        ):
            self.assertIn(field, request)
        self.assertIn(
            "var id: BrowserCredentialDetailPresentationIdentity",
            request,
        )
        self.assertIn("credentialID: descriptor.id", request)
        self.assertIn("spaceAssignment: spaceAssignment", request)
        self.assertIn("guard descriptor.spaceID == space.id", request)
        self.assertIn("BrowserSpaceRuntimeAssignment(space: space)", request)
        self.assertIn("let credentialID: CredentialID", identity)
        self.assertIn(
            "let spaceAssignment: BrowserSpaceRuntimeAssignment",
            identity,
        )

        self.assertIn("let request: BrowserCredentialDetailRequest", model)
        self.assertIn("request: BrowserCredentialDetailRequest", root)
        self.assertIn("request: request", root)
        self.assertIn("BrowserSpaceRuntimeAssignment", revealer)
        self.assertIn("CredentialID", revealer)
        self.assertNotIn("(CredentialID, SpaceID", revealer.replace("\n", " "))
        self.assertIn("let assignment: BrowserSpaceRuntimeAssignment", token)
        self.assertIn("let sequence: UInt64", token)

        for caller in (shared_caller, mobile_model):
            with self.subTest(caller="request-construction"):
                self.assertRegex(
                    caller,
                    r"BrowserCredentialDetailRequest\(\s*descriptor:\s*descriptor,\s*space:\s*",
                )
        for shell in (shared_caller, mobile_shell):
            with self.subTest(caller="presentation-identity"):
                self.assertIn(".sheet(item:", shell)
                self.assertIn("request: request", shell)
                self.assertIn(".id(request.id)", shell)

    def test_exact_assignment_and_late_reveal_are_token_guarded(self) -> None:
        model = self.source(
            SHARED_ROOT,
            "Models/BrowserCredentialDetailModel.swift",
        )
        sensitive_access = (
            REPOSITORY_ROOT
            / "CrestShared/Infrastructure/BrowserCredentialSensitiveAccess.swift"
        ).read_text()

        for seam in (
            "spaceAssignment",
            "isAssignmentCurrent",
            "activeOperationToken",
            "activeOperationTask",
            "activeOperationTask?.cancel()",
            "activeOperationToken == token",
            "guard !Task.isCancelled",
            "credentialMatchesRequest",
        ):
            with self.subTest(seam=seam):
                self.assertIn(seam, model)
        self.assertRegex(
            model,
            r"func\s+clearSensitiveState\(\)[^{]*\{[^}]*cancelActiveOperation\(\)",
        )
        self.assertIn(
            "matching assignment: BrowserSpaceRuntimeAssignment",
            sensitive_access,
        )
        self.assertGreaterEqual(
            sensitive_access.count("browser.space(matching: assignment)"),
            3,
        )

        tests = MODEL_TESTS.read_text()
        for test_name in (
            "testRevealForwardsExactCredentialAndRuntimeAssignment",
            "testClearingSensitiveStateRejectsLateRevealCompletion",
            "testDisappearanceRejectsALateCopyBeforeClipboardMutation",
            "testProfileReplacementRejectsRevealCompletion",
            "testPresentationIdentityIncludesCredentialAndRuntimeAssignment",
            "testSensitiveAccessRejectsProfileReplacementDuringAuthentication",
        ):
            with self.subTest(test_name=test_name):
                self.assertIn(f"func {test_name}", tests)

    def test_platform_clipboard_and_layout_semantics_survive_the_move(self) -> None:
        mac_clipboard = self.source(
            PLATFORM_ROOTS["Crest"],
            "Services/BrowserCredentialClipboard.swift",
        )
        pasteboard_port = self.source(
            PLATFORM_ROOTS["Crest"],
            "Services/BrowserCredentialPasteboard.swift",
        )
        system_pasteboard = self.source(
            PLATFORM_ROOTS["Crest"],
            "Services/BrowserSystemCredentialPasteboard.swift",
        )
        mobile_clipboard = self.source(
            PLATFORM_ROOTS["CrestMobile"],
            "Services/BrowserCredentialClipboard.swift",
        )
        mac_sizing = self.source(
            PLATFORM_ROOTS["Crest"],
            "Components/BrowserPlatformCredentialDetailSizingModifier.swift",
        )
        mobile_sizing = self.source(
            PLATFORM_ROOTS["CrestMobile"],
            "Components/BrowserPlatformCredentialDetailSizingModifier.swift",
        )

        for seam in (
            "any BrowserCredentialPasteboard",
            "expirationTask?.cancel()",
            "leasedChangeCount",
            "lease.expiration",
            "NSApplication.willTerminateNotification",
            "clearIfUnchanged()",
        ):
            self.assertIn(seam, mac_clipboard)
        for seam in (
            "var changeCount: Int { get }",
            "writeConcealedTransientString",
            "clearContents()",
        ):
            self.assertIn(seam, pasteboard_port)
        for seam in (
            "NSPasteboard.PasteboardType",
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "pasteboard.declareTypes",
            "pasteboard.setString",
            "pasteboard.clearContents()",
        ):
            self.assertIn(seam, system_pasteboard)
        for seam in (
            "UIPasteboard.general.setItems",
            ".localOnly: true",
            ".expirationDate: lease.expiration",
        ):
            self.assertIn(seam, mobile_clipboard)
        for value in ("minWidth: 380", "idealWidth: 440", "minHeight: 330", "idealHeight: 390"):
            self.assertIn(value, mac_sizing)
        self.assertRegex(mobile_sizing, r"func\s+body\(content:\s*Content\)[^{]*\{\s*content\s*\}")

        clipboard_tests = CLIPBOARD_TESTS.read_text()
        for test_name in (
            "testWriteUsesConcealedTransientPasteboardAndExpiresUnchangedLease",
            "testExpirationPreservesNewerUserPasteboardContents",
            "testNewLeaseCannotBeClearedByOlderExpiration",
            "testTerminationClearsOnlyTheUnchangedLease",
        ):
            with self.subTest(test_name=test_name):
                self.assertIn(f"func {test_name}", clipboard_tests)

    def test_visual_owners_have_direct_deterministic_colocated_previews(self) -> None:
        visual_owners = [
            (SHARED_ROOT, relative_path, owner)
            for relative_path, owner in SHARED_VISUAL_OWNERS.items()
        ]
        for root in PLATFORM_ROOTS.values():
            relative_path = (
                "Components/BrowserPlatformCredentialDetailSizingModifier.swift"
            )
            visual_owners.append(
                (
                    root,
                    relative_path,
                    SHARED_PLATFORM_OWNERS[relative_path],
                )
            )

        for root, relative_path, owner in visual_owners:
            source = self.source(root, relative_path)
            preview_offset = source.rfind("#Preview")
            with self.subTest(path=root / relative_path):
                self.assertGreaterEqual(preview_offset, 0)
                preview = source[preview_offset:]
                self.assertRegex(preview, rf"\b{re.escape(owner)}\s*\(")
                for label, pattern in FORBIDDEN_PREVIEW_PATTERNS.items():
                    self.assertIsNone(pattern.search(preview), label)

        fixture = self.source(
            SHARED_ROOT,
            "Support/BrowserCredentialDetailPreviewFixture.swift",
        )
        for seam in (
            "BrowserSpaceRuntimeAssignment(",
            "SpaceID(",
            "profileID:",
            "UUID(\n",
            "Date(timeIntervalSince1970:",
            "BrowserCredentialDetailModel(",
        ):
            self.assertIn(seam, fixture)
        for label, pattern in FORBIDDEN_PREVIEW_PATTERNS.items():
            self.assertIsNone(pattern.search(fixture), label)
        for forbidden in (
            "BrowserCredentialSensitiveAccess",
            "BrowserCredentialClipboard.write",
        ):
            self.assertNotIn(forbidden, fixture)

    def test_shared_sources_are_in_both_targets_and_platform_sources_are_scoped(self) -> None:
        project = (REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj").read_text()
        shared_paths = {
            (
                "CrestShared/Features/Credentials/BrowserCredentialDetailView/"
                f"{relative_path}"
            )
            for relative_path in set(SHARED_PRIMARY_OWNERS)
            | set(SHARED_EXTENSION_OWNERS)
        }
        mac_paths = {
            f"CrestMac/Features/Credentials/{relative_path}"
            for relative_path in set(SHARED_PLATFORM_OWNERS)
            | set(MAC_ONLY_OWNERS)
        }
        mobile_paths = {
            f"CrestMobile/Features/Credentials/{relative_path}"
            for relative_path in SHARED_PLATFORM_OWNERS
        }
        clipboard_tests_path = "CrestTests/BrowserCredentialClipboardTests.swift"

        mac_sources = self.project_target_source_paths(project, "Crest")
        mobile_sources = self.project_target_source_paths(project, "CrestMobile")
        test_sources = self.project_target_source_paths(project, "CrestTests")
        self.assertLessEqual(shared_paths | mac_paths, mac_sources)
        self.assertLessEqual(shared_paths | mobile_paths, mobile_sources)
        self.assertTrue(mac_paths.isdisjoint(mobile_sources))
        self.assertTrue(mobile_paths.isdisjoint(mac_sources))
        self.assertIn(clipboard_tests_path, test_sources)
        self.assertNotIn(clipboard_tests_path, mac_sources)
        self.assertNotIn(clipboard_tests_path, mobile_sources)

        self.assertNotIn("BrowserCredentialDetailViewPreviews.swift", project)

    def test_slice_removes_exactly_fourteen_debts_from_the_444_baseline(self) -> None:
        debt = json.loads(
            (REPOSITORY_ROOT / "Config/VerticalStructureDebt.json").read_text()
        )
        violations = [
            (rule, violation)
            for rule, body in debt["rules"].items()
            for violation in body["violations"]
        ]
        self.assertEqual(444 - 14, 430)
        self.assertEqual(len(violations), 0)

        owned_filenames = {
            Path(path).name
            for path in set(SHARED_PRIMARY_OWNERS)
            | set(SHARED_EXTENSION_OWNERS)
            | set(SHARED_PLATFORM_OWNERS)
            | set(MAC_ONLY_OWNERS)
        }
        remaining = [
            entry
            for entry in violations
            if "BrowserCredentialDetailView" in entry[1][0]
            or Path(entry[1][0]).name in owned_filenames
        ]
        self.assertEqual(remaining, [])

    def project_target_source_paths(self, project: str, target: str) -> set[str]:
        file_references = {
            match.group("id"): self.pbx_value(match.group("body"), "path")
            for match in re.finditer(
                r"^\t\t(?P<id>[0-9A-F]{24}) /\* .*? \*/ = "
                r"\{isa = PBXFileReference;(?P<body>.*?)\};$",
                project,
                re.MULTILINE,
            )
        }
        groups: dict[str, str] = {}
        parent_by_child: dict[str, str] = {}
        for match in re.finditer(
            r"^\t\t(?P<id>[0-9A-F]{24}) /\* (?P<label>.*?) \*/ = \{\n"
            r"\t\t\tisa = PBXGroup;\n"
            r"(?P<body>.*?)^\t\t\};",
            project,
            re.MULTILINE | re.DOTALL,
        ):
            group_id = match.group("id")
            body = match.group("body")
            groups[group_id] = (
                self.pbx_value(body, "path")
                or self.pbx_value(body, "name")
                or match.group("label")
            )
            children_match = re.search(
                r"children = \((?P<children>.*?)\n\t\t\t\);",
                body,
                re.DOTALL,
            )
            if children_match is None:
                continue
            for child_id in re.findall(
                r"\b[0-9A-F]{24}\b",
                children_match.group("children"),
            ):
                parent_by_child[child_id] = group_id

        main_group_match = re.search(
            r"\bmainGroup = (?P<id>[0-9A-F]{24})",
            project,
        )
        self.assertIsNotNone(main_group_match)
        main_group_id = main_group_match.group("id")
        resolved_paths = {
            file_id: self.resolve_file_reference_path(
                file_path,
                file_id,
                main_group_id,
                groups,
                parent_by_child,
            )
            for file_id, file_path in file_references.items()
            if file_path is not None
        }
        build_file_references = {
            match.group("build"): match.group("reference")
            for match in re.finditer(
                r"^\t\t(?P<build>[0-9A-F]{24}) /\* .*? in Sources \*/ = "
                r"\{isa = PBXBuildFile; fileRef = "
                r"(?P<reference>[0-9A-F]{24})",
                project,
                re.MULTILINE,
            )
        }

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
        build_file_ids = re.findall(
            r"\b[0-9A-F]{24}\b",
            phase_match.group("body"),
        )
        return {
            resolved_paths[build_file_references[build_file_id]]
            for build_file_id in build_file_ids
            if build_file_id in build_file_references
            and build_file_references[build_file_id] in resolved_paths
        }

    def resolve_file_reference_path(
        self,
        file_path: str,
        file_id: str,
        main_group_id: str,
        groups: dict[str, str],
        parent_by_child: dict[str, str],
    ) -> str:
        components = [file_path]
        group_id = parent_by_child.get(file_id)
        visited: set[str] = set()
        while group_id is not None and group_id != main_group_id:
            self.assertNotIn(group_id, visited)
            visited.add(group_id)
            component = groups.get(group_id)
            if component not in (None, "", "."):
                components.append(component)
            group_id = parent_by_child.get(group_id)
        return Path(*reversed(components)).as_posix()

    def pbx_value(self, body: str, key: str) -> str | None:
        match = re.search(
            rf"\b{re.escape(key)} = (?P<value>\"(?:\\.|[^\"])*\"|[^;]+);",
            body,
        )
        if match is None:
            return None
        value = match.group("value").strip()
        if value.startswith('"') and value.endswith('"'):
            return value[1:-1].replace(r'\"', '"')
        return value


if __name__ == "__main__":
    unittest.main()
