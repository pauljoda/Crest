import XCTest

@testable import Crest

@MainActor
final class BrowserWebsiteDataStoreTests: XCTestCase {
    func testEphemeralProfileRemovalNeverOpensAPersistentWebKitStore() async throws {
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            identifierProvider: { XCTFail("Ephemeral profiles must not query persistent stores"); return [] },
            removeDataStore: { _ in XCTFail("Ephemeral profiles must not remove persistent stores") })
        try await remover.removeProfile(BrowsingProfile(), ephemeral: true)
    }

    func testSiteDataMatchingIncludesTheHostAndItsParentRecords() {
        XCTAssertTrue(
            BrowserSiteDataPolicy.matchesDataRecord(
                displayName: "localhost",
                host: "api.localhost"
            )
        )
        XCTAssertTrue(
            BrowserSiteDataPolicy.matchesDataRecord(
                displayName: "api.localhost",
                host: "api.localhost"
            )
        )
        XCTAssertFalse(
            BrowserSiteDataPolicy.matchesDataRecord(
                displayName: "notlocalhost.example",
                host: "localhost"
            )
        )
    }

    func testSiteCookieRemovalIncludesParentDomainsButNotUnrelatedSites() {
        XCTAssertTrue(BrowserSiteDataPolicy.includesCookieDomainForRemoval("localhost", host: "api.localhost"))
        XCTAssertTrue(
            BrowserSiteDataPolicy.includesCookieDomainForRemoval(
                ".localhost",
                host: "api.localhost"
            )
        )
        XCTAssertTrue(
            BrowserSiteDataPolicy.includesCookieDomainForRemoval(
                "api.localhost",
                host: "api.localhost"
            )
        )
        XCTAssertFalse(
            BrowserSiteDataPolicy.includesCookieDomainForRemoval(
                ".example.com",
                host: "api.localhost"
            )
        )
    }

    func testRemovingAProfileAlsoRemovesItsLegacyHostedExtensionStore() async throws {
        let profile = BrowsingProfile()
        let hostedID = BrowserLegacyExtensionWebsiteDataStore.identifier(forProfileID: profile.id)
        var removed: [UUID] = []
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            identifierProvider: { [profile.id, hostedID] },
            removeDataStore: { removed.append($0) },
            clearDataStore: { _ in XCTFail("No fallback should be needed") })
        try await remover.removePersistentDataStore(for: profile)
        XCTAssertEqual(removed, [profile.id, hostedID])
        XCTAssertNotEqual(hostedID, profile.id)
    }

    func testRemovalRetriesTheFullDelayedReleaseSequenceBeforeSucceeding() async throws {
        let profile = BrowsingProfile()
        var removalAttempts = 0
        var observedDelays: [Duration] = []
        let expectedDelays: [Duration] = [
            .milliseconds(10),
            .milliseconds(20),
            .milliseconds(40),
        ]
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            retryDelays: expectedDelays,
            identifierProvider: { [profile] in [profile.id] },
            removeDataStore: { _ in
                removalAttempts += 1
                if removalAttempts <= expectedDelays.count {
                    throw TestWebsiteDataStoreRemovalError.storeInUse
                }
            },
            sleep: { delay in
                observedDelays.append(delay)
            },
            clearDataStore: { _ in },
            acceptsClearedStoreFallback: false
        )

        try await remover.removePersistentDataStore(for: profile)

        XCTAssertEqual(removalAttempts, expectedDelays.count + 1)
        XCTAssertEqual(observedDelays, expectedDelays)
    }

    func testClearedStoreCanFinishTransactionAndQueueContainerRemoval() async throws {
        let profile = BrowsingProfile()
        var clearedIdentifiers: [UUID] = []
        var deferredIdentifiers: [UUID] = []
        let remover = WebKitBrowserWebsiteDataStoreRemover(
            retryDelays: [.milliseconds(10)],
            identifierProvider: { [profile] in [profile.id] },
            removeDataStore: { _ in
                throw TestWebsiteDataStoreRemovalError.storeInUse
            },
            sleep: { _ in },
            clearDataStore: { identifier in
                clearedIdentifiers.append(identifier)
            },
            recordDeferredCleanup: { identifier in
                deferredIdentifiers.append(identifier)
            }
        )

        try await remover.removePersistentDataStore(for: profile)

        XCTAssertEqual(clearedIdentifiers, [profile.id])
        XCTAssertEqual(deferredIdentifiers, [profile.id])
    }
}

private enum TestWebsiteDataStoreRemovalError: Error, Equatable {
    case storeInUse
}
