import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteCompletionTests: XCTestCase {
    func testProposalDoesNotEditOrNavigateAndAcceptanceRequiresLiveSource() async throws {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let space = makeSpace(tab)
        var available = true
        var navigated: URL?
        var inserted: String?
        let model = BrowserCommandPaletteModel(
            space: space, selectedTabID: tab.id, initialQuery: "", commands: nil,
            isSourceAvailable: { _ in available }, selectTab: { _, _ in false },
            openURL: { _, url in
                navigated = url
                return true
            }, dismiss: {})
        model.applyCompletion = { text, _ in inserted = text }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        await model.waitForPendingResults()
        XCTAssertEqual(model.urlCompletion?.suffix, "mple.com/path")
        XCTAssertEqual(model.query, "exa")
        XCTAssertNil(navigated)
        XCTAssertNil(inserted)
        available = false
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        XCTAssertNil(inserted)
        available = true
        XCTAssertTrue(model.acceptURLCompletion())
        XCTAssertEqual(inserted, "mple.com/path")
        XCTAssertNil(navigated)
    }

    func testLiveLockSelectionSpaceAndProfileChangesHideAndRejectCompletion() {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let original = makeSpace(tab)
        let other = makeSpace(
            BrowserTab(title: "Private", url: URL(string: "https://secret.example/path"), placement: .current))
        let browser = BrowserStore(
            session: BrowserSession(spaces: [original, other]),
            showing: original.id, tabs: [original.id: tab.id],
            browsingMode: .privateBrowsing)
        let access = BrowserSpaceAccessController()
        let model = BrowserCommandPaletteModel(
            space: original, selectedTabID: tab.id, initialQuery: "", commands: nil, isPrivateBrowsing: true,
            isSourceAvailable: {
                BrowserCommandPaletteActionPolicy.isSourceAvailable($0, in: browser, accessController: access)
            },
            selectTab: { _, _ in false }, openURL: { _, _ in false }, dismiss: {})
        model.applyCompletion = { _, _ in XCTFail("Stale proposal was accepted") }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        XCTAssertNotNil(model.urlCompletion)
        browser.selectPresentedSpace(other.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        var locked = original
        locked.accessPolicy = .deviceOwnerAuthentication
        browser.session = BrowserSession(spaces: [locked])
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        browser.session = BrowserSession(spaces: [original])
        browser.clearPresentedTabSelection(in: original.id)
        XCTAssertNil(model.urlCompletion)
        let replacement = BrowserSpace(
            id: original.id, profile: BrowsingProfile(), name: original.name, symbol: original.symbol,
            accent: original.accent, folders: [], tabs: original.tabs)
        browser.session = BrowserSession(spaces: [replacement])
        browser.activateSessionTab(tab.id, in: original.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
    }

    func testEmptySelectionCompletionCreatesDestinationOnlyAfterEnter() {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .saved)
        let space = makeSpace(tab)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space]),
            showing: space.id, browsingMode: .privateBrowsing)
        var explicitSelectionCount = 0
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space), browser: browser,
            accessController: BrowserSpaceAccessController(), didSelectTab: { explicitSelectionCount += 1 })
        let model = BrowserCommandPaletteModel(
            space: space, selectedTabID: nil, initialQuery: "", commands: nil, isSourceAvailable: { _ in false },
            selectTab: { _, _ in false }, openURL: { _, _ in false }, dismiss: {}, emptySelectionActions: actions)
        model.applyCompletion = { [weak model] insertion, range in
            guard let model else { return }
            let text = (model.query as NSString).replacingCharacters(in: range, with: insertion)
            model.updateCompletionEditing(
                text: text, selection: NSRange(location: text.utf16.count, length: 0), isComposing: false)
        }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        XCTAssertNotNil(model.urlCompletion)
        XCTAssertTrue(model.acceptURLCompletion())
        XCTAssertNil(browser.selectedTab)
        XCTAssertEqual(explicitSelectionCount, 0)
        model.activateSelectedResult()
        XCTAssertEqual(browser.selectedTab?.url?.absoluteString, "https://example.com/path")
        XCTAssertEqual(explicitSelectionCount, 1)
        XCTAssertEqual(browser.selectedSpace?.tabs.count, 2)
    }

    private func makeSpace(_ tab: BrowserTab) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Current", symbol: "globe", accent: .indigo, folders: [],
            tabs: [tab])
    }

}
