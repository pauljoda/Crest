import XCTest
@testable import Crest

final class BrowserSetupSiteSuggestionTests: XCTestCase {
    func testPopularSuggestionsAreSmallSecureAndUnique() {
        let suggestions = BrowserSetupSiteSuggestion.popular

        XCTAssertGreaterThanOrEqual(suggestions.count, 5)
        XCTAssertLessThanOrEqual(suggestions.count, 8)
        XCTAssertEqual(Set(suggestions.map(\.url)).count, suggestions.count)
        XCTAssertTrue(suggestions.allSatisfy { $0.url.scheme == "https" })
    }

    func testSocialSuggestionsDefaultToPinned() throws {
        let suggestionsByTitle = Dictionary(
            uniqueKeysWithValues: BrowserSetupSiteSuggestion.popular.map {
                ($0.title, $0)
            }
        )

        for title in ["Facebook", "Instagram", "Reddit", "X"] {
            XCTAssertEqual(
                try XCTUnwrap(suggestionsByTitle[title]).defaultPlacement,
                .pinned
            )
        }
    }

    func testSuggestionCanRetainItsFriendlyTitleWhenAdded() throws {
        let session = BrowserSession.freshInstallSeed
        let spaceID = session.selectedSpaceID
        let suggestion = try XCTUnwrap(
            BrowserSetupSiteSuggestion.popular.first { $0.title == "YouTube" }
        )
        var plan = BrowserManualSetupPlan(existing: session)

        _ = try plan.addTab(
            title: suggestion.title,
            url: suggestion.url,
            placement: suggestion.defaultPlacement,
            to: spaceID
        )

        let preview = try plan.preview(mergingInto: session)
        let tab = try XCTUnwrap(
            preview.space(id: spaceID)?.tabs.first { $0.url == suggestion.url }
        )
        XCTAssertEqual(tab.title, "YouTube")
        XCTAssertEqual(tab.placement, suggestion.defaultPlacement)
    }
}
