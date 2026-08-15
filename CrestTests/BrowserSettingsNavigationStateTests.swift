import XCTest
@testable import Crest

final class BrowserSettingsNavigationStateTests: XCTestCase {
    func testDefaultsToGeneralWithEveryPlatformDestinationVisible() {
        let state = BrowserSettingsNavigationState()

        XCTAssertEqual(state.selection, .general)
        XCTAssertEqual(
            state.visibleDestinations(locale: Locale(identifier: "en")),
            BrowserSettingsDestination.platformCases
        )
    }

    func testSearchTrimsWhitespaceAndUsesLocalizedDestinationMetadata() {
        var state = BrowserSettingsNavigationState()
        state.searchText = "  QUICK WINDOW\n"

        XCTAssertEqual(
            state.visibleDestinations(locale: Locale(identifier: "en")),
            [.links]
        )
    }

    func testPasswordDestinationStaysVisibleWhileItsCredentialSearchIsActive() {
        var state = BrowserSettingsNavigationState(selection: .passwords)
        state.searchText = "cookies"

        XCTAssertEqual(
            state.visibleDestinations(locale: Locale(identifier: "en")),
            [.passwords, .privacy]
        )
    }

    func testHiddenDestinationIsNotInjectedForOtherSelections() {
        var state = BrowserSettingsNavigationState(selection: .general)
        state.searchText = "cookies"

        XCTAssertEqual(
            state.visibleDestinations(locale: Locale(identifier: "en")),
            [.privacy]
        )
    }

    func testExternalRouteSelectsItsRequestedDestination() {
        var state = BrowserSettingsNavigationState(selection: .general)

        state.applyExternalRoute(.shortcuts, revision: 1)

        XCTAssertEqual(state.selection, .shortcuts)
    }

    func testInitialPresentationWithoutARequestPreservesSelection() {
        var state = BrowserSettingsNavigationState(selection: .privacy)

        state.applyExternalRoute(.spaces, revision: 0)

        XCTAssertEqual(state.selection, .privacy)
    }
}
