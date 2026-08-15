import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserProfileIsolationTests: XCTestCase {
    func testLaunchScopedMobileStoreIsNonpersistentDuringXCTest() {
        let store = BrowserWebsiteDataStore.launchScoped(
            for: BrowsingProfile()
        )

        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testPrivateMobileStoresShareNothingAndCannotBeRehydrated() async throws {
        let storeA = WKWebsiteDataStore.nonPersistent()
        let storeB = WKWebsiteDataStore.nonPersistent()
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "private.crest.test",
                .path: "/",
                .name: "private-mobile-session",
                .value: "space-a",
                .secure: "TRUE",
            ])
        )

        await set(cookie, in: storeA.httpCookieStore)

        let cookiesA = await cookies(in: storeA.httpCookieStore)
        let cookiesB = await cookies(in: storeB.httpCookieStore)
        let replacementStore = WKWebsiteDataStore.nonPersistent()
        let replacementCookies = await cookies(in: replacementStore.httpCookieStore)

        XCTAssertFalse(storeA.isPersistent)
        XCTAssertNil(storeA.identifier)
        XCTAssertEqual(cookiesA.first(where: { $0.name == cookie.name })?.value, "space-a")
        XCTAssertNil(cookiesB.first(where: { $0.name == cookie.name }))
        XCTAssertNil(replacementCookies.first(where: { $0.name == cookie.name }))

        await delete(cookie, from: storeA.httpCookieStore)
    }

    func testNamedMobileProfileStoresPersistIdentityAndDoNotShareCookies() async throws {
        let profileA = BrowsingProfile()
        let profileB = BrowsingProfile()
        let storeA = BrowserWebsiteDataStore.persistent(for: profileA)
        let storeB = BrowserWebsiteDataStore.persistent(for: profileB)
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "crest.test",
                .path: "/",
                .name: "mobile-space-session",
                .value: "space-a",
                .secure: "TRUE",
            ])
        )

        await set(cookie, in: storeA.httpCookieStore)

        let cookiesA = await cookies(in: storeA.httpCookieStore)
        let cookiesB = await cookies(in: storeB.httpCookieStore)
        let rehydratedA = BrowserWebsiteDataStore.persistent(for: profileA)
        let rehydratedCookiesA = await cookies(in: rehydratedA.httpCookieStore)

        XCTAssertEqual(storeA.identifier, profileA.id)
        XCTAssertEqual(storeB.identifier, profileB.id)
        XCTAssertEqual(cookiesA.first(where: { $0.name == cookie.name })?.value, "space-a")
        XCTAssertNil(cookiesB.first(where: { $0.name == cookie.name }))
        XCTAssertEqual(rehydratedCookiesA.first(where: { $0.name == cookie.name })?.value, "space-a")

        await delete(cookie, from: storeA.httpCookieStore)
        await removeDataStore(profileA.id)
        await removeDataStore(profileB.id)
    }

    private func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) { continuation.resume() }
        }
    }

    private func cookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private func delete(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }

    private func removeDataStore(_ identifier: UUID) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in continuation.resume() }
        }
    }
}
