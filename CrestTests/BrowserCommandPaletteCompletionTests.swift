import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteCompletionTests: XCTestCase {
    func testPointerSelectionDismissesOnlyTheCompletionFromThePreviousAnswer() async throws {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let space = makeSpace(tab)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil, suggestionDebounce: .zero, fetchSuggestions: { _ in [] },
            isSourceAvailable: { _ in true }, selectTab: { _, _ in false },
            openURL: { _, _, _ in false }, dismiss: {})
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        await model.waitForPendingResults()
        XCTAssertEqual(model.urlCompletion?.suffix, "mple.com")
        let row = try XCTUnwrap(model.items.first)

        model.updateCompletionEditing(text: "exam", selection: NSRange(location: 4, length: 0), isComposing: false)
        XCTAssertEqual(model.urlCompletion?.suffix, "ple.com")
        model.selectResult(row)
        XCTAssertNil(model.urlCompletion)
        XCTAssertEqual(model.selectedResultIndex, row.index)

        await model.waitForPendingResults()
        XCTAssertEqual(model.urlCompletion?.suffix, "ple.com")
    }

    func testLiveLockSelectionSpaceAndProfileChangesHideAndRejectCompletion() async {
        let tab = TabState.Seed(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let original = makeSpace(tab)
        let other = makeSpace(
            TabState.Seed(title: "Private", url: URL(string: "https://secret.example/path"), placement: .current))
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [original, other]),
            showing: original.id, tabs: [original.id: tab.id])
        let access = BrowserSpaceAccessController()
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(original.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil,
            isSourceAvailable: {
                browser.isPaletteSourceAvailable($0, accessController: access)
            },
            selectTab: { _, _ in false }, openURL: { _, _, _ in false }, dismiss: {})
        model.applyCompletion = { _, _ in XCTFail("Stale proposal was accepted") }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        await model.waitForPendingResults()
        XCTAssertNotNil(model.urlCompletion)
        browser.selectPresentedSpace(other.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        browser.removeSpaceForTesting(other.id)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: original.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        browser.unlockForTesting(original)
        browser.updateSpaceAccessPolicy(.open, in: original.id)
        browser.clearPresentedTabSelection(in: original.id)
        XCTAssertNil(model.urlCompletion)
        browser.replaceProfileForTesting(of: original.id)
        browser.activateSessionTab(tab.id, in: original.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
    }

    private func makeSpace(_ tab: TabState.Seed) -> SpaceState.Seed {
        SpaceState.Seed(
            name: "Current", symbol: "globe", accent: .indigo, folders: [],
            tabs: [tab])
    }

}
