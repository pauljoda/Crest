import Foundation
import XCTest

@testable import Crest

/// The launcher's answer to a query, tested as data. Nothing here renders a
/// view: the sections, their order, their caps, and the ranking inside them are
/// the contract, and the card is only how they are drawn.
final class BrowserCommandPaletteResultTests: XCTestCase {

    // MARK: - Matching

    func testAMatchThatOpensTheTitleOutranksOneBuriedInsideIt() throws {
        let query = BrowserCommandPaletteQuery("git")

        let opening = try XCTUnwrap(
            BrowserCommandPaletteText.score(query, title: "GitHub")
        )
        let boundary = try XCTUnwrap(
            BrowserCommandPaletteText.score(query, title: "Apple GitHub Mirror")
        )
        let buried = try XCTUnwrap(
            BrowserCommandPaletteText.score(query, title: "Legitimate")
        )

        XCTAssertGreaterThan(opening, boundary)
        XCTAssertGreaterThan(boundary, buried)
    }

    func testASeparatorStartsAWordSoPathsAndHyphensMatchAsPrefixes() {
        let needle = BrowserCommandPaletteQuery("webkit").terms[0]

        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: needle, in: "webkit.org"),
            .prefix
        )
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(
                of: needle,
                in: "https://apple.com/webkit"
            ),
            .wordPrefix
        )
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: needle, in: "open-webkit-notes"),
            .wordPrefix
        )
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: needle, in: "prewebkit"),
            .contains
        )
        XCTAssertNil(
            BrowserCommandPaletteText.matchKind(of: needle, in: "web kit")
        )
    }

    func testMatchingIgnoresAsciiCaseAndScoresTheDetailLineLower() throws {
        let query = BrowserCommandPaletteQuery("APPLE")

        let inTitle = try XCTUnwrap(
            BrowserCommandPaletteText.score(query, title: "apple newsroom")
        )
        let inDetail = try XCTUnwrap(
            BrowserCommandPaletteText.score(
                query,
                title: "Newsroom",
                detail: "https://apple.com"
            )
        )

        XCTAssertGreaterThan(inTitle, inDetail)
    }

    func testEveryTermHasToLandSomewhereForACandidateToMatch() {
        let query = BrowserCommandPaletteQuery("apple keynote")

        XCTAssertNotNil(
            BrowserCommandPaletteText.score(
                query,
                title: "Keynote",
                detail: "https://apple.com/keynote"
            )
        )
        XCTAssertNil(
            BrowserCommandPaletteText.score(
                query,
                title: "Keynote",
                detail: "https://example.com/keynote"
            )
        )
    }

    func testArabicAndCJKTitlesMatchAndRankTheSameWayLatinOnesDo() throws {
        let arabic = BrowserCommandPaletteQuery("علامة")
        let opening = try XCTUnwrap(
            BrowserCommandPaletteText.score(arabic, title: "علامة التبويب الجديدة")
        )
        let later = try XCTUnwrap(
            BrowserCommandPaletteText.score(arabic, title: "التبويب علامة")
        )
        XCTAssertGreaterThan(opening, later)

        let japanese = BrowserCommandPaletteQuery("タブ")
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: japanese.terms[0], in: "タブを開く"),
            .prefix
        )
        // Nothing in a run of kana marks where a word began, so a match inside
        // one is honestly reported as a `contains` rather than a word start.
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: japanese.terms[0], in: "新しいタブ"),
            .contains
        )
    }

    // MARK: - Sections and order

    func testAnEmptyQueryListsOpenTabsAndAFewActionsAndNothingElse() {
        let space = makeSpace(
            tabs: [
                tab("Apple", "https://apple.com"),
                tab("GitHub", "https://github.com"),
                tab("WebKit", "https://webkit.org"),
                tab("Swift", "https://swift.org"),
                tab("Linear", "https://linear.app"),
                tab("Ignition", "https://example.com/ignition"),
            ],
            pinned: [tab("Pinned Apple", "https://apple.com/pinned", placement: .pinned)],
            history: [historyEntry("Apple Newsroom", "https://apple.com/newsroom")]
        )
        // A start page is a navigation draft, not a tab, and never a result.
        let withDraft = makeSpace(
            tabs: [BrowserTab.startPage()] + space.currentTabs,
            pinned: space.pinnedTabs
        )
        XCTAssertFalse(
            BrowserCommandPaletteResults.results(
                for: BrowserCommandPaletteInput(query: "", space: withDraft)
            )
            .contains { $0.title == BrowserTab.startPageTitle }
        )

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "   ",
                space: space,
                commands: [.newWindow, .reopenClosedTab, .showHistory, .showDownloads]
            )
        )

        XCTAssertEqual(
            results.filter { $0.section == .tabs }.count,
            BrowserCommandPaletteResultLimits.restingTabs
        )
        XCTAssertEqual(
            results.filter { $0.section == .actions }.count,
            BrowserCommandPaletteResultLimits.restingActions
        )
        XCTAssertFalse(results.contains(where: \.isIntent))
        // Tabs lead; the actions follow them rather than interleaving.
        XCTAssertEqual(
            results.compactMap(\.section),
            Array(repeating: BrowserCommandPaletteSection.tabs, count: 5)
                + Array(repeating: BrowserCommandPaletteSection.actions, count: 3)
        )
        // Resting, a pinned tab is just an open tab, exactly as it always was.
        XCTAssertEqual(results.first?.title, "Pinned Apple")
    }

    func testSearchIntentLeadsTabsActionsSavedAndHistory() {
        let space = makeSpace(
            tabs: [tab("Sidebar Notes", "https://example.com/notes")],
            pinned: [
                tab("Sidebar Design", "https://example.com/design", placement: .pinned)
            ],
            history: [historyEntry("Sidebar Patterns", "https://example.com/patterns")]
        )
        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "sidebar",
                space: space,
                commands: [.toggleSidebar]
            )
        )

        XCTAssertTrue(results.first?.isIntent == true)
        XCTAssertEqual(results.first?.title, "Search with Google")
        XCTAssertEqual(
            results.dropFirst().compactMap(\.section),
            [.tabs, .actions, .saved, .history]
        )
        XCTAssertEqual(results.count, 5)
    }

    func testRemoteSuggestionsAreLimitedDeduplicatedAndUseTheOrdinaryProviderURLBuilder() throws {
        let provider = BrowserCustomSearchProvider(
            name: "Kagi",
            searchURLTemplate: "https://kagi.com/search?q=%s",
            suggestionURLTemplate: "https://kagi.com/api/autosuggest?q=%s"
        ).provider
        let local = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "swift",
                space: makeSpace(tabs: []),
                searchProvider: provider
            )
        )

        let merged = BrowserCommandPaletteResults.insertingRemoteSuggestions(
            ["Swift", "  swift   concurrency ", "SWIFT CONCURRENCY", "SwiftUI", "WebKit"],
            query: "swift",
            provider: provider,
            into: local
        )
        let suggestions = merged.filter { $0.section == .searchSuggestions }

        XCTAssertEqual(suggestions.map(\.title), ["swift concurrency", "SwiftUI", "WebKit"])
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(
            suggestions.first?.target,
            .url(try XCTUnwrap(provider.searchURL(for: "swift concurrency")))
        )
        XCTAssertTrue(suggestions.allSatisfy { $0.searchProvider == provider })
        XCTAssertTrue(merged.first?.isIntent == true)
    }

    func testOpenSearchSuggestionParserFailsClosedForMalformedOrOversizedResponses() {
        let valid = Data(#"["crest",["Crest browser","crest browser","Crest SwiftUI"]]"#.utf8)

        XCTAssertEqual(
            BrowserSearchSuggestionResponseParser.suggestions(from: valid),
            ["Crest browser", "crest browser", "Crest SwiftUI"]
        )
        XCTAssertTrue(
            BrowserSearchSuggestionResponseParser.suggestions(
                from: Data(#"{"suggestions":["not OpenSearch"]}"#.utf8)
            ).isEmpty
        )
        XCTAssertTrue(
            BrowserSearchSuggestionResponseParser.suggestions(
                from: Data(
                    repeating: 0x20,
                    count: BrowserSearchSuggestionClient.maximumResponseByteCount + 1
                )
            ).isEmpty
        )
    }

    func testAQueryThatAlreadyReadsAsAURLPutsGoingThereFirst() throws {
        let space = makeSpace(tabs: [tab("Apple", "https://apple.com/store")])

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "apple.com", space: space)
        )

        let first = try XCTUnwrap(results.first)
        XCTAssertTrue(first.isIntent)
        XCTAssertEqual(first.title, "Open apple.com")
        XCTAssertEqual(first.target, .url(URL(string: "https://apple.com")!))
    }

    // MARK: - History

    func testHistoryIsCappedRankedByMatchThenRecencyAndNeverRepeatsAnOpenTab() {
        var history = [
            historyEntry("Swift Evolution", "https://swift.org/evolution"),
            historyEntry("Swift Forums", "https://forums.swift.org"),
            historyEntry("Swift Blog", "https://swift.org/blog"),
            historyEntry("Swift Book", "https://docs.swift.org/book"),
            historyEntry("Swift Package Index", "https://swiftpackageindex.com"),
            historyEntry("Swift Server", "https://swift.org/server"),
            historyEntry("Swift Testing", "https://swift.org/testing"),
            historyEntry("Learning Swift", "https://example.com/learning"),
        ]
        // The open tab's page is already on the list above it.
        history.insert(historyEntry("Swift Home", "https://swift.org"), at: 0)

        let space = makeSpace(
            tabs: [tab("Swift Home", "https://swift.org")],
            history: history
        )

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "swift", space: space)
        )
        let historyResults = results.filter { $0.section == .history }

        XCTAssertEqual(
            historyResults.count,
            BrowserCommandPaletteResultLimits.history
        )
        XCTAssertFalse(
            historyResults.contains { $0.target == .url(URL(string: "https://swift.org")!) },
            "A page already open as a tab must not be offered again as history."
        )
        // "Learning Swift" only matches mid-title, so it loses to the entries
        // that open with the term even though nothing separates them by age.
        XCTAssertFalse(historyResults.contains { $0.title == "Learning Swift" })
        XCTAssertEqual(historyResults.first?.title, "Swift Evolution")
        XCTAssertTrue(historyResults.allSatisfy { $0.trailing == "Open" })
    }

    // MARK: - Saved, pinned, and folders

    func testPinnedAndSavedTabsAppearTogetherAndSelectThemselves() {
        let pinned = tab("Design Review", "https://example.com/review", placement: .pinned)
        let saved = tab("Design System", "https://example.com/system", placement: .saved)
        let space = makeSpace(tabs: [], pinned: [pinned, saved])

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "design", space: space)
        )
        .filter { $0.section == .saved }

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(
            Set(results.map(\.target)),
            [
                .tab(tabAssignment(pinned, in: space)),
                .tab(tabAssignment(saved, in: space)),
            ]
        )
        XCTAssertTrue(results.allSatisfy { $0.trailing == "Switch to Tab" })
    }

    // MARK: - Actions

    func testOnlyRegisteredCommandsAreOfferedAndTheLauncherNeverOffersItself() {
        let space = makeSpace(tabs: [])

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "tab",
                space: space,
                commands: [.newTab, .openLocation, .duplicateTab, .archiveTab]
            )
        )
        .filter { $0.section == .actions }

        XCTAssertEqual(
            Set(results.map(\.target)),
            [.command(.duplicateTab), .command(.archiveTab)]
        )
        XCTAssertFalse(results.contains { $0.target == .command(.newTab) })
        XCTAssertFalse(results.contains { $0.target == .command(.openLocation) })
    }

    // MARK: - The selected tab

    func testTheTabAlreadyOnScreenIsNotOfferedAsSomewhereToGo() {
        let current = tab("Apple", "https://apple.com")
        let space = makeSpace(tabs: [current, tab("Apple Support", "https://apple.com/support")])

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "apple",
                space: space,
                selectedTabID: current.id
            )
        )

        XCTAssertFalse(
            results.contains {
                $0.target == .tab(tabAssignment(current, in: space))
            }
        )
    }

    // MARK: - Helpers

    private func tab(
        _ title: String,
        _ url: String,
        placement: TabPlacement = .current,
        folderID: FolderID? = nil
    ) -> BrowserTab {
        BrowserTab(
            title: title,
            url: URL(string: url),
            placement: placement,
            folderID: folderID
        )
    }

    private func tabAssignment(
        _ tab: BrowserTab,
        in space: BrowserSpace
    ) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }

    private func historyEntry(_ title: String, _ url: String) -> BrowserHistoryEntry {
        BrowserHistoryEntry(
            url: URL(string: url)!,
            title: title,
            firstVisitedAt: .now,
            lastVisitedAt: .now
        )
    }

    private func makeSpace(
        name: String = "Work",
        tabs: [BrowserTab],
        pinned: [BrowserTab] = [],
        folders: [BrowserFolder] = [],
        history: [BrowserHistoryEntry] = []
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "circle",
            accent: .indigo,
            folders: folders,
            tabs: pinned + tabs,
            history: history,
            selectedTabID: tabs.first?.id
        )
    }
}

