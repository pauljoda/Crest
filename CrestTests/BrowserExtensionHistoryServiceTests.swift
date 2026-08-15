import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionHistoryServiceTests: XCTestCase {
    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func entry(
        _ urlString: String,
        title: String,
        lastVisitedAt: Date,
        firstVisitedAt: Date? = nil,
        visitCount: Int = 1
    ) throws -> BrowserHistoryEntry {
        BrowserHistoryEntry(
            url: try XCTUnwrap(URL(string: urlString)),
            title: title,
            firstVisitedAt: firstVisitedAt ?? lastVisitedAt,
            lastVisitedAt: lastVisitedAt,
            visitCount: visitCount
        )
    }

    private func makeStore(
        history: [BrowserHistoryEntry]
    ) throws -> (store: BrowserStore, scope: BrowserSpaceRuntimeAssignment) {
        var session = BrowserSession.preview
        let index = try XCTUnwrap(
            session.spaces.firstIndex(where: { $0.id == session.selectedSpaceID })
        )
        session.spaces[index].history = history
        let store = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let scope = BrowserSpaceRuntimeAssignment(
            space: try XCTUnwrap(store.selectedSpace)
        )
        return (store, scope)
    }

    private func days(_ count: Double) -> Date {
        Self.referenceDate.addingTimeInterval(-count * 86_400)
    }

    // MARK: - Search

    func testSearchMatchesTitleAndURLMostRecentFirst() throws {
        let (store, scope) = try makeStore(history: [
            try entry(
                "https://swift.org/blog",
                title: "Swift Blog",
                lastVisitedAt: days(1)
            ),
            try entry(
                "https://example.com/swift-tips",
                title: "Tips",
                lastVisitedAt: days(2)
            ),
            try entry(
                "https://example.com/unrelated",
                title: "Nothing",
                lastVisitedAt: days(3)
            ),
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)

        let results = service.search(
            BrowserExtensionHistoryQuery(text: "swift"),
            in: scope
        )

        XCTAssertEqual(
            results.map(\.url.absoluteString),
            ["https://swift.org/blog", "https://example.com/swift-tips"]
        )
    }

    func testSearchHonorsTheHalfOpenTimeWindowAndResultCap() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1)),
            try entry("https://b.example", title: "B", lastVisitedAt: days(2)),
            try entry("https://c.example", title: "C", lastVisitedAt: days(3)),
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)

        let windowed = service.search(
            BrowserExtensionHistoryQuery(
                startTime: days(3),
                endTime: days(1)
            ),
            in: scope
        )
        let capped = service.search(
            BrowserExtensionHistoryQuery(maximumResults: 2),
            in: scope
        )
        let none = service.search(
            BrowserExtensionHistoryQuery(maximumResults: 0),
            in: scope
        )

        // days(1) is the exclusive upper bound, days(3) the inclusive lower one.
        XCTAssertEqual(
            windowed.map(\.title),
            ["B", "C"]
        )
        XCTAssertEqual(capped.map(\.title), ["A", "B"])
        XCTAssertTrue(none.isEmpty)
    }

    func testTypedCountIsAlwaysZero() throws {
        let (store, scope) = try makeStore(history: [
            try entry(
                "https://a.example",
                title: "A",
                lastVisitedAt: days(1),
                visitCount: 12
            )
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)

        let item = try XCTUnwrap(
            service.search(BrowserExtensionHistoryQuery(), in: scope).first
        )
        XCTAssertEqual(item.visitCount, 12)
        XCTAssertEqual(item.typedCount, 0)
    }

    // MARK: - Space scoping

    func testAReplacedSpaceResolvesToNothingRatherThanTheSelectedSpace() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1))
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)
        let foreignScope = BrowserSpaceRuntimeAssignment(
            spaceID: scope.spaceID,
            profileID: UUID()
        )

        XCTAssertTrue(
            service.search(BrowserExtensionHistoryQuery(), in: foreignScope).isEmpty
        )
        XCTAssertTrue(service.topSites(limit: 5, in: foreignScope).isEmpty)
        XCTAssertFalse(service.deleteAll(in: foreignScope))
        XCTAssertFalse(
            service.addURL(
                try XCTUnwrap(URL(string: "https://b.example")),
                title: "B",
                in: foreignScope
            )
        )
        XCTAssertEqual(store.selectedSpace?.history.count, 1)
    }

    func testWritesTouchOnlyTheAddressedSpace() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1))
        ])
        let otherSpace = try XCTUnwrap(
            store.session.spaces.first { $0.id != scope.spaceID }
        )
        store.session.recordVisit(
            url: try XCTUnwrap(URL(string: "https://kept.example")),
            title: "Kept",
            in: otherSpace.id,
            at: days(1)
        )
        let service = BrowserStoreExtensionHistoryService(store: store)

        XCTAssertTrue(service.deleteAll(in: scope))

        XCTAssertEqual(store.selectedSpace?.history.count, 0)
        XCTAssertEqual(
            store.session.space(id: otherSpace.id)?.history.map(\.title),
            ["Kept"]
        )
    }

    func testDeletionNarrowsThePersistedSaveScope() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        var session = BrowserSession.preview
        let index = try XCTUnwrap(
            session.spaces.firstIndex(where: { $0.id == session.selectedSpaceID })
        )
        session.spaces[index].history = [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1))
        ]
        let store = BrowserStore(session: session, persistence: persistence)
        let scope = BrowserSpaceRuntimeAssignment(
            space: try XCTUnwrap(store.selectedSpace)
        )
        let service = BrowserStoreExtensionHistoryService(store: store)

        XCTAssertTrue(
            service.deleteURL(
                try XCTUnwrap(URL(string: "https://a.example")),
                in: scope
            )
        )

        XCTAssertEqual(persistence.savedScopes.last, .history(in: scope.spaceID))
    }

    // MARK: - Visits

    func testVisitsReportTheTwoEndpointsCrestCanAttestTo() throws {
        let (store, scope) = try makeStore(history: [
            try entry(
                "https://a.example/page",
                title: "A",
                lastVisitedAt: days(1),
                firstVisitedAt: days(10),
                visitCount: 30
            ),
            try entry("https://b.example", title: "B", lastVisitedAt: days(2)),
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)

        let repeated = service.visits(
            for: try XCTUnwrap(URL(string: "https://a.example/page")),
            in: scope
        )
        let single = service.visits(
            for: try XCTUnwrap(URL(string: "https://b.example")),
            in: scope
        )
        let unknown = service.visits(
            for: try XCTUnwrap(URL(string: "https://missing.example")),
            in: scope
        )

        XCTAssertEqual(repeated.map(\.visitTime), [days(10), days(1)])
        XCTAssertEqual(repeated.map(\.transition), [.link, .link])
        XCTAssertEqual(single.map(\.visitTime), [days(2)])
        XCTAssertTrue(unknown.isEmpty)
    }

    /// A fragment is stripped on the way into history, so a lookup that still
    /// carries one must resolve to the stored row.
    func testVisitsNormalizeTheRequestedURL() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example/page", title: "A", lastVisitedAt: days(1))
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)

        let visits = service.visits(
            for: try XCTUnwrap(URL(string: "https://a.example/page#section")),
            in: scope
        )

        XCTAssertEqual(visits.count, 1)
    }

    // MARK: - Mutations

    func testAddURLRecordsAVisitAndRejectsUnsupportedSchemes() throws {
        let (store, scope) = try makeStore(history: [])
        let service = BrowserStoreExtensionHistoryService(store: store)

        let added = service.addURL(
            try XCTUnwrap(URL(string: "https://a.example/page")),
            title: "Added",
            in: scope
        )
        let rejected = service.addURL(
            try XCTUnwrap(URL(string: "ftp://a.example/page")),
            title: "Rejected",
            in: scope
        )

        XCTAssertTrue(added)
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.selectedSpace?.history.map(\.title), ["Added"])
    }

    func testDeleteURLReportsWhetherAnEntryWasPresent() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1))
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)
        let url = try XCTUnwrap(URL(string: "https://a.example"))

        XCTAssertTrue(service.deleteURL(url, in: scope))
        XCTAssertFalse(service.deleteURL(url, in: scope))
        XCTAssertEqual(store.selectedSpace?.history.count, 0)
    }

    func testDeleteRangeRemovesTheHalfOpenWindowOnly() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1)),
            try entry("https://b.example", title: "B", lastVisitedAt: days(2)),
            try entry("https://c.example", title: "C", lastVisitedAt: days(3)),
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)

        let removed = service.deleteRange(
            from: days(3),
            until: days(1),
            in: scope
        )

        XCTAssertTrue(removed)
        XCTAssertEqual(store.selectedSpace?.history.map(\.title), ["A"])
    }

    func testDeleteRangeReportsFalseWhenNothingFallsInside() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1))
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)

        XCTAssertFalse(
            service.deleteRange(from: days(90), until: days(30), in: scope)
        )
        XCTAssertEqual(store.selectedSpace?.history.count, 1)
    }

    // MARK: - Top sites

    func testTopSitesWeighVisitCountByRecency() throws {
        let (store, scope) = try makeStore(history: [
            try entry(
                "https://stale.example",
                title: "Stale",
                lastVisitedAt: days(200),
                visitCount: 80
            ),
            try entry(
                "https://daily.example",
                title: "Daily",
                lastVisitedAt: days(1),
                visitCount: 20
            ),
            try entry(
                "https://weekly.example",
                title: "Weekly",
                lastVisitedAt: days(10),
                visitCount: 20
            ),
        ])
        let service = BrowserStoreExtensionHistoryService(
            store: store,
            now: { Self.referenceDate }
        )

        let sites = service.topSites(limit: 3, in: scope)

        // Daily: 20 x 100. Weekly: 20 x 70. Stale: 80 x 10 — heaviest raw count,
        // lowest frecency.
        XCTAssertEqual(sites.map(\.title), ["Daily", "Weekly", "Stale"])
    }

    func testTopSitesRespectTheLimit() throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1)),
            try entry("https://b.example", title: "B", lastVisitedAt: days(2)),
        ])
        let service = BrowserStoreExtensionHistoryService(
            store: store,
            now: { Self.referenceDate }
        )

        XCTAssertEqual(service.topSites(limit: 1, in: scope).count, 1)
        XCTAssertTrue(service.topSites(limit: 0, in: scope).isEmpty)
    }

    // MARK: - Change events

    /// Ordinary browsing never calls this service, so the event has to be
    /// derived from Observation rather than raised by a mutation entry point.
    func testOrdinaryBrowsingRaisesAVisitedEvent() async throws {
        let (store, scope) = try makeStore(history: [])
        let service = BrowserStoreExtensionHistoryService(store: store)
        var changes = service.changes(in: scope).makeAsyncIterator()

        store.recordVisit(
            url: try XCTUnwrap(URL(string: "https://a.example/page")),
            title: "Browsed",
            matching: scope
        )

        let change = await changes.next()
        guard case .visited(let item) = change else {
            return XCTFail("Expected a visited change, got \(String(describing: change)).")
        }
        XCTAssertEqual(item.url.absoluteString, "https://a.example/page")
        XCTAssertEqual(item.title, "Browsed")
    }

    func testClearingHistoryRaisesRemovedAll() async throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1)),
            try entry("https://b.example", title: "B", lastVisitedAt: days(2)),
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)
        var changes = service.changes(in: scope).makeAsyncIterator()

        XCTAssertTrue(service.deleteAll(in: scope))

        let change = await changes.next()
        XCTAssertEqual(change, .removedAll)
    }

    func testDeletingOneURLRaisesARemovedEventNamingIt() async throws {
        let (store, scope) = try makeStore(history: [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1)),
            try entry("https://b.example", title: "B", lastVisitedAt: days(2)),
        ])
        let service = BrowserStoreExtensionHistoryService(store: store)
        var changes = service.changes(in: scope).makeAsyncIterator()

        XCTAssertTrue(
            service.deleteURL(
                try XCTUnwrap(URL(string: "https://a.example")),
                in: scope
            )
        )

        let change = await changes.next()
        XCTAssertEqual(
            change,
            .removed(urls: [try XCTUnwrap(URL(string: "https://a.example"))])
        )
    }

    func testAnUnresolvableScopeFinishesTheChangeStreamImmediately() async throws {
        let (store, scope) = try makeStore(history: [])
        let service = BrowserStoreExtensionHistoryService(store: store)
        let foreignScope = BrowserSpaceRuntimeAssignment(
            spaceID: scope.spaceID,
            profileID: UUID()
        )

        var changes = service.changes(in: foreignScope).makeAsyncIterator()

        let change = await changes.next()
        XCTAssertNil(change)
    }

    // MARK: - Diff policy

    func testTheDiffTreatsAnAdditionalVisitAsAVisitedChange() throws {
        let before = [
            try entry(
                "https://a.example",
                title: "A",
                lastVisitedAt: days(5),
                visitCount: 1
            )
        ]
        let after = [
            try entry(
                "https://a.example",
                title: "A",
                lastVisitedAt: days(1),
                firstVisitedAt: days(5),
                visitCount: 2
            )
        ]

        let changes = BrowserStoreExtensionHistoryService.changes(
            from: before,
            to: after
        )

        XCTAssertEqual(changes.count, 1)
        guard case .visited(let item) = try XCTUnwrap(changes.first) else {
            return XCTFail("Expected a visited change.")
        }
        XCTAssertEqual(item.visitCount, 2)
    }

    func testTheDiffIsSilentWhenNothingChanged() throws {
        let history = [
            try entry("https://a.example", title: "A", lastVisitedAt: days(1))
        ]

        XCTAssertTrue(
            BrowserStoreExtensionHistoryService.changes(
                from: history,
                to: history
            ).isEmpty
        )
    }

    // MARK: - In-memory double

    func testTheInMemoryDoubleMatchesTheAdapterQuerySemantics() throws {
        let scope = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let history = [
            try entry(
                "https://swift.org/blog",
                title: "Swift Blog",
                lastVisitedAt: days(1)
            ),
            try entry("https://example.com", title: "Example", lastVisitedAt: days(2)),
        ]
        let double = InMemoryBrowserExtensionHistoryStore(
            histories: [scope: history],
            now: Self.referenceDate
        )
        let (store, storeScope) = try makeStore(history: history)
        let service = BrowserStoreExtensionHistoryService(
            store: store,
            now: { Self.referenceDate }
        )
        let query = BrowserExtensionHistoryQuery(text: "swift")

        XCTAssertEqual(
            double.search(query, in: scope).map(\.url),
            service.search(query, in: storeScope).map(\.url)
        )
        XCTAssertEqual(
            double.topSites(limit: 5, in: scope).map(\.url),
            service.topSites(limit: 5, in: storeScope).map(\.url)
        )
    }

    func testTheInMemoryDoubleRefusesAnUnregisteredScope() throws {
        let double = InMemoryBrowserExtensionHistoryStore()
        let scope = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )

        XCTAssertFalse(
            double.addURL(
                try XCTUnwrap(URL(string: "https://a.example")),
                title: "A",
                in: scope
            )
        )
        XCTAssertTrue(
            double.search(BrowserExtensionHistoryQuery(), in: scope).isEmpty
        )
    }

    func testTheInMemoryDoublePublishesItsOwnMutations() async throws {
        let scope = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let double = InMemoryBrowserExtensionHistoryStore(
            histories: [scope: []],
            now: Self.referenceDate
        )
        var changes = double.changes(in: scope).makeAsyncIterator()

        XCTAssertTrue(
            double.addURL(
                try XCTUnwrap(URL(string: "https://a.example")),
                title: "A",
                in: scope
            )
        )

        let change = await changes.next()
        guard case .visited(let item) = change else {
            return XCTFail("Expected a visited change, got \(String(describing: change)).")
        }
        XCTAssertEqual(item.title, "A")
    }
}
