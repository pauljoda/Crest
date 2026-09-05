import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionSidebarStoreTests: XCTestCase {
    private let space = SpaceID()
    private let window = BrowserWindowID()
    private let tab = TabID()
    private let client = BrowserExtensionServiceClientID("chatgpt")!
    private let other = BrowserExtensionServiceClientID("other")!
    private let baseURL = URL(string: "webkit-extension://chatgpt/")!

    func testOpenReplacesOnlyThisWindowsSpacePanelAndPublishesBothEvents() async throws {
        let store = makeStore()
        store.register(
            client: other, spaceID: space, defaults: .init(flavor: .sidePanel, path: "other.html"),
            displayName: "Other", baseURL: URL(string: "webkit-extension://other/")!)
        var events = store.events(for: client).makeAsyncIterator()
        try store.open(for: client, in: window, tab: tab)
        let opened = await events.next()
        XCTAssertEqual(opened?.kind, .opened)
        XCTAssertEqual(opened?.path, "panel.html")
        XCTAssertNil(opened?.tabID)
        try store.open(for: other, in: window, tab: tab)
        let closed = await events.next()
        XCTAssertEqual(closed?.kind, .closed)
        XCTAssertFalse(store.isOpen(for: client, in: window))
        XCTAssertTrue(store.isOpen(for: other, in: window))
        XCTAssertNil(store.panel(in: BrowserWindowID(), spaceID: space, activeTab: tab))
    }

    func testTabCloseRefusesGlobalPanelAndOrdinaryCloseClearsIntent() throws {
        let store = makeStore()
        try store.open(for: client, in: window, tab: tab)
        XCTAssertThrowsError(try store.close(for: client, in: window, tab: tab))
        try store.close(for: client, in: window, tab: nil)
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: tab))
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertFalse(store.isOpen(for: client, in: window))
    }

    func testBehaviorPersistsButOpenStateAndOptionsDoNot() throws {
        let persistence = InMemoryBrowserExtensionSidebarBehaviorStore()
        let store = makeStore(persistence: persistence)
        try store.setBehavior(.init(openPanelOnActionClick: true), from: client)
        try store.setOptions(.init(path: "temporary.html"), scope: .default, from: client)
        try store.open(for: client, in: window, tab: tab)
        let relaunched = makeStore(persistence: persistence)
        XCTAssertTrue(try relaunched.behavior(for: client).openPanelOnActionClick)
        XCTAssertEqual(try relaunched.resolvedOptions(for: tab, client: client).path, "panel.html")
        XCTAssertFalse(relaunched.isOpen(for: client, in: window))
    }

    func testLockedSpaceHidesDocumentAndUnregisterRemovesIntent() throws {
        let store = makeStore()
        try store.open(for: client, in: window, tab: tab)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: false)
        XCTAssertFalse(store.isOpen(for: client, in: window))
        store.unregister(client: client)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: tab))
        XCTAssertThrowsError(try store.behavior(for: client))
    }

    func testResourceValidationRejectsRemoteAndOtherExtensionDocuments() throws {
        let store = makeStore()
        for path in [
            "https://example.com/", "javascript:alert(1)", "//other/panel.html", "webkit-extension://other/panel.html",
        ] {
            XCTAssertThrowsError(try store.setOptions(.init(path: path), scope: .default, from: client))
        }
        try store.setOptions(.init(path: "folder/panel.html?query=1#anchor"), scope: .default, from: client)
        try store.open(for: client, in: window, tab: tab)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.documentURL?.query, "query=1")
    }

    private func makeStore(
        persistence: InMemoryBrowserExtensionSidebarBehaviorStore = .init()
    ) -> BrowserExtensionSidebarStore {
        let store = BrowserExtensionSidebarStore(behaviorPersistence: persistence)
        store.register(
            client: client, spaceID: space, defaults: .init(flavor: .sidePanel, path: "panel.html"),
            displayName: "ChatGPT", baseURL: baseURL)
        return store
    }

    func testUnchangedSessionRepairDoesNotInvalidateObservers() {
        let store = makeStore()
        let browserSpace = BrowserSpace(
            id: space, profile: BrowsingProfile(), name: "Work", symbol: "briefcase",
            accent: .indigo, folders: [], tabs: [], selectedTabID: nil
        )
        let session = BrowserSession(spaces: [browserSpace], selectedSpaceID: space)
        let revision = store.optionsRevision
        store.repair(using: session)
        XCTAssertEqual(store.optionsRevision, revision)
    }

    func testChromeOptionsSeedDefaultsOnceAndDoNotInheritATabPath() throws {
        let store = makeStore()
        try store.setChromeOptions(.init(isEnabled: false), tab: nil, from: client)
        XCTAssertEqual(try store.layer(.default, for: client), .init(path: "panel.html", isEnabled: false))
        try store.setChromeOptions(.init(path: "new.html"), tab: nil, from: client)
        XCTAssertFalse(try store.resolvedOptions(for: nil, client: client).isEnabled)
        try store.setChromeOptions(.init(isEnabled: true), tab: tab, from: client)
        XCTAssertNil(try store.layer(.tab(tab), for: client).path)
        XCTAssertFalse(try store.resolvedOptions(for: tab, client: client).presentsPanel)
    }

    func testFirefoxFreshInstallOpensOnceWhenItsHostBecomesAvailable() throws {
        let store = BrowserExtensionSidebarStore(behaviorPersistence: InMemoryBrowserExtensionSidebarBehaviorStore())
        store.register(
            client: client, spaceID: space,
            defaults: .init(flavor: .sidebarAction, path: "panel.html", opensAtInstall: true),
            displayName: "Firefox", baseURL: baseURL)
        var completed = 0
        store.requestOpenAtInstall(for: client) { completed += 1 }
        XCTAssertFalse(store.isOpen(for: client, in: window))
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertTrue(store.isOpen(for: client, in: window))
        XCTAssertEqual(completed, 1)
        try store.close(for: client, in: window, tab: nil)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertFalse(store.isOpen(for: client, in: window))
        XCTAssertEqual(completed, 1)
    }

    func testTabResourceReplacesTheSpacesPanelAndStaysAcrossAllTabs() throws {
        let store = makeStore()
        store.register(
            client: other, spaceID: space, defaults: .init(flavor: .sidePanel),
            displayName: "Claude", baseURL: URL(string: "webkit-extension://other/")!)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.open(for: client, in: window, tab: nil)
        let inactive = TabID()
        try store.setChromeOptions(.init(path: "side.html?anchor=one"), tab: inactive, from: other)
        try store.open(for: other, in: window, tab: inactive)
        let opened = store.panel(in: window, spaceID: space, activeTab: tab)
        XCTAssertEqual(opened?.clientID, other)
        XCTAssertEqual(opened?.path, "side.html?anchor=one")
        XCTAssertNil(opened?.tabID, "The document belongs to the Space even when a tab selected its resource.")
        for selected in [inactive, tab, TabID()] {
            store.reconcilePresentation(in: window, spaceID: space, activeTab: selected, isAvailable: true)
            XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: selected), opened)
            XCTAssertTrue(store.isOpen(for: other, in: window))
            XCTAssertFalse(store.isOpen(for: client, in: window))
        }
    }

    func testCloseClearsTheSingleSelectionAndNoTabResurrectsIt() throws {
        let store = makeStore()
        let otherTab = TabID()
        for target in [tab, otherTab] {
            try store.setChromeOptions(.init(path: "tab.html"), tab: target, from: client)
            try store.open(for: client, in: window, tab: target)
        }
        store.closePresentedPanel(in: window, spaceID: space)
        for selected in [tab, otherTab] {
            store.reconcilePresentation(in: window, spaceID: space, activeTab: selected, isAvailable: true)
            XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: selected))
        }
        XCTAssertTrue(store.retainedPanels(in: window, spaceID: space).isEmpty)
    }

    func testToggleClosesTheSelectedExtensionEvenAfterSwitchingTabs() throws {
        let store = makeStore()
        try store.setChromeOptions(.init(path: "tab.html"), tab: tab, from: client)
        try store.toggle(for: client, in: window, tab: tab)
        let otherTab = TabID()
        store.reconcilePresentation(in: window, spaceID: space, activeTab: otherTab, isAvailable: true)
        try store.toggle(for: client, in: window, tab: otherTab)
        XCTAssertFalse(store.isOpen(for: client, in: window))
        XCTAssertTrue(store.retainedPanels(in: window, spaceID: space).isEmpty)
    }

    func testDisabledAndUnrelatedTabOptionsDoNotDestroyTheOpenDocument() throws {
        let store = makeStore()
        try store.open(for: client, in: window, tab: nil)
        let opened = store.panel(in: window, spaceID: space, activeTab: tab)
        try store.setChromeOptions(.init(path: "unrelated.html"), tab: tab, from: client)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab), opened)
        try store.setChromeOptions(.init(isEnabled: false), tab: tab, from: client)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab), opened)
        XCTAssertThrowsError(try store.open(for: client, in: window, tab: tab))
        try store.setChromeOptions(.init(isEnabled: false), tab: nil, from: client)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab), opened)
        store.closePresentedPanel(in: window, spaceID: space)
        XCTAssertThrowsError(try store.open(for: client, in: window, tab: nil))
    }

    func testExplicitOptionsUpdateTheSelectedResourceWithoutChangingItsOwnership() throws {
        let store = makeStore()
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        try store.setOptions(.init(path: "updated.html", title: "Updated"), scope: .tab(tab), from: client)
        let panel = store.panel(in: window, spaceID: space, activeTab: TabID())
        XCTAssertEqual(panel?.path, "updated.html")
        XCTAssertEqual(panel?.title, "Updated")
        XCTAssertNil(panel?.tabID)
    }

    func testTabChangesDoNotPublishSpuriousCloseAndOpenEvents() async throws {
        let store = makeStore()
        var events = store.events(for: client).makeAsyncIterator()
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        let opened = await events.next()
        XCTAssertEqual(opened?.kind, .opened)
        let otherTab = TabID()
        try store.setChromeOptions(.init(path: "different.html"), tab: otherTab, from: client)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: otherTab, isAvailable: true)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: nil, isAvailable: true)
        XCTAssertTrue(store.isOpen(for: client, in: window), "An empty Space still holds its panel.")
        store.closePresentedPanel(in: window, spaceID: space)
        store.unregister(client: client)
        var remainder: [BrowserExtensionSidebarEvent] = []
        while let event = await events.next() { remainder.append(event) }
        XCTAssertEqual(remainder.map(\.kind), [.closed])
        XCTAssertEqual(remainder.first?.path, opened?.path)
    }

    func testClosingTheSourceTabKeepsTheSelectedDocument() throws {
        let store = makeStore()
        try store.setChromeOptions(.init(path: "source.html"), tab: tab, from: client)
        try store.open(for: client, in: window, tab: tab)
        let browserSpace = BrowserSpace(
            id: space, profile: BrowsingProfile(), name: "Work", symbol: "briefcase",
            accent: .indigo, folders: [], tabs: [], selectedTabID: nil)
        store.repair(using: .init(spaces: [browserSpace], selectedSpaceID: space))
        store.reconcilePresentation(in: window, spaceID: space, activeTab: nil, isAvailable: true)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: nil)?.path, "source.html")
        XCTAssertEqual(try store.layer(.tab(tab), for: client), .init())
    }

    func testSpaceSwitchRetainsOnlyItsSelectionAndWindowReleaseDropsIt() throws {
        let store = makeStore()
        let otherSpace = SpaceID()
        store.register(
            client: other, spaceID: otherSpace, defaults: .init(flavor: .sidePanel, path: "other.html"),
            displayName: "Other", baseURL: URL(string: "webkit-extension://other/")!)
        try store.open(for: client, in: window, tab: tab)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: nil, isAvailable: false)
        store.reconcilePresentation(in: window, spaceID: otherSpace, activeTab: nil, isAvailable: true)
        XCTAssertNil(store.panel(in: window, spaceID: otherSpace, activeTab: nil))
        XCTAssertFalse(store.isOpen(for: client, in: window))
        XCTAssertEqual(store.retainedPanels(in: window, spaceID: space).map(\.path), ["panel.html"])
        try store.open(for: other, in: window, tab: nil)
        store.reconcilePresentation(in: window, spaceID: otherSpace, activeTab: nil, isAvailable: false)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertTrue(store.isOpen(for: client, in: window))
        XCTAssertFalse(store.isOpen(for: other, in: window))
        store.release(window: window)
        XCTAssertTrue(store.retainedPanels(in: window, spaceID: space).isEmpty)
        XCTAssertTrue(store.retainedPanels(in: window, spaceID: otherSpace).isEmpty)
    }

    func testReplacedExtensionCannotCloseItsSuccessor() throws {
        let store = makeStore()
        store.register(
            client: other, spaceID: space, defaults: .init(flavor: .sidePanel, path: "other.html"),
            displayName: "Other", baseURL: URL(string: "webkit-extension://other/")!)
        try store.open(for: client, in: window, tab: nil)
        try store.open(for: other, in: window, tab: tab)
        try store.closeChromePanel(for: client, in: window, tab: nil)
        XCTAssertTrue(store.isOpen(for: other, in: window))
        XCTAssertEqual(store.retainedPanels(in: window, spaceID: space).map(\.path), ["other.html"])
    }
}
