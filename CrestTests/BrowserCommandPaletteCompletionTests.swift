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

    func testCompositionKeepsUncommittedTextOutOfResultsAndNetworkSuggestions() async {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let model = makeModel(makeSpace(tab), tab)
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: true)
        await model.waitForPendingResults()
        XCTAssertEqual(model.query, "")
        XCTAssertNil(model.urlCompletion)
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        XCTAssertEqual(model.urlCompletion?.suffix, "mple.com/path")
        model.moveSelection(by: 1)
        XCTAssertNil(model.urlCompletion)
    }

    func testAcceptedAddressUsesExistingNavigationActionOnEnter() async {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        var navigated: URL?
        let model = BrowserCommandPaletteModel(
            space: makeSpace(tab), selectedTabID: tab.id, initialQuery: "", commands: nil,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in
                XCTFail("Should use URL intent")
                return false
            },
            openURL: { _, url in
                navigated = url
                return true
            }, dismiss: {})
        model.applyCompletion = { [weak model] insertion, range in
            guard let model else { return }
            let text = (model.query as NSString).replacingCharacters(in: range, with: insertion)
            model.updateCompletionEditing(
                text: text, selection: NSRange(location: text.utf16.count, length: 0), isComposing: false)
        }
        model.updateCompletionEditing(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        XCTAssertTrue(model.acceptURLCompletion())
        XCTAssertNil(navigated)
        model.activateSelectedResult()
        XCTAssertEqual(navigated?.absoluteString, "https://example.com/path")
    }

    func testLiveLockSelectionSpaceAndProfileChangesHideAndRejectCompletion() {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .current)
        let original = makeSpace(tab)
        let other = makeSpace(
            BrowserTab(title: "Private", url: URL(string: "https://secret.example/path"), placement: .current))
        let browser = BrowserStore(
            session: BrowserSession(spaces: [original, other], selectedSpaceID: original.id),
            persistence: InMemoryBrowserSessionPersistence(), browsingMode: .privateBrowsing)
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
        browser.session.selectedSpaceID = other.id
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        var locked = original
        locked.accessPolicy = .deviceOwnerAuthentication
        browser.session = BrowserSession(spaces: [locked], selectedSpaceID: locked.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
        var selectionChanged = original
        selectionChanged.selectedTabID = nil
        browser.session = BrowserSession(spaces: [selectionChanged], selectedSpaceID: original.id)
        XCTAssertNil(model.urlCompletion)
        let replacement = BrowserSpace(
            id: original.id, profile: BrowsingProfile(), name: original.name, symbol: original.symbol,
            accent: original.accent, folders: [], tabs: original.tabs, selectedTabID: tab.id)
        browser.session = BrowserSession(spaces: [replacement], selectedSpaceID: original.id)
        XCTAssertNil(model.urlCompletion)
        XCTAssertFalse(model.acceptURLCompletion())
    }

    func testEmptySelectionCompletionCreatesDestinationOnlyAfterEnter() {
        let tab = BrowserTab(title: "Example", url: URL(string: "https://example.com/path"), placement: .saved)
        var space = makeSpace(tab)
        space.selectedTabID = nil
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence(), browsingMode: .privateBrowsing)
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
            tabs: [tab], selectedTabID: tab.id)
    }

    private func makeModel(_ space: BrowserSpace, _ tab: BrowserTab) -> BrowserCommandPaletteModel {
        BrowserCommandPaletteModel(
            space: space, selectedTabID: tab.id, initialQuery: "", commands: nil,
            fetchSuggestions: { _, _ in
                XCTFail("Local completion must not send a request")
                return []
            },
            isSourceAvailable: { _ in true }, selectTab: { _, _ in false }, openURL: { _, _ in false }, dismiss: {})
    }
}
