import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteCompletionTests: XCTestCase {
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

    func testCompletionStaysWhileTypingIntoItUntilTheCoreAnswers() async {
        let tab = TabState.Seed(
            title: "Example", url: URL(string: "https://example.com/Path/page"), placement: .current)
        let space = makeSpace(tab)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: tab.id, initialQuery: "",
            commands: nil, isSourceAvailable: { _ in true },
            selectTab: { _, _ in false }, openURL: { _, _, _ in false }, dismiss: {})
        func type(_ text: String) {
            model.updateCompletionEditing(
                text: text, selection: NSRange(location: text.utf16.count, length: 0), isComposing: false)
        }
        type("exa")
        await model.waitForPendingResults()
        XCTAssertEqual(model.urlCompletion?.suffix, "mple.com")

        // Before the core answers, a keystroke that types into the suffix keeps it.
        type("exaM")
        XCTAssertEqual(model.urlCompletion?.typed, "exaM")
        XCTAssertEqual(model.urlCompletion?.suffix, "ple.com")
        XCTAssertEqual(model.urlCompletion?.accepted, "example.com")

        // One that leaves it clears it at once.
        type("exaMx")
        XCTAssertNil(model.urlCompletion)
        await model.waitForPendingResults()
        XCTAssertNil(model.urlCompletion)

        // The path matches only in its own case, as the core matches it.
        type("example.com/P")
        await model.waitForPendingResults()
        XCTAssertEqual(model.urlCompletion?.suffix, "ath/")
        type("example.com/Pa")
        XCTAssertEqual(model.urlCompletion?.suffix, "th/")
        type("example.com/PaT")
        XCTAssertNil(model.urlCompletion)

        // The path matches code unit by code unit, so a decomposed é never
        // continues a precomposed one.
        let accented = AddressCompletion(typed: "example.com/", suffix: "\u{E9}/", accepted: "example.com/\u{E9}/")
        XCTAssertNil(accented.continued(to: "example.com/e\u{301}"))
        XCTAssertEqual(accented.continued(to: "example.com/\u{E9}")?.suffix, "/")
    }

    private func makeSpace(_ tab: TabState.Seed) -> SpaceState.Seed {
        SpaceState.Seed(
            name: "Current", symbol: "globe", accent: .indigo, folders: [],
            tabs: [tab])
    }

}
