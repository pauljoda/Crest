import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionCookieAccessStoreTests: XCTestCase {
    private let space = SpaceID()
    private let otherSpace = SpaceID()
    private let client = BrowserExtensionServiceClientID("claude")!
    private let other = BrowserExtensionServiceClientID("other")!

    func testFramingASiteRelaxesItInThatSpaceOnly() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)

        await store.relaxCookies(for: "claude.ai", client: client, in: space)

        XCTAssertEqual(jar.relaxRequests[space], ["claude.ai"])
        XCTAssertNil(jar.relaxRequests[otherSpace])
        XCTAssertEqual(store.relaxedHosts(in: space), ["claude.ai"])
        XCTAssertTrue(store.relaxedHosts(in: otherSpace).isEmpty)
        XCTAssertEqual(jar.observedSpaces, [space])
    }

    func testHostsAreNormalizedAndEmptyOnesAreRefused() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)

        await store.relaxCookies(for: "Claude.AI", client: client, in: space)
        await store.relaxCookies(for: "", client: client, in: space)

        XCTAssertEqual(store.relaxedHosts(for: client), ["claude.ai"])
        XCTAssertEqual(jar.relaxRequests[space], ["claude.ai"])
    }

    func testOneClientCanRelaxSeveralHosts() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)

        await store.relaxCookies(for: "claude.ai", client: client, in: space)
        await store.relaxCookies(for: "api.anthropic.com", client: client, in: space)

        XCTAssertEqual(store.relaxedHosts(for: client), ["api.anthropic.com", "claude.ai"])
        XCTAssertEqual(store.relaxedHosts(in: space), ["claude.ai", "api.anthropic.com"])
    }

    func testReframingAKnownHostRewritesAgainWithoutASecondObserver() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)

        await store.relaxCookies(for: "claude.ai", client: client, in: space)
        let revisionAfterFirst = store.revision
        await store.relaxCookies(for: "claude.ai", client: client, in: space)

        // A reload is the cheapest moment to catch a cookie the observer
        // missed, so the rewrite runs again — but nothing was newly claimed.
        XCTAssertEqual(jar.relaxRequests[space], ["claude.ai", "claude.ai"])
        XCTAssertEqual(store.revision, revisionAfterFirst)
        XCTAssertEqual(jar.observedSpaces, [space])
    }

    func testUnregisteringTheLastClientStopsEnforcingTheSpace() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)
        await store.relaxCookies(for: "claude.ai", client: client, in: space)

        store.unregister(client: client)

        XCTAssertTrue(store.relaxedHosts(in: space).isEmpty)
        XCTAssertTrue(jar.observedSpaces.isEmpty)
        jar.simulateCookieChange(in: space)
        await settle()
        XCTAssertEqual(jar.relaxRequests[space], ["claude.ai"])
    }

    func testASecondClientOnTheSameHostKeepsEnforcementAlive() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)
        await store.relaxCookies(for: "claude.ai", client: client, in: space)
        await store.relaxCookies(for: "claude.ai", client: other, in: space)

        store.unregister(client: client)

        XCTAssertEqual(store.relaxedHosts(in: space), ["claude.ai"])
        XCTAssertEqual(jar.observedSpaces, [space])
    }

    func testUnregisteringOneClientKeepsTheOtherClientsHosts() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)
        await store.relaxCookies(for: "claude.ai", client: client, in: space)
        await store.relaxCookies(for: "example.com", client: other, in: space)

        store.unregister(client: other)

        XCTAssertEqual(store.relaxedHosts(in: space), ["claude.ai"])
        XCTAssertEqual(jar.observedSpaces, [space])
    }

    func testUnregisteringAnUnknownClientChangesNothing() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)
        await store.relaxCookies(for: "claude.ai", client: client, in: space)
        let revision = store.revision

        store.unregister(client: other)

        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(jar.observedSpaces, [space])
    }

    func testACookieChangeReappliesEveryHostTheSpaceStillHolds() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)
        await store.relaxCookies(for: "claude.ai", client: client, in: space)
        await store.relaxCookies(for: "example.com", client: other, in: space)

        // The login response that re-sets a `Lax` session cookie.
        jar.simulateCookieChange(in: space)
        await settle()

        XCTAssertEqual(
            jar.relaxRequests[space],
            ["claude.ai", "example.com", "claude.ai", "example.com"]
        )
    }

    func testEachSpaceKeepsItsOwnObserverAndHosts() async {
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)
        let otherSpaceClient = BrowserExtensionServiceClientID("claude.other-space")!
        await store.relaxCookies(for: "claude.ai", client: client, in: space)
        await store.relaxCookies(for: "claude.ai", client: otherSpaceClient, in: otherSpace)

        store.unregister(client: client)

        XCTAssertTrue(store.relaxedHosts(in: space).isEmpty)
        XCTAssertEqual(store.relaxedHosts(in: otherSpace), ["claude.ai"])
        XCTAssertEqual(jar.observedSpaces, [otherSpace])
    }

    /// Lets the store's re-apply task run; it hops through `Task { @MainActor }`
    /// so the change handler stays synchronous for the observer.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}
