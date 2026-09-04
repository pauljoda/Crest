import XCTest

@testable import Crest

final class BrowserExtensionIdentityBrokerRequestTests: XCTestCase {
    /// The envelope the Claude extension's startup re-authentication sends.
    func testDecodesTheSilentReauthenticationEnvelope() throws {
        let request = try BrowserExtensionIdentityBrokerRequest(
            message: [
                "api": "identity.launchWebAuthFlow",
                "url": "https://claude.ai/oauth/authorize?client_id=abc&prompt=none",
                "interactive": false,
                "abortOnLoadForNonInteractive": false,
                "timeoutMs": 5000,
            ]
        )
        XCTAssertEqual(
            request.url.absoluteString,
            "https://claude.ai/oauth/authorize?client_id=abc&prompt=none")
        XCTAssertFalse(request.isInteractive)
        XCTAssertFalse(request.abortsOnLoadForNonInteractive)
        XCTAssertEqual(request.nonInteractiveTimeout, 5, accuracy: 0.001)
    }

    /// Chrome's defaults, applied when the caller omits them.
    func testAppliesChromesDefaultsForOmittedOptions() throws {
        let request = try BrowserExtensionIdentityBrokerRequest(
            message: ["api": "identity.launchWebAuthFlow", "url": "https://example.com/auth"]
        )
        XCTAssertFalse(request.isInteractive)
        XCTAssertTrue(request.abortsOnLoadForNonInteractive)
        XCTAssertEqual(request.nonInteractiveTimeout, 60, accuracy: 0.001)
    }

    /// A request for a longer non-interactive run is a request to keep an
    /// invisible web view alive, so the ceiling is enforced here rather than
    /// trusted from JavaScript.
    func testClampsTheNonInteractiveTimeoutToChromesCeiling() throws {
        let request = try BrowserExtensionIdentityBrokerRequest(
            message: [
                "api": "identity.launchWebAuthFlow",
                "url": "https://example.com/auth",
                "timeoutMs": 900_000,
            ]
        )
        XCTAssertEqual(request.nonInteractiveTimeout, 60, accuracy: 0.001)
    }

    func testRejectsRequestsCrestCannotRun() {
        let messages: [[String: Any]] = [
            ["api": "identity.getAuthToken", "url": "https://example.com/"],
            ["api": "identity.launchWebAuthFlow"],
            ["api": "identity.launchWebAuthFlow", "url": 42],
            ["api": "identity.launchWebAuthFlow", "url": "/relative"],
            ["api": "identity.launchWebAuthFlow", "url": "ftp://example.com/"],
            ["api": "identity.launchWebAuthFlow", "url": "https:///no-host"],
            ["api": "identity.launchWebAuthFlow", "url": "https://a.test/", "timeoutMs": 0],
            ["api": "identity.launchWebAuthFlow", "url": "https://a.test/", "timeoutMs": -1],
        ]
        for message in messages {
            XCTAssertThrowsError(
                try BrowserExtensionIdentityBrokerRequest(message: message),
                "\(message) must not decode."
            ) { error in
                XCTAssertEqual(
                    error as? BrowserExtensionIdentityBrokerError, .invalidRequest)
            }
        }
    }

    /// Packages branch on these strings, so they are Chrome's exactly. None of
    /// them names the URL: an error message is a place a package logs.
    func testFailureTextMatchesChrome() {
        XCTAssertEqual(
            BrowserExtensionIdentityBrokerError.pageLoadFailure.errorDescription,
            "Authorization page could not be loaded.")
        XCTAssertEqual(
            BrowserExtensionIdentityBrokerError.userRejected.errorDescription,
            "The user did not approve access.")
        XCTAssertEqual(
            BrowserExtensionIdentityBrokerError.interactionRequired.errorDescription,
            "User interaction required.")
    }

    func testRedirectOriginIsDerivedFromTheRuntimeIdentifier() {
        XCTAssertEqual(
            BrowserExtensionIdentityRedirectOrigin.origin(
                runtimeID: "fcoeoabgfenejglbffodgkkbkcdhcgfn"),
            "https://fcoeoabgfenejglbffodgkkbkcdhcgfn.chromiumapp.org")
        // Crest's per-Space host for a non-store package is hex, not a
        // Chrome-shaped id. The flow still runs; a provider that validates the
        // host is the one that refuses it.
        XCTAssertEqual(
            BrowserExtensionIdentityRedirectOrigin.origin(runtimeID: "AB12cd"),
            "https://ab12cd.chromiumapp.org")
        XCTAssertNil(BrowserExtensionIdentityRedirectOrigin.origin(runtimeID: ""))
        XCTAssertNil(
            BrowserExtensionIdentityRedirectOrigin.origin(runtimeID: "evil.example.com"))
        XCTAssertNil(BrowserExtensionIdentityRedirectOrigin.origin(runtimeID: "a/b"))
    }

    /// Origin equality, not a prefix test. Chrome matches
    /// `https://<id>.chromiumapp.org/*`, so every path completes the flow and
    /// a look-alike host does not.
    func testRedirectMatchingIsOriginEqualityRatherThanAPrefix() throws {
        let origin = "https://abc.chromiumapp.org"
        let matching = [
            "https://abc.chromiumapp.org/",
            "https://abc.chromiumapp.org/?code=x&state=y",
            "https://abc.chromiumapp.org/nested/path#token",
            "https://ABC.chromiumapp.org/?code=x",
        ]
        for candidate in matching {
            XCTAssertTrue(
                BrowserExtensionIdentityRedirectOrigin.matches(
                    try XCTUnwrap(URL(string: candidate)), origin: origin),
                "\(candidate) is the callback.")
        }
        let rejected = [
            "http://abc.chromiumapp.org/?code=x",
            "https://abc.chromiumapp.org.example.com/?code=x",
            "https://abc.chromiumapp.org:8443/?code=x",
            "https://def.chromiumapp.org/?code=x",
            "https://chromiumapp.org/?code=x",
            "https://evil.test/abc.chromiumapp.org",
        ]
        for candidate in rejected {
            XCTAssertFalse(
                BrowserExtensionIdentityRedirectOrigin.matches(
                    try XCTUnwrap(URL(string: candidate)), origin: origin),
                "\(candidate) must not complete the flow.")
        }
    }
}
