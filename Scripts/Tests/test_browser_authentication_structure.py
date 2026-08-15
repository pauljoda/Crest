#!/usr/bin/env python3
"""Structural contracts for HTTP authentication ownership."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserAuthentication"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserAuthentication"
INFRASTRUCTURE_ROOT = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserAuthentication"
)

DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserAuthenticationStructureTests(unittest.TestCase):
    def test_authentication_owners_use_focused_matching_files(self) -> None:
        required_files = (
            DOMAIN_ROOT / "Models/BrowserAuthenticationChallenge.swift",
            DOMAIN_ROOT / "Models/BrowserAuthenticationHandling.swift",
            DOMAIN_ROOT / "Models/BrowserAuthenticationMethod.swift",
            DOMAIN_ROOT / "Models/BrowserHTTPAuthenticationDecision.swift",
            DOMAIN_ROOT / "Models/BrowserHTTPAuthenticationDescriptor.swift",
            DOMAIN_ROOT / "Models/BrowserHTTPAuthenticationPrompt.swift",
            DOMAIN_ROOT / "Models/BrowserHTTPAuthenticationPromptResponse.swift",
            DOMAIN_ROOT / "Models/BrowserHTTPAuthenticationProtectionSpace.swift",
            DOMAIN_ROOT / "Models/BrowserHTTPAuthenticationSaveRequest.swift",
            DOMAIN_ROOT / "Policies/BrowserAuthenticationPolicy.swift",
            DOMAIN_ROOT / "Policies/BrowserHTTPAuthenticationSourcePolicy.swift",
            DOMAIN_ROOT / "Policies/BrowserPhysicalValidationTrustPolicy.swift",
            APPLICATION_ROOT / "BrowserHTTPAuthenticationSession.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserAuthenticationChallenge+URLAuthenticationChallenge.swift",
            INFRASTRUCTURE_ROOT / "BrowserAuthenticationMethod+Foundation.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserAuthenticationPolicy+URLAuthenticationChallenge.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserHTTPAuthenticationDescriptor+URLAuthenticationChallenge.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserHTTPAuthenticationProtectionSpace+URLProtectionSpace.swift",
            INFRASTRUCTURE_ROOT / "BrowserHTTPAuthenticationResolution.swift",
            INFRASTRUCTURE_ROOT
            / "BrowserHTTPAuthenticationSession+URLAuthenticationChallenge.swift",
        )

        for path in required_files:
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())

        self.assertFalse(
            (
                REPOSITORY_ROOT
                / "CrestShared/Infrastructure/BrowserAuthenticationPolicy.swift"
            ).exists()
        )

    def test_primary_authentication_types_match_their_filenames(self) -> None:
        for root in (DOMAIN_ROOT, APPLICATION_ROOT, INFRASTRUCTURE_ROOT):
            for path in root.rglob("*.swift"):
                names = DECLARATION_PATTERN.findall(path.read_text())
                expected_names = [] if "+" in path.stem else [path.stem]
                with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                    self.assertEqual(names, expected_names)

    def test_foundation_authentication_adapters_are_in_infrastructure(self) -> None:
        forbidden_tokens = (
            "URLAuthenticationChallenge",
            "URLCredential",
            "URLProtectionSpace",
            "URLSession.AuthChallengeDisposition",
            "NSURLAuthenticationMethod",
        )

        for root in (DOMAIN_ROOT, APPLICATION_ROOT):
            for path in root.rglob("*.swift"):
                source = path.read_text()
                for token in forbidden_tokens:
                    with self.subTest(
                        path=path.relative_to(REPOSITORY_ROOT), token=token
                    ):
                        self.assertNotIn(token, source)

        infrastructure_source = "\n".join(
            path.read_text() for path in INFRASTRUCTURE_ROOT.rglob("*.swift")
        )
        for token in forbidden_tokens:
            with self.subTest(token=token):
                self.assertIn(token, infrastructure_source)

    def test_session_state_machine_is_application_owned(self) -> None:
        source = (
            APPLICATION_ROOT / "BrowserHTTPAuthenticationSession.swift"
        ).read_text()

        self.assertIn("@MainActor", source)
        self.assertIn("final class BrowserHTTPAuthenticationSession", source)
        self.assertIn("attemptedStoredCredential", source)
        self.assertIn("attemptedProtectionSpace", source)
        self.assertIn("pendingSaveRequest", source)
        self.assertIn("func authenticationSucceeded() async", source)
        self.assertIn("func authenticationFailed()", source)


if __name__ == "__main__":
    unittest.main()
