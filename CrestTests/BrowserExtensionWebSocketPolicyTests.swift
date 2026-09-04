import XCTest

@testable import Crest

/// A brokered worker WebSocket is opened outside the WebContent process, so
/// WebKit never applies the extension's own `connect-src` to it. These pin the
/// evaluation that stands in for it.
final class BrowserExtensionWebSocketPolicyTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testAManifestWithoutAConnectDirectiveAllowsAnySocket() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "script-src 'self'; object-src 'self'"
        )

        XCTAssertTrue(
            policy.allowsConnection(to: try url("wss://api.example.com/v1"))
        )
        XCTAssertTrue(
            policy.allowsConnection(to: try url("ws://127.0.0.1:1455/codex"))
        )
    }

    func testAnAbsentPolicyAllowsAnySocket() throws {
        XCTAssertTrue(
            BrowserExtensionWebSocketPolicy(policy: nil)
                .allowsConnection(to: try url("wss://example.com/"))
        )
        XCTAssertTrue(
            BrowserExtensionWebSocketPolicy.unrestricted
                .allowsConnection(to: try url("ws://example.com/"))
        )
    }

    func testOnlyWebSocketSchemesAreEverAllowed() throws {
        let policy = BrowserExtensionWebSocketPolicy(policy: "connect-src *")

        XCTAssertTrue(policy.allowsConnection(to: try url("ws://example.com/")))
        XCTAssertTrue(policy.allowsConnection(to: try url("wss://example.com/")))
        XCTAssertFalse(
            policy.allowsConnection(to: try url("https://example.com/"))
        )
        XCTAssertFalse(
            policy.allowsConnection(to: try url("file:///etc/hosts"))
        )
    }

    func testConnectSourceOverridesDefaultSource() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "default-src 'none'; connect-src wss://api.example.com"
        )

        XCTAssertTrue(
            policy.allowsConnection(to: try url("wss://api.example.com/socket"))
        )
        XCTAssertFalse(
            policy.allowsConnection(to: try url("wss://other.example.com/"))
        )
    }

    func testDefaultSourceAppliesWhenNoConnectSourceIsDeclared() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "default-src 'self' wss://api.example.com"
        )

        XCTAssertTrue(
            policy.allowsConnection(to: try url("wss://api.example.com/"))
        )
        XCTAssertFalse(
            policy.allowsConnection(to: try url("wss://cdn.example.com/"))
        )
    }

    func testNoneBlocksEverySocket() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "connect-src 'none'"
        )

        XCTAssertFalse(policy.allowsConnection(to: try url("wss://a.example/")))
        XCTAssertFalse(policy.allowsConnection(to: try url("ws://a.example/")))
    }

    /// `'self'` for an extension page is a `chrome-extension:` origin, which no
    /// WebSocket URL can be.
    func testSelfAloneBlocksEverySocket() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "connect-src 'self'"
        )

        XCTAssertFalse(policy.allowsConnection(to: try url("wss://a.example/")))
    }

    func testSchemeSourcesUpgradeInOneDirectionOnly() throws {
        let insecure = BrowserExtensionWebSocketPolicy(policy: "connect-src ws:")
        XCTAssertTrue(insecure.allowsConnection(to: try url("ws://a.example/")))
        XCTAssertTrue(insecure.allowsConnection(to: try url("wss://a.example/")))

        let secure = BrowserExtensionWebSocketPolicy(policy: "connect-src wss:")
        XCTAssertTrue(secure.allowsConnection(to: try url("wss://a.example/")))
        XCTAssertFalse(secure.allowsConnection(to: try url("ws://a.example/")))

        // Chromium's `https:` scheme-source covers no socket at all, and a
        // package that means to open one names `wss:` alongside it.
        let https = BrowserExtensionWebSocketPolicy(policy: "connect-src https:")
        XCTAssertFalse(https.allowsConnection(to: try url("wss://a.example/")))
    }

    func testHostSourcesMatchSubdomainsAndPorts() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "connect-src wss://*.example.com ws://localhost:1455"
        )

        XCTAssertTrue(
            policy.allowsConnection(to: try url("wss://api.example.com/socket"))
        )
        XCTAssertTrue(
            policy.allowsConnection(to: try url("wss://example.com/socket"))
        )
        XCTAssertFalse(
            policy.allowsConnection(to: try url("wss://example.com.evil.test/"))
        )
        XCTAssertTrue(
            policy.allowsConnection(to: try url("ws://localhost:1455/codex"))
        )
        XCTAssertFalse(
            policy.allowsConnection(to: try url("ws://localhost:1456/codex"))
        )
    }

    /// A source with no port matches only the scheme's default port, so a
    /// package that means to reach a local app server has to say which one.
    func testAPortlessSourceMatchesOnlyTheDefaultPort() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "connect-src ws://localhost"
        )

        XCTAssertTrue(
            policy.allowsConnection(to: try url("ws://localhost/socket"))
        )
        XCTAssertFalse(
            policy.allowsConnection(to: try url("ws://localhost:1455/socket"))
        )

        let anyPort = BrowserExtensionWebSocketPolicy(
            policy: "connect-src ws://localhost:*"
        )
        XCTAssertTrue(
            anyPort.allowsConnection(to: try url("ws://localhost:1455/socket"))
        )
    }

    func testPathSourcesMatchExactlyOrAsAPrefix() throws {
        let exact = BrowserExtensionWebSocketPolicy(
            policy: "connect-src wss://api.example.com/socket"
        )
        XCTAssertTrue(
            exact.allowsConnection(to: try url("wss://api.example.com/socket"))
        )
        XCTAssertFalse(
            exact.allowsConnection(
                to: try url("wss://api.example.com/socket/v2")
            )
        )

        let prefix = BrowserExtensionWebSocketPolicy(
            policy: "connect-src wss://api.example.com/socket/"
        )
        XCTAssertTrue(
            prefix.allowsConnection(
                to: try url("wss://api.example.com/socket/v2")
            )
        )
        XCTAssertFalse(
            prefix.allowsConnection(to: try url("wss://api.example.com/other"))
        )
    }

    /// Crest is deliberately more permissive than Chromium here: Chromium
    /// compares a scheme-less source against the page's own scheme, which for
    /// an extension is `chrome-extension:` and therefore matches no socket.
    func testASchemelessHostSourceMatchesEitherWebSocketScheme() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "connect-src localhost:1455"
        )

        XCTAssertTrue(
            policy.allowsConnection(to: try url("ws://localhost:1455/codex"))
        )
        XCTAssertTrue(
            policy.allowsConnection(to: try url("wss://localhost:1455/codex"))
        )
        XCTAssertFalse(
            policy.allowsConnection(to: try url("ws://127.0.0.1:1455/codex"))
        )
    }

    func testWildcardHostMatchesAnyHostOnTheNamedScheme() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "connect-src wss://*"
        )

        XCTAssertTrue(policy.allowsConnection(to: try url("wss://a.example/")))
        XCTAssertFalse(policy.allowsConnection(to: try url("ws://a.example/")))
    }

    func testNoncesAndKeywordsNeverMatchASocket() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy:
                "connect-src 'unsafe-inline' 'nonce-abc123' "
                + "'sha256-Zm9vYmFy'"
        )

        XCTAssertFalse(policy.allowsConnection(to: try url("wss://a.example/")))
    }

    func testDirectiveNamesAndSchemesAreCaseInsensitive() throws {
        let policy = BrowserExtensionWebSocketPolicy(
            policy: "CONNECT-SRC WSS://API.Example.COM"
        )

        XCTAssertTrue(
            policy.allowsConnection(to: try url("wss://api.example.com/"))
        )
    }

    func testManifestVersionThreeDeclaresPolicyForExtensionPages() {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "content_security_policy": [
                "extension_pages":
                    "script-src 'self'; connect-src wss://api.example.com",
                "sandbox": "sandbox allow-scripts",
            ],
        ]

        XCTAssertEqual(
            BrowserExtensionWebSocketPolicy.extensionPagesPolicy(in: manifest),
            "script-src 'self'; connect-src wss://api.example.com"
        )
    }

    func testManifestVersionTwoDeclaresPolicyAsAString() {
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "content_security_policy": "connect-src ws://localhost:1455",
        ]

        XCTAssertEqual(
            BrowserExtensionWebSocketPolicy.extensionPagesPolicy(in: manifest),
            "connect-src ws://localhost:1455"
        )
        XCTAssertNil(
            BrowserExtensionWebSocketPolicy.extensionPagesPolicy(
                in: ["manifest_version": 3]
            )
        )
    }
}
