import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionCookieJarCoordinatorTests: XCTestCase {
    private let space = SpaceID()

    func testRelaxingDropsSameSiteAndKeepsEverythingElse() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let cookieStore = dataStore.httpCookieStore
        let expiry = Date(timeIntervalSinceNow: 86_400)
        await cookieStore.setCookie(
            try makeCookie(sameSite: HTTPCookieStringPolicy.sameSiteLax, expires: expiry)
        )
        let beforeCookie = await Self.cookie(named: "sessionKey", in: cookieStore)
        let before = try XCTUnwrap(beforeCookie)
        XCTAssertTrue(
            BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(before),
            "the fixture must reach WebKit still restricted, or the rewrite proves nothing"
        )
        let coordinator = makeCoordinator(dataStore)

        await coordinator.relax(host: "claude.ai", in: space)

        let storedCookie = await Self.cookie(named: "sessionKey", in: cookieStore)
        let stored = try XCTUnwrap(storedCookie)
        // WebKit reports an unspecified `SameSite` as `none` rather than as no
        // value, so "relaxed" is read through the policy, not through nil.
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(stored))
        XCTAssertEqual(stored.value, "abc123")
        XCTAssertTrue(stored.isSecure)
        XCTAssertTrue(stored.isHTTPOnly)
        XCTAssertEqual(stored.path, "/")
        XCTAssertEqual(
            stored.expiresDate?.timeIntervalSince1970 ?? 0,
            before.expiresDate?.timeIntervalSince1970 ?? -1,
            accuracy: 2
        )
    }

    func testASecondPassOverRelaxedCookiesWritesNothing() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let cookieStore = dataStore.httpCookieStore
        await cookieStore.setCookie(try makeCookie(sameSite: HTTPCookieStringPolicy.sameSiteLax))
        let coordinator = makeCoordinator(dataStore)
        await coordinator.relax(host: "claude.ai", in: space)
        let firstPassCookie = await Self.cookie(named: "sessionKey", in: cookieStore)
        let firstPass = try XCTUnwrap(firstPassCookie)

        await coordinator.relax(host: "claude.ai", in: space)

        // Nothing left to rewrite is what makes the observer loop terminate.
        XCTAssertNil(BrowserExtensionCookieAccessPolicy.relaxed(firstPass))
        let secondPassCookie = await Self.cookie(named: "sessionKey", in: cookieStore)
        let secondPass = try XCTUnwrap(secondPassCookie)
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(secondPass))
        XCTAssertEqual(secondPass.value, "abc123")
    }

    func testCookiesForOtherHostsAreLeftAlone() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let cookieStore = dataStore.httpCookieStore
        await cookieStore.setCookie(
            try makeCookie(
                name: "elsewhere",
                domain: "example.com",
                sameSite: HTTPCookieStringPolicy.sameSiteStrict
            )
        )
        let coordinator = makeCoordinator(dataStore)

        await coordinator.relax(host: "claude.ai", in: space)

        let storedCookie = await Self.cookie(named: "elsewhere", in: cookieStore)
        let stored = try XCTUnwrap(storedCookie)
        XCTAssertTrue(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(stored))
    }

    func testASpaceWithNoExtensionDataStoreRewritesNothing() async {
        let coordinator = BrowserExtensionCookieJarCoordinator { _ in nil }

        // Reaching this line without trapping is the assertion: an unresolved
        // Space must be left alone rather than fall back to a default jar.
        await coordinator.relax(host: "claude.ai", in: space)
    }

    func testTheObserverRestoresTheRewriteWhenTheSiteResetsALaxCookie() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let cookieStore = dataStore.httpCookieStore
        await cookieStore.setCookie(try makeCookie(sameSite: HTTPCookieStringPolicy.sameSiteLax))
        let coordinator = makeCoordinator(dataStore)
        await coordinator.relax(host: "claude.ai", in: space)

        let reapplied = expectation(description: "observer re-applied the rewrite")
        reapplied.assertForOverFulfill = false
        let space = self.space
        coordinator.observe(spaceID: space) {
            Task { @MainActor in
                await coordinator.relax(host: "claude.ai", in: space)
                guard let stored = await Self.cookie(named: "sessionKey", in: cookieStore),
                    stored.value == "signed-in",
                    !BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(stored)
                else { return }
                reapplied.fulfill()
            }
        }

        // The login response: the site re-sets the same cookie as `Lax`.
        await cookieStore.setCookie(
            try makeCookie(value: "signed-in", sameSite: HTTPCookieStringPolicy.sameSiteLax)
        )

        await fulfillment(of: [reapplied], timeout: 10)
        let storedCookie = await Self.cookie(named: "sessionKey", in: cookieStore)
        let stored = try XCTUnwrap(storedCookie)
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(stored))
        XCTAssertEqual(stored.value, "signed-in")
        coordinator.observe(spaceID: space, onChange: nil)
    }

    func testRemovingTheObserverStopsTheReapplyHandler() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let cookieStore = dataStore.httpCookieStore
        let coordinator = makeCoordinator(dataStore)
        var changeCount = 0
        coordinator.observe(spaceID: space) { changeCount += 1 }
        coordinator.observe(spaceID: space, onChange: nil)

        await cookieStore.setCookie(try makeCookie(sameSite: HTTPCookieStringPolicy.sameSiteLax))
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        _ dataStore: WKWebsiteDataStore
    ) -> BrowserExtensionCookieJarCoordinator {
        let space = self.space
        return BrowserExtensionCookieJarCoordinator(coalescingDelay: .milliseconds(20)) { spaceID in
            spaceID == space ? dataStore : nil
        }
    }

    private static func cookie(
        named name: String,
        in cookieStore: WKHTTPCookieStore
    ) async -> HTTPCookie? {
        let cookies = await cookieStore.allCookies()
        return cookies.first { $0.name == name }
    }

    private func makeCookie(
        name: String = "sessionKey",
        value: String = "abc123",
        domain: String = ".claude.ai",
        sameSite: HTTPCookieStringPolicy?,
        expires: Date? = nil
    ) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: "/",
            .secure: "TRUE",
            BrowserExtensionCookieAccessPolicy.httpOnlyPropertyKey: "TRUE",
        ]
        if let sameSite { properties[.sameSitePolicy] = sameSite.rawValue }
        if let expires { properties[.expires] = expires }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }
}
