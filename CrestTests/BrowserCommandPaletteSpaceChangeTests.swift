import XCTest

@testable import Crest

/// What a window's command palette keeps when the window moves to another
/// Space: a new tab can open in any Space, so its text, and the search
/// provider or scope it was narrowed to, follow; an address being edited
/// belongs to the tab left behind, so that palette closes.
@MainActor
final class BrowserCommandPaletteSpaceChangeTests: XCTestCase {
    func testNewTabTextFollowsSpaceChangeUntilDismissed() {
        let chrome = BrowserChromeState()
        chrome.presentCommandPalette()
        chrome.recordCommandPaletteDraft(BrowserCommandPaletteDraft(query: "google.com", provider: nil, scope: nil))

        chrome.spaceChanged()

        XCTAssertEqual(chrome.commandPaletteMode, .newTab)
        XCTAssertEqual(chrome.commandPaletteDraft(for: .newTab)?.query, "google.com")

        chrome.dismissCommandPalette()
        chrome.presentCommandPalette()
        XCTAssertEqual(chrome.commandPaletteDraft(for: .newTab), .empty)
    }

    func testNarrowedNewTabStaysNarrowedInTheNextSpace() throws {
        let provider = BrowserCommandPalettePreviewFixture.google
        let chrome = BrowserChromeState()
        chrome.presentCommandPalette()
        chrome.recordCommandPaletteDraft(BrowserCommandPaletteDraft(query: "swift", provider: provider, scope: nil))

        chrome.spaceChanged()

        let carried = try XCTUnwrap(chrome.commandPaletteDraft(for: .newTab))
        let replacement = makePalette(carrying: carried)
        XCTAssertEqual(replacement.activeProvider, provider)
        XCTAssertNil(replacement.activeScope)
        XCTAssertEqual(replacement.draft, carried)

        chrome.recordCommandPaletteDraft(BrowserCommandPaletteDraft(query: "", provider: nil, scope: .history))
        let scoped = makePalette(carrying: try XCTUnwrap(chrome.commandPaletteDraft(for: .newTab)))
        XCTAssertEqual(scoped.activeScope, .history)
        XCTAssertNil(scoped.activeProvider)
    }

    func testEditedAddressClosesOnSpaceChangeAndNeverBecomesNewTabText() {
        let chrome = BrowserChromeState()
        chrome.openLocation("https://alpha.crest.test")
        chrome.recordCommandPaletteDraft(
            BrowserCommandPaletteDraft(query: "https://alpha.crest.test/edited", provider: nil, scope: nil))

        chrome.spaceChanged()

        XCTAssertNil(chrome.commandPaletteMode)
        XCTAssertNil(chrome.commandPaletteDraft(for: .editLocation("https://alpha.crest.test")))
        chrome.presentCommandPalette()
        XCTAssertEqual(chrome.commandPaletteDraft(for: .newTab), .empty)
    }

    /// The palette a Space change builds from `draft`, as the window's
    /// palette layer builds it.
    private func makePalette(carrying draft: BrowserCommandPaletteDraft) -> BrowserCommandPaletteModel {
        BrowserCommandPaletteModel(
            browser: BrowserCommandPalettePreviewFixture.browser, space: BrowserCommandPalettePreviewFixture.space,
            selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID, initialQuery: draft.query,
            typesAfterInitialQuery: true, initialProvider: draft.provider, initialScope: draft.scope, commands: nil,
            isSourceAvailable: { _ in true }, selectTab: { _, _ in true }, openURL: { _, _, _ in true }, dismiss: {})
    }
}
