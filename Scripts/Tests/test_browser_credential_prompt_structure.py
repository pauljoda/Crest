#!/usr/bin/env python3
"""Structural ownership contract for credential prompt presentation."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
APPLICATION_MODELS = REPOSITORY_ROOT / "CrestShared/Application/Credentials/Models"
PRESENTATION_ROOT = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Credentials/Models"
)
MAC_PROMPT = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Credentials/BrowserCredentialSaveBanner/BrowserCredentialSaveBanner.swift"
)
MOBILE_PROMPT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Credentials/MobileCredentialSavePrompt/MobileCredentialSavePrompt.swift"
)
MOBILE_CHROME_ROOT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Credentials/MobileBrowserCredentialChrome"
)

EXPECTED_MOBILE_CHROME_VIEWS = {
    "MobileBrowserCredentialChrome": "MobileBrowserCredentialChrome.swift",
    "MobileCredentialPromptSurface": (
        "Components/MobileCredentialPromptSurface.swift"
    ),
    "MobileCredentialPromptHeader": (
        "Components/MobileCredentialPromptHeader.swift"
    ),
    "MobileCredentialCrossOriginNotice": (
        "Components/MobileCredentialCrossOriginNotice.swift"
    ),
    "MobileCredentialPromptError": (
        "Components/MobileCredentialPromptError.swift"
    ),
    "MobileStrongPasswordPrompt": (
        "Components/MobileStrongPasswordPrompt/"
        "MobileStrongPasswordPrompt.swift"
    ),
    "MobileStrongPasswordPromptContent": (
        "Components/MobileStrongPasswordPrompt/Components/"
        "MobileStrongPasswordPromptContent.swift"
    ),
    "MobileStrongPasswordActionButton": (
        "Components/MobileStrongPasswordPrompt/Components/"
        "MobileStrongPasswordActionButton.swift"
    ),
    "MobileStrongPasswordExplanation": (
        "Components/MobileStrongPasswordPrompt/Components/"
        "MobileStrongPasswordExplanation.swift"
    ),
    "MobileCredentialSuggestionPrompt": (
        "Components/MobileCredentialSuggestionPrompt/"
        "MobileCredentialSuggestionPrompt.swift"
    ),
    "MobileCredentialSuggestionPromptContent": (
        "Components/MobileCredentialSuggestionPrompt/Components/"
        "MobileCredentialSuggestionPromptContent.swift"
    ),
    "MobileCredentialSuggestionState": (
        "Components/MobileCredentialSuggestionPrompt/Components/"
        "MobileCredentialSuggestionState.swift"
    ),
    "MobileCredentialSuggestionList": (
        "Components/MobileCredentialSuggestionPrompt/Components/"
        "MobileCredentialSuggestionList.swift"
    ),
    "MobileCredentialSuggestionRow": (
        "Components/MobileCredentialSuggestionPrompt/Components/"
        "MobileCredentialSuggestionRow.swift"
    ),
    "MobileCredentialSuggestionFeedback": (
        "Components/MobileCredentialSuggestionPrompt/Components/"
        "MobileCredentialSuggestionFeedback.swift"
    ),
}

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserCredentialPromptStructureTests(unittest.TestCase):
    def test_credential_application_models_use_one_matching_owner_per_file(self) -> None:
        required_files = (
            "BrowserCredentialFillError.swift",
            "BrowserCredentialPageState.swift",
            "BrowserCredentialSavePromptAction.swift",
            "BrowserCredentialSavePromptFailure.swift",
            "BrowserCredentialSavePromptModel.swift",
            "BrowserCredentialSavePromptPhase.swift",
            "BrowserCredentialSuggestionModel.swift",
            "BrowserStrongPasswordOperationModel.swift",
            "BrowserSystemPasswordOfferPhase.swift",
        )
        for filename in required_files:
            with self.subTest(filename=filename):
                self.assertTrue((APPLICATION_MODELS / filename).is_file())

        for source_path in APPLICATION_MODELS.rglob("*.swift"):
            declarations = DECLARATION_PATTERN.findall(source_path.read_text())
            with self.subTest(path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, [source_path.stem])

        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Application/BrowserCredentialPageState.swift").exists()
        )

    def test_application_credential_models_remain_platform_neutral(self) -> None:
        forbidden_imports = ("AppKit", "SwiftUI", "UIKit", "WebKit")
        for source_path in APPLICATION_MODELS.rglob("*.swift"):
            source = source_path.read_text()
            with self.subTest(path=source_path.relative_to(REPOSITORY_ROOT)):
                for module in forbidden_imports:
                    self.assertNotIn(f"import {module}", source)

        model_source = (
            APPLICATION_MODELS / "BrowserCredentialSavePromptModel.swift"
        ).read_text()
        self.assertIn("private var candidateID: UUID?", model_source)
        self.assertNotIn("BrowserCredentialSaveCandidate?", model_source)

    def test_shared_route_owns_phase_copy_and_action_mapping(self) -> None:
        route_path = PRESENTATION_ROOT / "BrowserCredentialPromptRoute.swift"
        presentation_path = (
            PRESENTATION_ROOT / "BrowserCredentialPromptRoute+Presentation.swift"
        )
        self.assertTrue(route_path.is_file())
        self.assertTrue(presentation_path.is_file())
        route_source = route_path.read_text()
        presentation_source = presentation_path.read_text()
        self.assertEqual(
            DECLARATION_PATTERN.findall(route_source),
            ["BrowserCredentialPromptRoute"],
        )
        self.assertIn("LocalizedStringResource", presentation_source)
        primary_action_source = (
            PRESENTATION_ROOT / "BrowserCredentialPromptPrimaryAction.swift"
        ).read_text()
        self.assertIn("case retrySystemPasswords", primary_action_source)
        self.assertIn("func crossOriginMessage", presentation_source)
        self.assertIn("extension BrowserCredentialPromptRoute", presentation_source)
        for module in ("AppKit", "SwiftUI", "UIKit", "WebKit"):
            self.assertNotIn(f"import {module}", route_source)
            self.assertNotIn(f"import {module}", presentation_source)

    def test_platform_views_dispatch_typed_actions_without_phase_switches(self) -> None:
        self.assertTrue(MAC_PROMPT.is_file())
        self.assertTrue(MOBILE_PROMPT.is_file())

        for source_path, type_name in (
            (MAC_PROMPT, "BrowserCredentialSaveBanner"),
            (MOBILE_PROMPT, "MobileCredentialSavePrompt"),
        ):
            source = source_path.read_text()
            with self.subTest(path=source_path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(DECLARATION_PATTERN.findall(source), [type_name])
                self.assertIn("BrowserCredentialPromptRoute(", source)
                self.assertIn("private func perform(", source)
                self.assertNotIn("switch model.phase", source)
                self.assertNotIn("private var promptTitle", source)
                self.assertNotIn("private var errorMessage", source)

        self.assertNotIn("BrowserSystemPasswordWriteThroughSystem", MAC_PROMPT.read_text())
        self.assertIn("BrowserSystemPasswordWriteThroughSystem", MOBILE_PROMPT.read_text())

        mac_chrome = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Credentials/Components/BrowserCredentialChrome/BrowserCredentialChrome.swift"
        ).read_text()
        mobile_chrome = (
            MOBILE_CHROME_ROOT / "MobileBrowserCredentialChrome.swift"
        ).read_text()
        self.assertNotIn("struct BrowserCredentialSaveBanner", mac_chrome)
        self.assertNotIn("struct MobileCredentialSavePrompt", mobile_chrome)

    def test_mobile_credential_chrome_is_a_previewed_component_family(self) -> None:
        for type_name, relative_path in EXPECTED_MOBILE_CHROME_VIEWS.items():
            with self.subTest(type_name=type_name):
                path = MOBILE_CHROME_ROOT / relative_path
                self.assertTrue(path.is_file(), path)
                source = path.read_text()
                self.assertEqual(DECLARATION_PATTERN.findall(source), [type_name])
                self.assertIn("#Preview", source)
                self.assertIn(f"{type_name}(", source)

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestMobile/Features/Credentials/"
                "MobileBrowserCredentialChrome.swift"
            ).exists()
        )

    def test_mobile_credential_previews_are_fixed_and_nonpersistent(self) -> None:
        fixture = (
            MOBILE_CHROME_ROOT
            / "Support/MobileBrowserCredentialChromePreviewFixture.swift"
        ).read_text()

        self.assertEqual(
            DECLARATION_PATTERN.findall(fixture),
            ["MobileBrowserCredentialChromePreviewFixture"],
        )
        self.assertIn("UUID(\n        uuid:", fixture)
        self.assertIn("Date(timeIntervalSince1970:", fixture)
        self.assertIn("InMemoryBrowserSessionPersistence()", fixture)
        self.assertIn("WKWebsiteDataStore.nonPersistent()", fixture)
        self.assertIn("loadsInitialURL: false", fixture)
        self.assertNotIn("UUID()", fixture)
        self.assertNotIn("UserDefaults", fixture)
        self.assertNotIn(".production(", fixture)

        header_kind = (
            MOBILE_CHROME_ROOT
            / "Models/MobileCredentialPromptHeaderKind.swift"
        ).read_text()
        self.assertEqual(
            DECLARATION_PATTERN.findall(header_kind),
            ["MobileCredentialPromptHeaderKind"],
        )


if __name__ == "__main__":
    unittest.main()
