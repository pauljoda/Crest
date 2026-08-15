import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserOmniboxSuggestionTests: XCTestCase {
    // MARK: - Fixtures

    private func keyword(_ value: String) throws -> BrowserOmniboxKeyword {
        try XCTUnwrap(BrowserOmniboxKeyword(value))
    }

    private func descriptor(
        _ value: String = "yt",
        title: String = "YouTube",
        defaultDescription: String = "Search YouTube for %s"
    ) throws -> BrowserOmniboxDescriptor {
        BrowserOmniboxDescriptor(
            keyword: try keyword(value),
            title: title,
            defaultSuggestionDescription: defaultDescription
        )
    }

    private func space(tabs: [BrowserTab] = []) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Omnibox",
            symbol: "magnifyingglass",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            history: [],
            selectedTabID: nil
        )
    }

    /// Polls until the palette has published results for `query`.
    private func waitForResults(
        of model: BrowserCommandPaletteModel,
        matching predicate: @MainActor (BrowserCommandPaletteModel) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<200 {
            if predicate(model) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for palette results.", file: file, line: line)
    }

    private func makeModel(
        registry: BrowserOmniboxRegistry,
        disposition: BrowserOmniboxDisposition = .currentTab,
        space: BrowserSpace? = nil,
        selectedTabID: TabID? = nil,
        dismiss: @escaping () -> Void = {}
    ) -> BrowserCommandPaletteModel {
        BrowserCommandPaletteModel(
            space: space ?? self.space(),
            selectedTabID: selectedTabID,
            initialQuery: "",
            otherSpaces: [],
            commands: nil,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            selectTabInSpace: nil,
            openURL: { _, _ in true },
            dismiss: dismiss,
            omnibox: registry,
            omniboxDisposition: disposition
        )
    }

    // MARK: - Keyword parsing

    func testKeywordModeNeedsASeparatingSpace() throws {
        XCTAssertNil(BrowserOmniboxInput.parse("yt"))
        XCTAssertNil(BrowserOmniboxInput.parse(""))

        let parsed = try XCTUnwrap(BrowserOmniboxInput.parse("yt "))
        XCTAssertEqual(parsed.keyword.rawValue, "yt")
        XCTAssertEqual(parsed.query, "")
    }

    func testKeywordParsingNormalizesCaseAndPreservesTheQuery() throws {
        let parsed = try XCTUnwrap(
            BrowserOmniboxInput.parse("  YT   swift  concurrency ")
        )

        XCTAssertEqual(parsed.keyword.rawValue, "yt")
        XCTAssertEqual(parsed.query, "swift  concurrency ")
    }

    func testKeywordsRejectEmptyAndWhitespaceValues() {
        XCTAssertNil(BrowserOmniboxKeyword(""))
        XCTAssertNil(BrowserOmniboxKeyword("   "))
        XCTAssertNil(BrowserOmniboxKeyword("two words"))
        XCTAssertEqual(BrowserOmniboxKeyword(" GH ")?.rawValue, "gh")
    }

    // MARK: - Registry

    func testRegistryResolvesOnlyRegisteredKeywords() throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor()
        )
        registry.register(provider)

        XCTAssertNotNil(registry.resolve("yt cats"))
        XCTAssertNil(registry.resolve("gh cats"))
        XCTAssertNil(registry.resolve("cats"))
        XCTAssertEqual(registry.registeredKeywords.map(\.rawValue), ["yt"])
    }

    func testRegisteringATakenKeywordReportsTheDisplacedProvider() throws {
        let registry = BrowserOmniboxRegistry()
        let first = InMemoryBrowserOmniboxProvider(descriptor: try descriptor())
        let second = InMemoryBrowserOmniboxProvider(descriptor: try descriptor())

        XCTAssertNil(registry.register(first))
        let displaced = registry.register(second)

        XCTAssertTrue(displaced === first)
        XCTAssertTrue(registry.provider(for: try keyword("yt")) === second)
    }

    func testUnregisteringRemovesTheKeyword() throws {
        let registry = BrowserOmniboxRegistry()
        registry.register(
            InMemoryBrowserOmniboxProvider(descriptor: try descriptor())
        )

        XCTAssertNotNil(registry.unregister(keyword: try keyword("yt")))
        XCTAssertNil(registry.resolve("yt cats"))
    }

    // MARK: - Rendering model

    func testKeywordRowsLeadWithTheDefaultSuggestion() throws {
        let context = BrowserCommandPaletteOmniboxContext(
            keyword: try keyword("yt"),
            query: "swift",
            title: "YouTube",
            defaultSuggestionDescription: "Search YouTube for %s",
            suggestions: [
                BrowserOmniboxSuggestion(
                    content: "swift concurrency",
                    description: "Swift Concurrency"
                ),
                BrowserOmniboxSuggestion(
                    content: "swift ui",
                    description: "SwiftUI",
                    isDeletable: true
                ),
            ]
        )

        let results = BrowserCommandPaletteResults.omniboxResults(for: context)

        XCTAssertEqual(
            results.map(\.title),
            ["Search YouTube for swift", "Swift Concurrency", "SwiftUI"]
        )
        XCTAssertEqual(
            results.map(\.section),
            [.omnibox, .omnibox, .omnibox]
        )
        XCTAssertEqual(Set(results.map(\.id)).count, results.count)
        XCTAssertEqual(
            results.map { $0.omniboxAcceptance?.isDeletable },
            [false, false, true]
        )
        XCTAssertEqual(
            results.compactMap { $0.omniboxAcceptance?.content },
            ["swift", "swift concurrency", "swift ui"]
        )
    }

    func testADefaultSuggestionWithoutAPlaceholderFallsBackToTheTitle() throws {
        let context = BrowserCommandPaletteOmniboxContext(
            keyword: try keyword("yt"),
            query: "swift",
            title: "YouTube",
            defaultSuggestionDescription: "",
            suggestions: []
        )

        let results = BrowserCommandPaletteResults.omniboxResults(for: context)

        XCTAssertEqual(results.map(\.title), ["YouTube"])
    }

    func testKeywordRowsAreCapped() throws {
        let context = BrowserCommandPaletteOmniboxContext(
            keyword: try keyword("yt"),
            query: "swift",
            title: "YouTube",
            defaultSuggestionDescription: "Search %s",
            suggestions: (0..<40).map { index in
                BrowserOmniboxSuggestion(
                    content: "content-\(index)",
                    description: "Suggestion \(index)"
                )
            }
        )

        let results = BrowserCommandPaletteResults.omniboxResults(for: context)

        XCTAssertEqual(
            results.count,
            BrowserCommandPaletteResultLimits.omniboxSuggestions + 1
        )
    }

    /// Keyword mode owns the whole list — a tab or history match for the raw
    /// text would be noise once the person handed the query to a provider.
    func testKeywordModeReplacesEveryOtherSource() throws {
        let tab = BrowserTab(
            title: "Swift",
            url: try XCTUnwrap(URL(string: "https://swift.org")),
            placement: .current
        )
        let context = BrowserCommandPaletteOmniboxContext(
            keyword: try keyword("yt"),
            query: "swift",
            title: "YouTube",
            defaultSuggestionDescription: "Search %s",
            suggestions: []
        )
        let input = BrowserCommandPaletteInput(
            query: "yt swift",
            space: space(tabs: [tab]),
            omnibox: context
        )

        let results = BrowserCommandPaletteResults.results(for: input)

        XCTAssertEqual(results.map(\.section), [.omnibox])
    }

    func testWithoutAKeywordTheOrdinarySourcesStillRun() throws {
        let tab = BrowserTab(
            title: "Swift",
            url: try XCTUnwrap(URL(string: "https://swift.org")),
            placement: .current
        )
        let input = BrowserCommandPaletteInput(
            query: "swift",
            space: space(tabs: [tab])
        )

        let results = BrowserCommandPaletteResults.results(for: input)

        XCTAssertFalse(results.contains { $0.section == .omnibox })
        XCTAssertTrue(results.contains { $0.section == .tabs })
    }

    // MARK: - Pipeline routing

    func testTypingAKeywordRoutesTheRemainderToTheProvider() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor(),
            suggestions: [
                BrowserOmniboxSuggestion(
                    content: "swift concurrency",
                    description: "Swift Concurrency"
                )
            ]
        )
        registry.register(provider)
        let model = makeModel(registry: registry)

        model.query = "yt swift"

        try await waitForResults(of: model) { model in
            model.results.contains { $0.section == .omnibox }
        }
        XCTAssertEqual(provider.requestedQueries, ["swift"])
        XCTAssertEqual(
            model.results.map(\.title),
            ["Search YouTube for swift", "Swift Concurrency"]
        )
    }

    func testAnUnregisteredKeywordLeavesThePipelineAlone() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor()
        )
        registry.register(provider)
        let tab = BrowserTab(
            title: "Swift",
            url: try XCTUnwrap(URL(string: "https://swift.org")),
            placement: .current
        )
        let model = makeModel(registry: registry, space: space(tabs: [tab]))

        model.query = "gh swift"

        try await waitForResults(of: model) { model in
            model.results.contains { $0.section == .tabs }
        }
        XCTAssertTrue(provider.requestedQueries.isEmpty)
        XCTAssertFalse(model.results.contains { $0.section == .omnibox })
    }

    func testEnteringAndLeavingKeywordModeRaisesTheSessionEvents() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor()
        )
        registry.register(provider)
        let model = makeModel(registry: registry)

        model.query = "yt swift"
        try await waitForResults(of: model) { model in
            model.results.contains { $0.section == .omnibox }
        }
        model.query = "yt swift concurrency"
        try await waitForResults(of: model) { _ in
            provider.requestedQueries.count == 2
        }

        XCTAssertEqual(provider.inputStartedCount, 1)
        XCTAssertEqual(provider.inputCancelledCount, 0)

        model.query = "plain search"
        try await waitForResults(of: model) { _ in
            provider.inputCancelledCount == 1
        }
        XCTAssertEqual(provider.inputStartedCount, 1)
    }

    // MARK: - Acceptance dispatch

    func testAcceptanceReachesTheProviderWithTheDisposition() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor(),
            suggestions: [
                BrowserOmniboxSuggestion(
                    content: "swift concurrency",
                    description: "Swift Concurrency"
                )
            ]
        )
        registry.register(provider)
        var dismissalCount = 0
        let model = makeModel(
            registry: registry,
            disposition: .newForegroundTab,
            dismiss: { dismissalCount += 1 }
        )

        model.query = "yt swift"
        try await waitForResults(of: model) { model in
            model.results.count == 2
        }
        model.selectResult(at: 1)
        model.activateSelectedResult()

        XCTAssertEqual(provider.acceptedContents, ["swift concurrency"])
        XCTAssertEqual(provider.acceptedDispositions, [.newForegroundTab])
        XCTAssertEqual(dismissalCount, 1)
    }

    func testAcceptingTheDefaultRowSubmitsTheRawQuery() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor()
        )
        registry.register(provider)
        let model = makeModel(registry: registry)

        model.query = "yt swift concurrency"
        try await waitForResults(of: model) { model in
            model.results.contains { $0.section == .omnibox }
        }
        model.activateSelectedResult()

        XCTAssertEqual(provider.acceptedContents, ["swift concurrency"])
        XCTAssertEqual(provider.acceptedDispositions, [.currentTab])
    }

    /// A row prepared under one keyword must never be delivered to whichever
    /// provider happens to be registered by the time it is clicked.
    func testARowWhoseProviderVanishedIsRefused() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor()
        )
        registry.register(provider)
        var dismissalCount = 0
        let model = makeModel(registry: registry, dismiss: { dismissalCount += 1 })

        model.query = "yt swift"
        try await waitForResults(of: model) { model in
            model.results.contains { $0.section == .omnibox }
        }
        registry.unregister(keyword: try keyword("yt"))
        model.activateSelectedResult()

        XCTAssertTrue(provider.acceptedContents.isEmpty)
        XCTAssertEqual(dismissalCount, 0)
    }

    func testAStaleRowIsRefusedWhileResultsAreRebuilding() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor()
        )
        registry.register(provider)
        let model = makeModel(registry: registry)

        model.query = "yt swift"
        try await waitForResults(of: model) { model in
            model.results.contains { $0.section == .omnibox }
        }
        let staleResult = try XCTUnwrap(model.results.first)
        model.query = "yt swift ui"
        model.activate(staleResult)

        XCTAssertTrue(provider.acceptedContents.isEmpty)
    }

    // MARK: - Deletion

    func testOnlyDeletableRowsCanBeRemoved() async throws {
        let registry = BrowserOmniboxRegistry()
        let provider = InMemoryBrowserOmniboxProvider(
            descriptor: try descriptor(),
            suggestions: [
                BrowserOmniboxSuggestion(
                    content: "keep",
                    description: "Keep me"
                ),
                BrowserOmniboxSuggestion(
                    content: "remove",
                    description: "Remove me",
                    isDeletable: true
                ),
            ]
        )
        registry.register(provider)
        let model = makeModel(registry: registry)

        model.query = "yt swift"
        try await waitForResults(of: model) { model in
            model.results.count == 3
        }

        let keepRow = try XCTUnwrap(model.results[1].omniboxAcceptance)
        let removeRow = try XCTUnwrap(model.results[2].omniboxAcceptance)
        XCTAssertFalse(model.deleteOmniboxSuggestion(keepRow))
        XCTAssertTrue(model.deleteOmniboxSuggestion(removeRow))

        XCTAssertEqual(provider.deletedContents, ["remove"])
        try await waitForResults(of: model) { model in
            model.results.count == 2
        }
    }
}