@MainActor
final class BrowserCommandPaletteModelPerformanceTests: XCTestCase {
    func testQueryChangesKeepTheLastPublishedRowsUntilReplacementIsReady() async throws {
        let tab = BrowserTab(
            title: "Current Result",
            url: try XCTUnwrap(URL(string: "https://example.com/current")),
            placement: .current
        )
        let secondaryTab = BrowserTab(
            title: "Secondary Result",
            url: try XCTUnwrap(URL(string: "https://example.com/secondary")),
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Performance",
            symbol: "speedometer",
            accent: .indigo,
            folders: [],
            tabs: [tab, secondaryTab],
            history: [],
            selectedTabID: nil
        )
        var openedURL: URL?
        let model = BrowserCommandPaletteModel(
            space: space,
            selectedTabID: nil,
            initialQuery: "",
            commands: nil,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            openURL: { _, url in
                openedURL = url
                return true
            },
            dismiss: {}
        )
        let publishedResults = model.results
        let publishedGroups = model.resultGroups

        model.query = "replacement query"

        XCTAssertEqual(model.results, publishedResults)
        XCTAssertEqual(model.resultGroups, publishedGroups)

        model.moveSelection(by: 1)
        model.selectResult(at: 1)
        XCTAssertEqual(model.selectedResultIndex, 0)

        if let staleResult = publishedResults.first {
            model.activate(staleResult)
        }
        XCTAssertNil(openedURL)

        for _ in 0..<200 {
            if model.results.last?.subtitle == "replacement query" {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.results.last?.subtitle, "replacement query")
        XCTAssertNotEqual(model.resultGroups, publishedGroups)
    }

}
