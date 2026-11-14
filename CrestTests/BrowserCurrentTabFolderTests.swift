import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCurrentTabFolderTests: XCTestCase {

    func testSyncPreferencesIncludeEachFolderWithItsSectionAndPreserveDisabledLocalSections() async throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.shownSpace)
        let firstCurrent = try XCTUnwrap(space.currentTabs.first?.id)
        let saved = try XCTUnwrap(browser.addFolder(title: "Saved", in: space.id))
        let current = try XCTUnwrap(browser.createTabFolder([firstCurrent], in: space.id))
        // A device that does not sync its current tabs.
        let device = try BrowserStoredSessionHarness(
            seed: browser.sessionSeed,
            journalData: StoredSyncJournal.fresh(deviceID: UUID(), syncsCurrentTabs: false))
        let records = try await device.heldRecords()
        XCTAssertEqual(records.filter { $0.kind == .folder }.map(\.id), [saved])
        try device.deliverNow(MergeSyncRecords(records: records))
        let refreshed = try XCTUnwrap(device.store.spaceModel(space.id))
        XCTAssertEqual(refreshed.folders.model(current)?.location, .current)
        XCTAssertEqual(refreshed.tabs.model(firstCurrent)?.folderID, current)
    }

    func testSendReturnsTheFolderANewFolderBatchCreated() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.shownSpace)
        let tab = try XCTUnwrap(space.currentTabs.first?.id)
        let before = Set(space.folders.models.map(\.id))
        let request = try XCTUnwrap(BrowserSidebarSelection.capture([.tab(tab)], in: browser))
        let created = try XCTUnwrap(browser.send(browser.filingInNewFolder(request, in: .current), for: request))
        XCTAssertFalse(before.contains(created))
        XCTAssertTrue(space.folders.contains(created))
        XCTAssertEqual(space.tabs.model(tab)?.folderID, created)
    }

    func testSendReturnsNilForABatchThatCreatesNoFolder() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.shownSpace)
        let tab = try XCTUnwrap(space.currentTabs.first?.id)
        let request = try XCTUnwrap(BrowserSidebarSelection.capture([.tab(tab)], in: browser))
        XCTAssertNil(try browser.send(browser.keepingLoaded(request, true), for: request))
    }

    /// Moving an existing folder between sections rewrites that folder, so the
    /// core reports it in `updated` without having made anything.
    func testSendReturnsNilWhenAnExistingFolderOnlyChanges() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.shownSpace)
        // `addFolder` makes a saved folder; filing it into the open section moves it.
        let existing = try XCTUnwrap(browser.addFolder(title: "Existing", in: space.id))
        let request = try XCTUnwrap(BrowserSidebarSelection.capture([.folder(existing)], in: browser))
        XCTAssertNil(try browser.send(browser.filing(request, .current), for: request))
        XCTAssertEqual(space.folders.model(existing)?.location, .current)
    }

    /// The Space a selection names can stop being readable between capture and
    /// send, and a folder the edit only moved must never be mistaken for a new
    /// one: renaming would open on a folder the person already named.
    func testSendReturnsNilWhenTheSpaceCannotBeReadBeforeTheEdit() throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.shownSpace)
        let tab = try XCTUnwrap(space.currentTabs.first?.id)
        let existing = try XCTUnwrap(browser.addFolder(title: "Existing", in: space.id))
        let captured = try XCTUnwrap(BrowserSidebarSelection.capture([.folder(existing), .tab(tab)], in: browser))
        // A profile the Space no longer has, so `spaceModel(matching:)` answers nil.
        let unreadable = BrowserCapturedSelection(
            assignment: BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: UUID()),
            selected: captured.selected)
        XCTAssertNil(try browser.send(browser.filingInNewFolder(unreadable, in: .current), for: unreadable))
    }

    /// One saved tab followed by four open tabs, showing the last one.
    private func makeBrowser(_ configure: (inout SpaceState.Seed) -> Void = { _ in }) -> BrowserStore {
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = (0..<5).map { i in
            TabState.Seed(
                id: UUID(), title: "Tab \(i)", url: URL(string: "https://example.com/\(i)"),
                symbol: "globe", placement: i == 0 ? .saved : .current)
        }
        configure(&space)
        return makeStore(space, showing: space.tabs[4].id)
    }

    /// A window showing `tabID` in the only Space.
    private func makeStore(_ space: SpaceState.Seed, showing tabID: UUID) -> BrowserStore {
        BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: tabID])
    }
}
