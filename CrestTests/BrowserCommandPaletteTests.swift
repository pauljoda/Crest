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

    // MARK: - Text that is not ASCII

    func testScoringSurvivesEveryScriptItCanBeHandedWithoutTrapping() {
        // Crest ships Arabic and lets anyone rename a tab, so none of this is
        // exotic input — it is Tuesday. The point of the assertion is that the
        // call returns at all.
        let haystacks = [
            "علامة التبويب الجديدة",
            "新しいタブ",
            "简体中文文档",
            "Ελληνικά Σημειώσεις",
            "Здравствуйте",
            "🚀 Launch Notes",
            "Reading › Long Reads › Café",
            "naïve café —— résumé",
            "",
        ]
        let queries = [
            "علامة",
            "新しい",
            "文档",
            "ΣΗΜΕΙΩΣΕΙΣ",
            "здрав",
            "🚀",
            "café",
            "reading",
            "a b",
            "",
        ]

        for raw in queries {
            let query = BrowserCommandPaletteQuery(raw)
            for haystack in haystacks {
                _ = BrowserCommandPaletteText.score(
                    query,
                    title: haystack,
                    detail: "https://example.com/" + haystack
                )
            }
        }
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

    func testNonAsciiSeparatorsAndEmojiStartAWordJustLikeASpaceDoes() {
        let needle = BrowserCommandPaletteQuery("reads").terms[0]

        // The folder path separator Crest joins names with.
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: needle, in: "Reading › Reads"),
            .wordPrefix
        )
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(
                of: BrowserCommandPaletteQuery("launch").terms[0],
                in: "🚀Launch"
            ),
            .wordPrefix
        )
        // An em dash and a non-breaking space are boundaries too.
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: needle, in: "Long—Reads"),
            .wordPrefix
        )
        XCTAssertEqual(
            BrowserCommandPaletteText.matchKind(of: needle, in: "Long\u{00A0}Reads"),
            .wordPrefix
        )
    }

    func testCaseFoldingReachesBeyondAsciiIntoGreekAndCyrillic() {
        XCTAssertNotNil(
            BrowserCommandPaletteText.score(
                BrowserCommandPaletteQuery("ΣΗΜΕΙΩΣΕΙΣ"),
                title: "σημειωσεις"
            )
        )
        XCTAssertNotNil(
            BrowserCommandPaletteText.score(
                BrowserCommandPaletteQuery("здравствуйте"),
                title: "ЗДРАВСТВУЙТЕ"
            )
        )
    }

    func testAMixedScriptQueryStillRequiresEveryTermToLand() {
        let query = BrowserCommandPaletteQuery("apple علامة")

        XCTAssertNotNil(
            BrowserCommandPaletteText.score(
                query,
                title: "علامة Apple التبويب"
            )
        )
        XCTAssertNil(
            BrowserCommandPaletteText.score(query, title: "Apple Newsroom")
        )
    }

    func testTheWholeResultListBuildsFromNonAsciiTabsHistoryAndFolders() {
        let folder = BrowserFolder(title: "قراءة")
        let space = makeSpace(
            name: "العمل",
            tabs: [tab("علامة التبويب الجديدة", "https://example.com/ar")],
            pinned: [
                tab(
                    "علامة محفوظة",
                    "https://example.com/saved",
                    placement: .saved,
                    folderID: folder.id
                )
            ],
            folders: [folder],
            history: [historyEntry("علامة في السجل", "https://example.com/history")]
        )
        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "علامة",
                space: space,
                commands: [.toggleSidebar]
            )
        )

        XCTAssertEqual(
            results.compactMap(\.section),
            [.tabs, .saved, .history]
        )
        XCTAssertEqual(results.first?.title, "Search with Google")
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

    func testSearchIntentCarriesTheSelectedProviderForBrandedPresentation() throws {
        let space = makeSpace(tabs: [])

        for provider in BrowserSearchProvider.allCases {
            let result = try XCTUnwrap(
                BrowserCommandPaletteResults.results(
                    for: BrowserCommandPaletteInput(
                        query: "private search",
                        space: space,
                        searchProvider: provider
                    )
                ).first
            )

            XCTAssertEqual(result.searchProvider, provider)
        }
    }

    func testRemoteSuggestionsAreLimitedDeduplicatedAndUseTheOrdinaryProviderURLBuilder() throws {
        let provider = try BrowserCustomSearchProvider(
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

    func testEmbeddedPaletteIdentityChangesWithItsSpaceSearchContract() throws {
        var space = makeSpace(tabs: [])
        let original = BrowserCommandPalettePresentationIdentity(
            space: space,
            source: nil
        )
        var preferences = space.browsingPreferences
        let custom = try BrowserCustomSearchProvider(
            name: "Kagi",
            searchURLTemplate: "https://kagi.com/search?q=%s",
            suggestionURLTemplate: "https://kagi.com/api/autosuggest?q=%s"
        )
        try preferences.upsertCustomSearchProvider(custom)
        preferences.searchProvider = custom.provider
        space.browsingPreferences = preferences
        let customProvider = BrowserCommandPalettePresentationIdentity(
            space: space,
            source: nil
        )

        preferences.searchSuggestionsEnabled = true
        space.browsingPreferences = preferences
        let suggestionsEnabled = BrowserCommandPalettePresentationIdentity(
            space: space,
            source: nil
        )

        XCTAssertNotEqual(original, customProvider)
        XCTAssertNotEqual(customProvider, suggestionsEnabled)
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

    func testRecencyBreaksTiesBetweenEquallyGoodHistoryMatches() {
        let space = makeSpace(
            tabs: [],
            history: [
                historyEntry("Notes Later", "https://later.example.com/notes"),
                historyEntry("Notes Earlier", "https://earlier.example.com/notes"),
            ]
        )

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "notes", space: space)
        )
        .filter { $0.section == .history }

        XCTAssertEqual(results.map(\.title), ["Notes Later", "Notes Earlier"])
    }

    func testHistorySearchStopsAtTheFreshestMatchesRatherThanScanningEverything() {
        let matching = (0..<400).map {
            historyEntry("Ledger \($0)", "https://example.com/ledger/\($0)")
        }
        let space = makeSpace(tabs: [], history: matching)

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "ledger", space: space)
        )
        .filter { $0.section == .history }

        // Every entry matches equally well, so what survives is simply the most
        // recent handful — the scan never had to reach the four hundredth.
        XCTAssertEqual(
            results.map(\.title),
            (0..<BrowserCommandPaletteResultLimits.history).map { "Ledger \($0)" }
        )
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

    func testAMatchingFolderOpensTheFirstTabItHoldsAndSaysSoOnTheRow() {
        let folder = BrowserFolder(title: "Reading")
        let first = tab(
            "Long Article",
            "https://example.com/long",
            placement: .saved,
            folderID: folder.id
        )
        let second = tab(
            "Short Article",
            "https://example.com/short",
            placement: .saved,
            folderID: folder.id
        )
        let space = makeSpace(tabs: [], pinned: [first, second], folders: [folder])

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "reading", space: space)
        )
        let folderResult = results.first { $0.id.hasPrefix("folder-") }

        XCTAssertEqual(folderResult?.title, "Reading")
        XCTAssertEqual(folderResult?.subtitle, "2 tabs")
        XCTAssertEqual(folderResult?.trailing, "Open First Tab")
        XCTAssertEqual(
            folderResult?.target,
            .tab(tabAssignment(first, in: space))
        )
    }

    func testAnEmptyFolderIsNotOfferedBecauseThereIsNothingToOpen() {
        let folder = BrowserFolder(title: "Reading")
        let space = makeSpace(tabs: [], folders: [folder])

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "reading", space: space)
        )

        XCTAssertFalse(results.contains { $0.id.hasPrefix("folder-") })
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

    func testAShellThatRegistersNothingSimplyHasNoActionSection() {
        let space = makeSpace(tabs: [tab("Reader", "https://example.com/reader")])

        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(query: "reader", space: space)
        )

        XCTAssertFalse(results.contains { $0.section == .actions })
    }

    func testAnActionRowCarriesItsSectionNameAndAGlyph() {
        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "sidebar",
                space: makeSpace(tabs: []),
                commands: [.toggleSidebar]
            )
        )
        let action = results.first { $0.section == .actions }

        XCTAssertEqual(action?.title, BrowserShortcutCommand.toggleSidebar.title)
        XCTAssertEqual(action?.subtitle, BrowserShortcutSection.view.title)
        XCTAssertEqual(action?.symbol, "sidebar.leading")
    }

    // MARK: - Identity

    func testEveryResultCarriesADistinctIdentitySoTheListCanAnimate() {
        let folder = BrowserFolder(title: "Apple Reading")
        let space = makeSpace(
            tabs: [tab("Apple Store", "https://apple.com/store")],
            pinned: [
                tab("Apple Support", "https://apple.com/support", placement: .pinned),
                tab(
                    "Apple Notes",
                    "https://apple.com/notes",
                    placement: .saved,
                    folderID: folder.id
                ),
            ],
            folders: [folder],
            history: [historyEntry("Apple Newsroom", "https://apple.com/newsroom")]
        )
        let results = BrowserCommandPaletteResults.results(
            for: BrowserCommandPaletteInput(
                query: "apple",
                space: space,
                commands: [.toggleSidebar]
            )
        )

        XCTAssertEqual(Set(results.map(\.id)).count, results.count)
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

/// The card's geometry. The launcher sizes itself to its content until it has to
/// scroll, and a sectioned list has headers to pay for.
final class BrowserCommandPaletteLayoutTests: XCTestCase {
    func testASectionedListPaysForEveryHeaderAndEveryGapBetweenSections() {
        // One five-row section is the shape the tab-only launcher always had.
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                sectionRowCounts: [5],
                includesPrimaryAction: false
            ),
            BrowserCommandPaletteLayout.resultAreaHeight(
                tabCount: 5,
                includesPrimaryAction: false
            )
        )
        // 28 outer + (17 + 6 + 54) + 16 + (17 + 6 + 54) + 16 + 54
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                sectionRowCounts: [1, 1],
                includesPrimaryAction: true,
                maximumHeight: 1_000
            ),
            268
        )
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                sectionRowCounts: [],
                includesPrimaryAction: false
            ),
            0
        )
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                sectionRowCounts: [0, 0],
                includesPrimaryAction: true
            ),
            82
        )
    }

    func testALongSectionedListStopsGrowingAndScrollsInstead() {
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                sectionRowCounts: [8, 5, 5, 6, 5],
                includesPrimaryAction: true
            ),
            BrowserCommandPaletteLayout.maximumResultAreaHeight
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

    func testRapidQueriesOnlyPublishTheLatestResultSet() async throws {
        let first = BrowserTab(
            title: "First Needle",
            url: try XCTUnwrap(URL(string: "https://example.com/first")),
            placement: .current
        )
        let second = BrowserTab(
            title: "Second Needle",
            url: try XCTUnwrap(URL(string: "https://example.com/second")),
            placement: .current
        )
        let history = try (0..<1_500).map { index in
            BrowserHistoryEntry(
                url: try XCTUnwrap(
                    URL(string: "https://history.example.com/\(index)")
                ),
                title: "First Needle History \(index)",
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        }
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Performance",
            symbol: "speedometer",
            accent: .indigo,
            folders: [],
            tabs: [first, second],
            history: history,
            selectedTabID: nil
        )
        let model = BrowserCommandPaletteModel(
            space: space,
            selectedTabID: nil,
            initialQuery: "",
            commands: nil,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            openURL: { _, _ in true },
            dismiss: {}
        )

        model.query = "first needle"
        model.query = "second needle"

        for _ in 0..<200 {
            if model.results.first?.subtitle == "second needle" {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.results.first?.subtitle, "second needle")
        XCTAssertTrue(model.results.contains { $0.title == "Second Needle" })
        XCTAssertFalse(model.results.contains { $0.title == "First Needle" })
    }
}
