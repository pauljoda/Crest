import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteModelActivationTests: XCTestCase {
    func testSuggestionNetworkConfigurationCarriesNoCookiesOrSharedCache() {
        let configuration = BrowserSearchSuggestionClient.sessionConfiguration

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertLessThanOrEqual(configuration.timeoutIntervalForRequest, 5)
    }

    /// A click lands on the row the person saw, even between a keystroke and
    /// the core's answer to it; Return keeps waiting for that answer.
    func testClickDuringPendingAnswerActsOnShownRow() async {
        let shown = TabState.Seed(title: "Shown", url: URL(string: "https://shown.example/"), placement: .current)
        let other = TabState.Seed(title: "Other", url: URL(string: "https://other.example/"), placement: .current)
        let space = SpaceState.Seed(
            name: "Current", symbol: "globe", accent: .indigo, folders: [], tabs: [shown, other])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: shown.id])
        var switched: [UUID] = []
        var dismissed = 0
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: shown.id, initialQuery: "",
            commands: nil, isSourceAvailable: { _ in true },
            selectTab: { _, target in
                switched.append(target.tabID)
                return true
            },
            openURL: { _, _, _ in false }, dismiss: { dismissed += 1 })
        guard let row = model.items.first(where: { $0.row.tabID == other.id })?.row else {
            return XCTFail("The resting rows do not offer the other tab")
        }

        model.query = "unanswered"
        model.activate(row)

        XCTAssertEqual(switched, [other.id])
        XCTAssertEqual(dismissed, 1)
        await model.waitForPendingResults()
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
