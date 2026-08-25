import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteModelActivationTests: XCTestCase {
    func testActivationCarriesExactAssignmentsAndRejectsAStaleSource() throws {
        let sourceTab = BrowserTab.startPage(
            id: TabID(rawValue: uuid(0x11)),
            lastActivatedAt: fixedDate
        )
        let targetTab = BrowserTab(
            id: TabID(rawValue: uuid(0x12)),
            title: "Target",
            url: URL(fileURLWithPath: "/palette-target"),
            placement: .current,
            lastActivatedAt: fixedDate
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: uuid(0x21)),
            profile: BrowsingProfile(id: uuid(0x31)),
            name: "Palette",
            symbol: "command",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab, targetTab],
            selectedTabID: sourceTab.id
        )
        var sourceIsAvailable = false
        var capturedSource: BrowserTabRuntimeAssignment?
        var capturedTarget: BrowserTabRuntimeAssignment?
        var dismissalCount = 0
        let model = BrowserCommandPaletteModel(
            space: space,
            selectedTabID: sourceTab.id,
            initialQuery: "",
            commands: nil,
            isSourceAvailable: { _ in sourceIsAvailable },
            selectTab: { source, target in
                capturedSource = source
                capturedTarget = target
                return true
            },
            openURL: { _, _ in false },
            dismiss: { dismissalCount += 1 }
        )
        let targetResult = try XCTUnwrap(
            model.results.first { $0.faviconTabID == targetTab.id }
        )

        model.activate(targetResult)
        XCTAssertNil(capturedSource)
        XCTAssertNil(capturedTarget)
        XCTAssertEqual(dismissalCount, 0)

        sourceIsAvailable = true
        model.activate(targetResult)

        XCTAssertEqual(
            capturedSource,
            BrowserTabRuntimeAssignment(
                tabID: sourceTab.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
        XCTAssertEqual(
            capturedTarget,
            BrowserTabRuntimeAssignment(
                tabID: targetTab.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
        XCTAssertEqual(dismissalCount, 1)
    }

    func testSuggestionsStayOffUntilTheSpaceOptsIn() async {
        let fixture = makePaletteFixture(searchSuggestionsEnabled: false)
        let recorder = SuggestionRecorder(results: ["remote result"])
        let model = makeModel(fixture: fixture, recorder: recorder)

        model.query = "crest browser"
        await model.waitForPendingResults()

        let queries = await recorder.queries
        XCTAssertTrue(queries.isEmpty)
        XCTAssertFalse(model.results.contains { $0.section == .searchSuggestions })
    }

    func testPrivateBrowsingNeverSendsAnOptedInQuery() async {
        let fixture = makePaletteFixture(searchSuggestionsEnabled: true)
        let recorder = SuggestionRecorder(results: ["remote result"])
        let model = makeModel(
            fixture: fixture,
            isPrivateBrowsing: true,
            recorder: recorder
        )

        model.query = "private words"
        await model.waitForPendingResults()

        let queries = await recorder.queries
        XCTAssertTrue(queries.isEmpty)
        XCTAssertFalse(model.results.contains { $0.section == .searchSuggestions })
    }

    func testOptedInSuggestionsCancelAndIgnoreStaleResponsesWithoutReorderingSelection() async {
        let fixture = makePaletteFixture(searchSuggestionsEnabled: true)
        let recorder = SuggestionRecorder(
            resultsByQuery: [
                "first words": ["stale suggestion"],
                "latest words": ["latest suggestion"],
            ],
            delayByQuery: ["first words": .milliseconds(80)]
        )
        let model = makeModel(fixture: fixture, recorder: recorder)

        model.query = "first words"
        await Task.yield()
        model.query = "latest words"
        await model.waitForPendingResults()

        XCTAssertEqual(
            model.results.filter { $0.section == .searchSuggestions }.map(\.title),
            ["latest suggestion"]
        )
        XCTAssertFalse(model.results.contains { $0.title == "stale suggestion" })
        XCTAssertEqual(model.selectedResultIndex, 0)
    }

    func testSuggestionFailureLeavesTheAlreadyPublishedLocalResultsUsable() async {
        let fixture = makePaletteFixture(searchSuggestionsEnabled: true)
        let model = BrowserCommandPaletteModel(
            space: fixture.space,
            selectedTabID: fixture.sourceTab.id,
            initialQuery: "",
            commands: nil,
            isPrivateBrowsing: false,
            suggestionDebounce: .zero,
            fetchSuggestions: { _, _ in throw SuggestionTestError.failed },
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in false },
            openURL: { _, _ in false },
            dismiss: {}
        )

        model.query = "crest"
        await model.waitForPendingResults()

        XCTAssertEqual(model.results.first?.title, "Search with Google")
        XCTAssertTrue(model.results.contains { $0.title == "Local Crest tab" })
        XCTAssertFalse(model.results.contains { $0.section == .searchSuggestions })
    }

    func testSuggestionNetworkConfigurationCarriesNoCookiesOrSharedCache() {
        let configuration = BrowserSearchSuggestionClient.sessionConfiguration

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertLessThanOrEqual(configuration.timeoutIntervalForRequest, 5)
    }

    private func makePaletteFixture(
        searchSuggestionsEnabled: Bool
    ) -> (space: BrowserSpace, sourceTab: BrowserTab) {
        let sourceTab = BrowserTab.startPage(
            id: TabID(rawValue: uuid(0x41)),
            lastActivatedAt: fixedDate
        )
        let localTab = BrowserTab(
            id: TabID(rawValue: uuid(0x42)),
            title: "Local Crest tab",
            url: URL(string: "https://example.com/crest"),
            placement: .current,
            lastActivatedAt: fixedDate
        )
        var preferences = BrowserSpaceBrowsingPreferences.default
        preferences.searchSuggestionsEnabled = searchSuggestionsEnabled
        let space = BrowserSpace(
            id: SpaceID(rawValue: uuid(0x51)),
            profile: BrowsingProfile(id: uuid(0x61)),
            name: "Suggestions",
            symbol: "magnifyingglass",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab, localTab],
            browsingPreferences: preferences,
            selectedTabID: sourceTab.id
        )
        return (space, sourceTab)
    }

    private func makeModel(
        fixture: (space: BrowserSpace, sourceTab: BrowserTab),
        isPrivateBrowsing: Bool = false,
        recorder: SuggestionRecorder
    ) -> BrowserCommandPaletteModel {
        BrowserCommandPaletteModel(
            space: fixture.space,
            selectedTabID: fixture.sourceTab.id,
            initialQuery: "",
            commands: nil,
            isPrivateBrowsing: isPrivateBrowsing,
            suggestionDebounce: .zero,
            fetchSuggestions: { query, provider in
                await recorder.suggestions(query: query, provider: provider)
            },
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in false },
            openURL: { _, _ in false },
            dismiss: {}
        )
    }

    private var fixedDate: Date {
        Date(timeIntervalSinceReferenceDate: 600)
    }

    private func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x4D, 0x4F, 0x44, finalByte
            ))
    }
}

private enum SuggestionTestError: Error {
    case failed
}

private actor SuggestionRecorder {
    private(set) var queries: [String] = []
    private let resultsByQuery: [String: [String]]
    private let delayByQuery: [String: Duration]

    init(
        results: [String] = [],
        resultsByQuery: [String: [String]] = [:],
        delayByQuery: [String: Duration] = [:]
    ) {
        self.resultsByQuery = resultsByQuery.merging(["*": results]) { current, _ in current }
        self.delayByQuery = delayByQuery
    }

    func suggestions(
        query: String,
        provider: BrowserSearchProvider
    ) async -> [String] {
        queries.append(query)
        if let delay = delayByQuery[query] {
            try? await Task.sleep(for: delay)
        }
        return resultsByQuery[query] ?? resultsByQuery["*"] ?? []
    }
}
