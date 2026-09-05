import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionCookieJarCoordinatorTests: XCTestCase {
    private let space = SpaceID()

    func testRelaxingOnlyChangesTheHostedCopyAndKeepsEverythingElse() async throws {
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
        let hostedStore = try XCTUnwrap(coordinator.hostedWebsiteDataStore(in: space)).httpCookieStore

        await coordinator.relax(host: "claude.ai", in: space)

        let storedCookie = await Self.cookie(named: "sessionKey", in: hostedStore)
        let stored = try XCTUnwrap(storedCookie)
        // WebKit reports an unspecified `SameSite` as `none` rather than as no
        // value, so "relaxed" is read through the policy, not through nil.
        XCTAssertFalse(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(stored))
        let normalAfter = await Self.cookie(named: "sessionKey", in: cookieStore)
        XCTAssertEqual(normalAfter?.sameSitePolicy, before.sameSitePolicy)
        XCTAssertEqual(normalAfter?.value, before.value)
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
        let hostedStore = try XCTUnwrap(coordinator.hostedWebsiteDataStore(in: space)).httpCookieStore
        await coordinator.relax(host: "claude.ai", in: space)
        let firstPassCookie = await Self.cookie(named: "sessionKey", in: hostedStore)
        let firstPass = try XCTUnwrap(firstPassCookie)

        await coordinator.relax(host: "claude.ai", in: space)

        // Nothing left to rewrite is what makes the observer loop terminate.
        XCTAssertNil(BrowserExtensionCookieAccessPolicy.relaxed(firstPass))
        let secondPassCookie = await Self.cookie(named: "sessionKey", in: hostedStore)
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
        let hostedStore = try XCTUnwrap(coordinator.hostedWebsiteDataStore(in: space)).httpCookieStore

        await coordinator.relax(host: "claude.ai", in: space)

        let storedCookie = await Self.cookie(named: "elsewhere", in: cookieStore)
        let stored = try XCTUnwrap(storedCookie)
        XCTAssertTrue(BrowserExtensionCookieAccessPolicy.restrictsCrossSiteUse(stored))
        let copiedOtherHost = await Self.cookie(named: "elsewhere", in: hostedStore)
        XCTAssertNil(copiedOtherHost)
    }

    func testASpaceWithNoExtensionDataStoreRewritesNothing() async {
        let coordinator = BrowserExtensionCookieJarCoordinator { _ in nil }

        // Reaching this line without trapping is the assertion: an unresolved
        // Space must be left alone rather than fall back to a default jar.
        await coordinator.relax(host: "claude.ai", in: space)
    }

    func testARevokedHostCannotSynchronizeALaterHostedRefresh() async throws {
        let normal = WKWebsiteDataStore.nonPersistent()
        await normal.httpCookieStore.setCookie(try makeCookie(sameSite: .sameSiteStrict))
        let coordinator = makeCoordinator(normal)
        let hosted = try XCTUnwrap(coordinator.hostedWebsiteDataStore(in: space)).httpCookieStore
        coordinator.setSynchronizedHosts(["claude.ai"], in: space)
        await coordinator.relax(host: "claude.ai", in: space)
        coordinator.setSynchronizedHosts([], in: space)
        await hosted.setCookie(try makeCookie(value: "new-session", sameSite: .sameSiteLax))
        await coordinator.relax(host: "claude.ai", in: space)
        let normalAfter = await Self.cookie(named: "sessionKey", in: normal.httpCookieStore)
        XCTAssertEqual(normalAfter?.value, "abc123")
        XCTAssertEqual(normalAfter?.sameSitePolicy, .sameSiteStrict)
    }

    func testTheObserverRestoresTheRewriteWhenTheSiteResetsALaxCookie() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let cookieStore = dataStore.httpCookieStore
        await cookieStore.setCookie(try makeCookie(sameSite: HTTPCookieStringPolicy.sameSiteLax))
        let coordinator = makeCoordinator(dataStore)
        let hostedStore = try XCTUnwrap(coordinator.hostedWebsiteDataStore(in: space)).httpCookieStore
        await coordinator.relax(host: "claude.ai", in: space)

        let reapplied = expectation(description: "observer re-applied the rewrite")
        reapplied.assertForOverFulfill = false
        let space = self.space
        coordinator.observe(spaceID: space) {
            Task { @MainActor in
                await coordinator.relax(host: "claude.ai", in: space)
                guard let stored = await Self.cookie(named: "sessionKey", in: hostedStore),
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
        let storedCookie = await Self.cookie(named: "sessionKey", in: hostedStore)
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

    func testHostedRefreshPreservesNormalSameSiteAndLogoutPropagates() async throws {
        let normal = WKWebsiteDataStore.nonPersistent()
        let coordinator = makeCoordinator(normal)
        let hosted = try XCTUnwrap(coordinator.hostedWebsiteDataStore(in: space))
        await normal.httpCookieStore.setCookie(try makeCookie(sameSite: .sameSiteStrict))
        await coordinator.relax(host: "claude.ai", in: space)

        // A frame refresh updates a relaxed copy. Its value reaches normal tabs
        // without copying the relaxation back into their cookie jar.
        await hosted.httpCookieStore.setCookie(try makeCookie(value: "refreshed", sameSite: nil))
        await coordinator.relax(host: "claude.ai", in: space)
        let refreshed = await Self.cookie(named: "sessionKey", in: normal.httpCookieStore)
        XCTAssertEqual(refreshed?.value, "refreshed")
        XCTAssertEqual(refreshed?.sameSitePolicy, .sameSiteStrict)

        await normal.httpCookieStore.deleteCookie(try XCTUnwrap(refreshed))
        await coordinator.relax(host: "claude.ai", in: space)
        let loggedOut = await Self.cookie(named: "sessionKey", in: hosted.httpCookieStore)
        XCTAssertNil(loggedOut)

        await normal.httpCookieStore.setCookie(try makeCookie(value: "new-login", sameSite: .sameSiteLax))
        await coordinator.relax(host: "claude.ai", in: space)
        let newLogin = await Self.cookie(named: "sessionKey", in: hosted.httpCookieStore)
        await hosted.httpCookieStore.deleteCookie(try XCTUnwrap(newLogin))
        await coordinator.relax(host: "claude.ai", in: space)
        let panelLogout = await Self.cookie(named: "sessionKey", in: normal.httpCookieStore)
        XCTAssertNil(panelLogout)
    }

    func testNormalLogoutWinsAConcurrentHostedRefresh() async throws {
        let normal = WKWebsiteDataStore.nonPersistent()
        let coordinator = makeCoordinator(normal)
        let hosted = try XCTUnwrap(coordinator.hostedWebsiteDataStore(in: space))
        let cookie = try makeCookie(sameSite: .sameSiteLax)
        await normal.httpCookieStore.setCookie(cookie)
        await coordinator.relax(host: "claude.ai", in: space)
        await normal.httpCookieStore.deleteCookie(cookie)
        await hosted.httpCookieStore.setCookie(try makeCookie(value: "late-refresh", sameSite: .sameSiteLax))
        await coordinator.relax(host: "claude.ai", in: space)
        let sourceAfter = await Self.cookie(named: "sessionKey", in: normal.httpCookieStore)
        let hostedAfter = await Self.cookie(named: "sessionKey", in: hosted.httpCookieStore)
        XCTAssertNil(sourceAfter)
        XCTAssertNil(hostedAfter)
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
