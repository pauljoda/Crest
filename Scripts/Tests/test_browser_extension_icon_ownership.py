#!/usr/bin/env python3
"""Ownership contracts for asynchronous WebExtension icon decoding."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserExtensions"
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserExtensions"
)
FEATURE_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Extensions/BrowserExtensionsView"
)
VIEW_PATH = FEATURE_ROOT / "Components/BrowserExtensionIconView.swift"
PRODUCTION_ROOTS = tuple(
    REPOSITORY_ROOT / name for name in ("CrestShared", "CrestMac", "CrestMobile")
)


def production_swift_sources() -> list[Path]:
    return [
        path
        for root in PRODUCTION_ROOTS
        for path in root.rglob("*.swift")
    ]


def call_arguments(source: str, call_name: str) -> list[str]:
    marker = f"{call_name}("
    results: list[str] = []
    search_start = 0
    while (call_start := source.find(marker, search_start)) >= 0:
        argument_start = call_start + len(marker)
        depth = 1
        index = argument_start
        in_string = False
        escaped = False
        while index < len(source) and depth > 0:
            character = source[index]
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            index += 1
        if depth != 0:
            raise AssertionError(f"Unbalanced {call_name} call")
        results.append(source[argument_start : index - 1])
        search_start = index
    return results


class BrowserExtensionIconOwnershipTests(unittest.TestCase):
    def test_decoder_port_cache_and_image_pipeline_have_explicit_owners(self) -> None:
        required_paths = (
            APPLICATION_ROOT / "BrowserExtensionIconDecoder.swift",
            APPLICATION_ROOT / "Models/BrowserExtensionIconContentIdentifier.swift",
            APPLICATION_ROOT / "Models/BrowserExtensionIconPayload.swift",
            APPLICATION_ROOT / "Models/BrowserExtensionIconRequest.swift",
            APPLICATION_ROOT / "Models/BrowserExtensionIconRequestIdentity.swift",
            APPLICATION_ROOT / "Ports/BrowserExtensionIconDecoding.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionIconPayloadFactory.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionIconEncodedDataValidator.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionIconImageIOAdapter.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionIconDecoder+Production.swift",
            INFRASTRUCTURE_ROOT / "BrowserExtensionIconDecoderProduction.swift",
            FEATURE_ROOT / "Models/BrowserExtensionIconRenderState.swift",
        )
        for path in required_paths:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        decoder = required_paths[0].read_text()
        self.assertIn("actor BrowserExtensionIconDecoder", decoder)
        self.assertIn("Task.detached", decoder)
        self.assertIn("inFlight", decoder)
        self.assertIn("maximumCachedIconCount", decoder)
        self.assertIn("request.payload", decoder)
        self.assertIn("let generation: UUID", decoder)
        self.assertIn(
            "guard inFlight[key]?.generation == entry.generation",
            decoder,
        )
        self.assertNotRegex(
            decoder,
            r"struct CacheKey[\s\S]*?\blet\s+\w*data\s*:\s*Data",
        )

        factory = required_paths[6].read_text()
        self.assertIn("import CryptoKit", factory)
        self.assertIn("SHA256.hash", factory)
        self.assertIn("private init(", factory)
        self.assertIn("testingValidate:", factory)
        self.assertNotRegex(factory, r"validate:\s*@escaping Validate\s*=")
        self.assertLess(
            factory.index("data.count <= BrowserExtensionIconPayload.maximumEncodedByteCount"),
            factory.index("identifier(data)"),
        )

        validator = required_paths[7].read_text()
        self.assertIn("import ImageIO", validator)
        self.assertIn("CGImageSourceGetStatus(source) == .statusComplete", validator)

        self.assertLess(
            factory.index("data.count <= BrowserExtensionIconPayload.maximumEncodedByteCount"),
            factory.index("validate(data)"),
        )
        self.assertLess(factory.index("validate(data)"), factory.index("identifier(data)"))

        adapter = required_paths[8].read_text()
        self.assertIn("import ImageIO", adapter)
        self.assertIn("CGImageSourceCreateThumbnailAtIndex", adapter)

    def test_application_icon_pipeline_is_foundation_only(self) -> None:
        icon_paths = tuple(
            APPLICATION_ROOT.rglob("BrowserExtensionIcon*.swift")
        )
        self.assertGreaterEqual(len(icon_paths), 5)
        for path in icon_paths:
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                for forbidden in (
                    "import AppKit",
                    "import CoreGraphics",
                    "import CryptoKit",
                    "import ImageIO",
                    "import SwiftUI",
                    "import UIKit",
                ):
                    self.assertNotIn(forbidden, source)

    def test_content_identifier_and_cache_keys_never_retain_encoded_data(self) -> None:
        identifier_source = (
            APPLICATION_ROOT
            / "Models/BrowserExtensionIconContentIdentifier.swift"
        ).read_text()
        self.assertNotIn("Data", identifier_source)
        self.assertEqual(len(re.findall(r"private let \w+Word: UInt64", identifier_source)), 4)
        self.assertIn("static let digestByteCount = 32", identifier_source)

        identity = (
            APPLICATION_ROOT / "Models/BrowserExtensionIconRequestIdentity.swift"
        ).read_text()
        self.assertIn("contentIdentifier", identity)
        self.assertIn("extensionID", identity)
        self.assertIn("spaceID", identity)
        self.assertNotIn("Data", identity)

        decoder_source = (
            APPLICATION_ROOT / "BrowserExtensionIconDecoder.swift"
        ).read_text()
        self.assertIn(
            "typealias CacheKey = BrowserExtensionIconRequestIdentity",
            decoder_source,
        )

    def test_swiftui_view_only_maps_identity_gated_decoded_artwork(self) -> None:
        source = VIEW_PATH.read_text()
        for forbidden in (
            "import AppKit",
            "import CryptoKit",
            "import ImageIO",
            "import UIKit",
            "#if os(",
            "Data",
            "BrowserExtensionIconPayloadFactory",
            "NSImage(data:",
            "UIImage(data:",
            "CGImageSourceCreate",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)

        for required in (
            "@State private var renderState",
            "renderState.icon(for: request.identity)",
            ".task(id: request.identity)",
            "guard !Task.isCancelled else { return }",
            "renderState.store(icon, for: identity)",
            'Image(systemName: "puzzlepiece.extension.fill")',
            "extensionIconCornerRadiusRatio",
            "extensionIconFallbackPaddingRatio",
        ):
            with self.subTest(required=required):
                self.assertIn(required, source)

    def test_all_production_swiftui_files_avoid_inline_image_decoding_and_hashing(
        self,
    ) -> None:
        forbidden_operations = (
            "NSImage(data:",
            "UIImage(data:",
            "CGImageSourceCreate",
            "SHA256.hash",
            "BrowserExtensionIconPayloadFactory",
        )
        for path in production_swift_sources():
            source = path.read_text()
            if "import SwiftUI" not in source or "Previews" in path.parts:
                continue
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                for forbidden in forbidden_operations:
                    self.assertNotIn(forbidden, source)

    def test_every_icon_consumer_supplies_precomputed_payload_and_scope(self) -> None:
        consumers_found = 0
        for path in production_swift_sources():
            source = path.read_text()
            if path.name != "BrowserExtensionIconPayloadFactory.swift":
                self.assertNotIn("BrowserExtensionIconPayloadFactory(", source)
            calls = call_arguments(source, "BrowserExtensionIconView")
            for arguments in calls:
                consumers_found += 1
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertIn("extensionID:", arguments)
                    self.assertIn("spaceID:", arguments)
                    self.assertIn("payload:", arguments)
        self.assertGreaterEqual(consumers_found, 4)

    def test_persisted_icon_cap_has_one_typed_owner(self) -> None:
        registry = (
            REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserExtensionRegistry.swift"
        ).read_text()
        self.assertIn(
            "BrowserExtensionIconPayload.maximumEncodedByteCount",
            registry,
        )
        self.assertNotIn("iconData.count <= 1_048_576", registry)


if __name__ == "__main__":
    unittest.main()
