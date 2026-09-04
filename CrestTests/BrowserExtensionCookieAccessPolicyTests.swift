import Foundation
import XCTest

@testable import Crest

final class BrowserExtensionCookieAccessPolicyTests: XCTestCase {

    // MARK: - relaxed

    func testLaxCookieLosesOnlyItsSameSiteAttribute() throws {
        // Foundation clamps a far-future expiry to its own cap, so the
        // assertion compares the two cookies rather than the requested date.
        let expiry = Date(timeIntervalSinceNow: 86_400)
        let cookie = try makeCookie(
            name: "sessionKey",
            value: "abc123",
            domain: ".claude.ai",
            path: "/api",
            sameSite: HTTPCookieStringPolicy.sameSiteLax,
            isSecure: true,
            isHTTPOnly: true,
            expires: expiry
        )

        let relaxed = try XCTUnwrap(BrowserExtensionCookieAccessPolicy.relaxed(cookie))

        XCTAssertNil(relaxed.sameSitePolicy)
        XCTAssertEqual(relaxed.name, "sessionKey")
        XCTAssertEqual(relaxed.value, "abc123")
        XCTAssertEqual(relaxed.domain, ".claude.ai")
        XCTAssertEqual(relaxed.path, "/api")
        XCTAssertTrue(relaxed.isSecure)
        XCTAssertTrue(relaxed.isHTTPOnly)
        XCTAssertEqual(
            relaxed.expiresDate?.timeIntervalSince1970 ?? 0,
            cookie.expiresDate?.timeIntervalSince1970 ?? -1,
            accuracy: 1
        )
    }

    func testStrictCookieIsRelaxedToo() throws {
        let cookie = try makeCookie(
            name: "csrf",
            value: "token",
            domain: "claude.ai",
            sameSite: HTTPCookieStringPolicy.sameSiteStrict
        )

        let relaxed = try XCTUnwrap(BrowserExtensionCookieAccessPolicy.relaxed(cookie))

        XCTAssertNil(relaxed.sameSitePolicy)
        XCTAssertEqual(relaxed.value, "token")
    }

    func testCookieWithNoSameSiteAttributeNeedsNoRewrite() throws {
        let cookie = try makeCookie(name: "plain", value: "v", domain: "claude.ai")

        XCTAssertNil(cookie.sameSitePolicy)
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(cookie))
        // Nil is the "nothing to write" signal that keeps a rewrite pass from
        // waking the cookie-store observer with its own no-op writes.
        XCTAssertNil(BrowserExtensionCookieAccessPolicy.relaxed(cookie))
    }

    func testWebKitsUnspecifiedNoneValueIsTreatedAsAlreadyRelaxed() throws {
        // What a cookie carrying no `SameSite` attribute reads back as once it
        // has been through `WKHTTPCookieStore`. Rewriting it would write the
        // same value forever and never stop notifying the store's observer.
        let cookie = try makeCookie(
            name: "roundTripped",
            value: "v",
            domain: "claude.ai",
            sameSite: HTTPCookieStringPolicy(rawValue: "none")
        )

        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(cookie))
        XCTAssertNil(BrowserExtensionCookieAccessPolicy.relaxed(cookie))
    }

    func testSameSiteValuesAreRecognizedRegardlessOfCase() throws {
        for raw in ["lax", "LAX", "Strict", "strict"] {
            let cookie = try makeCookie(
                name: "a",
                value: "v",
                domain: "claude.ai",
                sameSite: HTTPCookieStringPolicy(rawValue: raw)
            )
            XCTAssertTrue(
                BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(cookie),
                "\(raw) restricts cross-site use"
            )
        }
    }

    func testSessionCookieStaysSessionScopedAfterRelaxing() throws {
        let cookie = try makeCookie(
            name: "session",
            value: "v",
            domain: "claude.ai",
            sameSite: HTTPCookieStringPolicy.sameSiteLax
        )

        let relaxed = try XCTUnwrap(BrowserExtensionCookieAccessPolicy.relaxed(cookie))

        XCTAssertNil(relaxed.expiresDate)
        XCTAssertTrue(relaxed.isSessionOnly)
    }

    func testInsecureScriptReadableCookieKeepsBothFlagsOff() throws {
        let cookie = try makeCookie(
            name: "pref",
            value: "v",
            domain: "claude.ai",
            sameSite: HTTPCookieStringPolicy.sameSiteLax,
            isSecure: false,
            isHTTPOnly: false
        )

        let relaxed = try XCTUnwrap(BrowserExtensionCookieAccessPolicy.relaxed(cookie))

        XCTAssertFalse(relaxed.isSecure)
        XCTAssertFalse(relaxed.isHTTPOnly)
    }

    // MARK: - appliesTo

    func testHostOnlyCookieMatchesOnlyThatHost() throws {
        let cookie = try makeCookie(name: "a", value: "v", domain: "claude.ai")

        XCTAssertTrue(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "claude.ai"))
        XCTAssertTrue(
            BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "www.claude.ai")
        )
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "anthropic.com"))
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "notclaude.ai"))
    }

    func testDomainCookieMatchesTheHostAndItsSubdomains() throws {
        let cookie = try makeCookie(name: "a", value: "v", domain: ".claude.ai")

        XCTAssertTrue(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "claude.ai"))
        XCTAssertTrue(
            BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "api.claude.ai")
        )
        XCTAssertTrue(
            BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "deep.api.claude.ai")
        )
    }

    func testSubdomainCookieIsNotAppliedToItsParentHost() throws {
        let cookie = try makeCookie(name: "a", value: "v", domain: "api.claude.ai")

        // A request to `claude.ai` would never carry it, so relaxing it would
        // widen the rewrite past the frame that asked.
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "claude.ai"))
    }

    func testMatchingIgnoresCaseAndTrailingDots() throws {
        let cookie = try makeCookie(name: "a", value: "v", domain: ".Claude.AI.")

        XCTAssertTrue(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "CLAUDE.ai"))
    }

    func testEmptyHostNeverMatches() throws {
        let cookie = try makeCookie(name: "a", value: "v", domain: "claude.ai")

        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: ""))
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.appliesTo(cookie: cookie, host: "."))
    }

    // MARK: - host(for:)

    func testHostIsReadOnlyFromWebURLs() throws {
        XCTAssertEqual(
            BrowserExtensionCookieAccessPolicy.host(
                for: try XCTUnwrap(URL(string: "https://Claude.AI/cic/new?surface=cic_sidepanel"))
            ),
            "claude.ai"
        )
        XCTAssertEqual(
            BrowserExtensionCookieAccessPolicy.host(for: try XCTUnwrap(URL(string: "http://localhost:8080/x"))),
            "localhost"
        )
    }

    func testNonWebURLsHaveNoCookieHost() throws {
        let rejected = [
            "chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn/sidepanel.html",
            "about:blank",
            "data:text/html,<p>hi</p>",
            "blob:https://claude.ai/1234",
            "file:///tmp/x.html",
            "https:///nohost",
        ]
        for raw in rejected {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertNil(
                BrowserExtensionCookieAccessPolicy.host(for: url),
                "\(raw) must not resolve to a cookie host"
            )
        }
    }

    // MARK: - Helpers

    private func makeCookie(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        sameSite: HTTPCookieStringPolicy? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        expires: Date? = nil
    ) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
        ]
        if let sameSite { properties[.sameSitePolicy] = sameSite.rawValue }
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[BrowserExtensionCookieAccessPolicy.httpOnlyPropertyKey] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }
}
