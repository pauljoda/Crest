#!/usr/bin/env python3
"""Vertical and safety contracts for the shared tab-favicon family."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FAMILY_ROOT = REPOSITORY_ROOT / "CrestShared/Features/Tabs/TabFaviconView"
FALLBACK_ROOT = REPOSITORY_ROOT / "CrestShared/Infrastructure"
# `BrowserTab` stores the fingerprint, so the identity type owns it from Domain
# rather than from this feature slice.
PAYLOAD_IDENTITY_PATH = (
    REPOSITORY_ROOT
    / "CrestShared/Domain/BrowserTab/Icons/BrowserFaviconPayloadIdentity.swift"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class TabFaviconViewStructureTests(unittest.TestCase):
    def test_family_has_only_the_contract_compliant_vertical_topology(self) -> None:
        expected_files = {
            "TabFaviconView.swift",
            "Components/TabFaviconContent.swift",
            "Components/CrestStartPageMark/CrestStartPageMark.swift",
            "Components/CrestStartPageMark/Components/CrestBannerShape.swift",
            "Components/CrestStartPageMark/Components/CrestButterPlaneShape.swift",
            "Components/CrestStartPageMark/Components/CrestSkyPlaneShape.swift",
            "Components/CrestStartPageMark/Models/CrestStartPageMarkMetrics.swift",
            "Components/CrestStartPageMark/Models/CrestStartPageMarkPalette.swift",
            "Models/BrowserFaviconImageCacheKey.swift",
            "Models/BrowserFaviconImageCacheRequestLease.swift",
            "Models/BrowserFaviconImageCacheRequestRegistry.swift",
            "Models/BrowserFaviconImageCacheRequestToken.swift",
            "Models/BrowserFaviconRenderRequest.swift",
            "Models/BrowserFaviconRenderState.swift",
            "Models/BrowserFaviconRenderedImage.swift",
            "Models/BrowserFaviconTaskIdentity.swift",
            "Models/TabFaviconMetrics.swift",
            "Services/BrowserFaviconImageCache.swift",
            "Services/BrowserFaviconImageDecoder.swift",
            "Services/BrowserFaviconRenderLoader.swift",
            "Support/BrowserFaviconTaskIdentityPolicy.swift",
            "Support/TabFaviconPreviewFixture.swift",
        }
        actual_files = {
            str(path.relative_to(FAMILY_ROOT))
            for path in FAMILY_ROOT.rglob("*.swift")
        }

        self.assertEqual(actual_files, expected_files)
        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Features/Tabs/TabFaviconView.swift").exists()
        )
        for obsolete_role in (
            "Caching",
            "Decoding",
            "Metrics",
            "Palette",
            "Policies",
            "Previews",
            "Shapes",
        ):
            with self.subTest(obsolete_role=obsolete_role):
                self.assertFalse(any(
                    path.name == obsolete_role and path.is_dir()
                    for path in FAMILY_ROOT.rglob("*")
                ))

    def test_every_source_has_one_matching_file_scope_declaration(self) -> None:
        sources = list(FAMILY_ROOT.rglob("*.swift")) + [
            FALLBACK_ROOT / "BrowserFaviconFallbackCacheKey.swift",
            FALLBACK_ROOT / "BrowserFaviconFallbackLoader.swift",
            FALLBACK_ROOT / "BrowserFaviconFallbackRequestLease.swift",
            FALLBACK_ROOT / "BrowserFaviconFallbackRequestToken.swift",
        ]

        for path in sources:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
                self.assertEqual(
                    DECLARATION_PATTERN.findall(path.read_text()),
                    [path.stem],
                )

    def test_root_composes_content_and_qualifies_rendered_state_by_request(self) -> None:
        source = (FAMILY_ROOT / "TabFaviconView.swift").read_text()

        self.assertIn("TabFaviconContent(", source)
        self.assertIn("BrowserFaviconTaskIdentityPolicy.renderRequest", source)
        self.assertIn("BrowserFaviconRenderState()", source)
        self.assertIn(".task(id: request.identity)", source)
        self.assertIn("guard !Task.isCancelled", source)
        self.assertNotIn("renderState.renderedImage = nil", source)
        self.assertNotIn("if tab.isStartPage", source)
        self.assertNotIn("BrowserFaviconFallbackLoader.shared.data", source)

        content = (FAMILY_ROOT / "Components/TabFaviconContent.swift").read_text()
        self.assertIn("renderedImage?.image(matching: requestIdentity)", content)
        self.assertLessEqual(len(content.splitlines()), 50)

    def test_payload_and_task_identity_are_exact_and_complete(self) -> None:
        # The identity owns a fixed-size digest of the payload, not the payload.
        # SwiftUI evaluates task identities and compares view values during view
        # updates, so holding the bytes hashed a whole image on the main actor
        # once per visible tab row; sampling fixed offsets was constant work but
        # could alias two different icons. The digest is exact *and* constant
        # work, and it lives beside `BrowserTab`, which computes it once when the
        # bytes are assigned.
        payload = (PAYLOAD_IDENTITY_PATH).read_text()
        task = (FAMILY_ROOT / "Models/BrowserFaviconTaskIdentity.swift").read_text()
        policy = (
            FAMILY_ROOT / "Support/BrowserFaviconTaskIdentityPolicy.swift"
        ).read_text()
        cache = (FAMILY_ROOT / "Services/BrowserFaviconImageCache.swift").read_text()

        self.assertIn("SHA256Digest", payload)
        self.assertNotIn("let data: Data", payload)
        for sampled_field in (
            "firstWord",
            "firstThirdWord",
            "secondThirdWord",
            "lastWord",
            "withUnsafeBytes",
        ):
            self.assertNotIn(sampled_field, payload)
        self.assertIn("BrowserFaviconPayloadIdentity(hashing: data)", cache)
        # The render path reads the stored fingerprint instead of the bytes.
        self.assertIn("displayFaviconPayloadIdentity", policy)

        for field in (
            "tabID",
            "profileID",
            "pageURL",
            "iconMode",
            "payload",
            "maximumPixelSize",
        ):
            with self.subTest(field=field):
                self.assertRegex(task, rf"let {field}:")
                self.assertIn(f"{field}:", policy)

    def test_start_page_and_emoji_requests_cannot_reach_network_fallback(self) -> None:
        policy = (
            FAMILY_ROOT / "Support/BrowserFaviconTaskIdentityPolicy.swift"
        ).read_text()
        loader = (
            FAMILY_ROOT / "Services/BrowserFaviconRenderLoader.swift"
        ).read_text()

        self.assertIn("guard !tab.isStartPage, tab.emojiIcon == nil", policy)
        self.assertIn("fallbackPageURL: nil", policy)
        self.assertIn("fallbackProfileID: nil", policy)
        self.assertIn("request.fallbackPageURL", loader)
        self.assertIn("request.fallbackProfileID", loader)
        self.assertNotIn("BrowserTab", loader)

    def test_decode_is_off_main_bounded_coalesced_and_exactly_cached(self) -> None:
        decoder = (
            FAMILY_ROOT / "Services/BrowserFaviconImageDecoder.swift"
        ).read_text()
        cache = (FAMILY_ROOT / "Services/BrowserFaviconImageCache.swift").read_text()
        registry = (
            FAMILY_ROOT / "Models/BrowserFaviconImageCacheRequestRegistry.swift"
        ).read_text()

        self.assertIn("BrowserFaviconImageCache.shared", decoder)
        self.assertIn("actor BrowserFaviconImageCache", cache)
        self.assertIn("inFlight", registry)
        self.assertIn("maximumCachedImageCount", cache)
        self.assertIn("Task.detached(priority: .utility)", cache)
        self.assertIn("BrowserFaviconImageCacheKey", cache)
        self.assertNotIn("struct Key", cache)
        self.assertIn("BrowserFaviconImageCacheRequestLease", registry)
        self.assertIn("BrowserFaviconImageCacheRequestToken", registry)
        self.assertIn("requests.complete(lease, for: key)", cache)
        self.assertIn("requests.isCurrent(lease)", cache)
        self.assertIn("inFlight[key]?.token == lease.token", registry)
        self.assertIn("lease.token.generation == generation", registry)

        state = (FAMILY_ROOT / "Models/BrowserFaviconRenderState.swift").read_text()
        self.assertIn("guard !isCancelled", state)
        self.assertIn("activeRequestIdentity == requestIdentity", state)
        self.assertNotIn("renderedImage = nil", state)

    def test_profile_invalidation_uses_external_key_lease_and_generation_token(self) -> None:
        loader = (
            FALLBACK_ROOT / "BrowserFaviconFallbackLoader.swift"
        ).read_text()
        key = (
            FALLBACK_ROOT / "BrowserFaviconFallbackCacheKey.swift"
        ).read_text()
        lease = (
            FALLBACK_ROOT / "BrowserFaviconFallbackRequestLease.swift"
        ).read_text()
        token = (
            FALLBACK_ROOT / "BrowserFaviconFallbackRequestToken.swift"
        ).read_text()

        self.assertIn("let profileID: UUID", key)
        self.assertIn("let iconURL: URL", key)
        self.assertIn("let token: BrowserFaviconFallbackRequestToken", lease)
        self.assertIn("let task: Task<Data?, Never>", lease)
        self.assertIn("let profileGeneration: UInt64", token)
        self.assertIn("let requestID: UInt64", token)
        self.assertIn("profileGenerations", loader)
        self.assertIn("nextRequestID", loader)
        self.assertIn("activeLease.token == lease.token", loader)
        self.assertIn("currentGeneration(for: profileID)", loader)
        self.assertNotIn("struct CacheKey", loader)

    def test_shared_sources_are_platform_agnostic(self) -> None:
        for source_path in FAMILY_ROOT.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(source=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("#if os(", source)

    def test_each_visual_owner_has_a_direct_deterministic_preview(self) -> None:
        owners = {
            "TabFaviconView.swift": "TabFaviconView",
            "Components/TabFaviconContent.swift": "TabFaviconContent",
            "Components/CrestStartPageMark/CrestStartPageMark.swift":
                "CrestStartPageMark",
            "Components/CrestStartPageMark/Components/CrestBannerShape.swift":
                "CrestBannerShape",
            "Components/CrestStartPageMark/Components/CrestButterPlaneShape.swift":
                "CrestButterPlaneShape",
            "Components/CrestStartPageMark/Components/CrestSkyPlaneShape.swift":
                "CrestSkyPlaneShape",
        }
        for relative_path, owner in owners.items():
            source = (FAMILY_ROOT / relative_path).read_text()
            with self.subTest(relative_path=relative_path):
                self.assertIn("#Preview", source)
                preview_source = source[source.index("#Preview"):]
                self.assertIn(f"{owner}(", preview_source)

        root = (FAMILY_ROOT / "TabFaviconView.swift").read_text()
        for name in ("Start Page", "Emoji", "Image", "Fallback"):
            self.assertIn(f'#Preview("Tab Favicon — {name}")', root)

        fixture = (FAMILY_ROOT / "Support/TabFaviconPreviewFixture.swift").read_text()
        self.assertIn("Data([", fixture)
        for forbidden in (
            "http://",
            "https://",
            "BrowserSession.preview",
            "UserDefaults",
            "FileManager",
            "URLSession",
            "WKWebView",
            "UUID()",
            "Date.now",
            "Date()",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, fixture)

    def test_all_shared_sources_belong_to_both_app_source_phases(self) -> None:
        project = (REPOSITORY_ROOT / "Crest.xcodeproj/project.pbxproj").read_text()
        expected_filenames = {
            path.name for path in FAMILY_ROOT.rglob("*.swift")
        } | {
            "BrowserFaviconFallbackCacheKey.swift",
            "BrowserFaviconFallbackLoader.swift",
            "BrowserFaviconFallbackRequestLease.swift",
            "BrowserFaviconFallbackRequestToken.swift",
        }

        for target in ("Crest", "CrestMobile"):
            target_sources = self.project_target_sources(project, target)
            for filename in expected_filenames:
                with self.subTest(target=target, filename=filename):
                    self.assertIn(filename, target_sources)

    def test_slice_has_zero_debt_and_exact_repository_total(self) -> None:
        debt = json.loads(
            (REPOSITORY_ROOT / "Config/VerticalStructureDebt.json").read_text()
        )
        violations = [
            (rule, violation)
            for rule, body in debt["rules"].items()
            for violation in body["violations"]
        ]
        self.assertEqual(len(violations), 0)
        self.assertEqual(
            [
                entry
                for entry in violations
                if "TabFaviconView" in entry[1][0]
                or "BrowserFaviconFallbackLoader" in entry[1][0]
            ],
            [],
        )

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


if __name__ == "__main__":
    unittest.main()
