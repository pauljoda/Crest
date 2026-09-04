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

    func testDisabledTabHidesPanelAndReturningRestoresOpenIntent() throws {
        let store = makeStore()
        let disabled = TabID()
        try store.setOptions(.init(isEnabled: false), scope: .tab(disabled), from: client)
        try store.open(for: client, in: window, tab: tab)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: disabled, isAvailable: true)
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: disabled)?.documentURL)
        XCTAssertFalse(store.isOpen(for: client, in: window))
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertTrue(store.isOpen(for: client, in: window))
        XCTAssertEqual(
            store.panel(in: window, spaceID: space, activeTab: tab)?.documentURL,
            baseURL.appending(path: "panel.html"))
    }

    func testSamePathOnTabStillHasSeparateDocumentIdentity() throws {
        let store = makeStore()
        try store.setOptions(.init(path: "panel.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        let panel = store.panel(in: window, spaceID: space, activeTab: tab)
        XCTAssertEqual(panel?.tabID, tab)
        XCTAssertTrue(panel?.isTabSpecific == true)
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: TabID())?.tabID)
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

    func testBoundPanelAnswersForTheTabItWasOpenedForAndForNoOtherPlace() throws {
        let store = makeStore()
        let otherTab = TabID()
        // The bound tab is not the selected one: a row's mark has to promise
        // what returning to that tab would show.
        store.reconcilePresentation(in: window, spaceID: space, activeTab: otherTab, isAvailable: true)
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        let bound = store.boundPanel(for: tab, in: window, spaceID: space)
        XCTAssertEqual(bound?.clientID, client)
        XCTAssertEqual(bound?.path, "tab.html")
        XCTAssertEqual(bound?.tabID, tab)
        XCTAssertNil(store.boundPanel(for: otherTab, in: window, spaceID: space))
        XCTAssertNil(store.boundPanel(for: tab, in: BrowserWindowID(), spaceID: space))
        XCTAssertNil(store.boundPanel(for: tab, in: window, spaceID: SpaceID()))
    }

    func testGlobalPanelBindsNoTabEvenWhileItIsOnScreen() throws {
        let store = makeStore()
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.open(for: client, in: window, tab: nil)
        XCTAssertTrue(store.isOpen(for: client, in: window))
        XCTAssertNil(store.boundPanel(for: tab, in: window, spaceID: space))
    }

    func testClosingATabsPanelClearsItsBindingAndDisablingItHidesTheMark() throws {
        let store = makeStore()
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        XCTAssertNotNil(store.boundPanel(for: tab, in: window, spaceID: space))
        try store.setOptions(.init(isEnabled: false), scope: .tab(tab), from: client)
        XCTAssertNil(store.boundPanel(for: tab, in: window, spaceID: space))
        try store.setOptions(.init(isEnabled: true), scope: .tab(tab), from: client)
        XCTAssertNotNil(store.boundPanel(for: tab, in: window, spaceID: space))
        try store.closeChromePanel(for: client, in: window, tab: tab)
        XCTAssertNil(store.boundPanel(for: tab, in: window, spaceID: space))
    }

    func testUnregisteringAnExtensionDropsEveryTabItHadBound() throws {
        let store = makeStore()
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        store.unregister(client: client)
        XCTAssertNil(store.boundPanel(for: tab, in: window, spaceID: space))
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

    func testRepairDropsAContextualPanelWhoseTabClosedWithoutOverlappingAccess() throws {
        // Claude's login opened a tab, the coordinator reconciled the session,
        // and repair trapped on overlapping access to `contextualPresentations`
        // while a tab-specific panel was showing. Debug builds abort on that.
        let store = makeStore()
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.tabID, tab)
        let survivor = BrowserTab(title: "Example", url: URL(string: "https://example.com/")!, placement: .current)
        let browserSpace = BrowserSpace(
            id: space, profile: BrowsingProfile(), name: "Work", symbol: "briefcase",
            accent: .indigo, folders: [], tabs: [survivor], selectedTabID: survivor.id
        )
        store.repair(using: BrowserSession(spaces: [browserSpace], selectedSpaceID: space))
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: tab))
        XCTAssertFalse(store.isOpen(for: client, in: window))
    }

    func testOpeningInactiveTabPanelDoesNotReplaceVisibleGlobalPanel() throws {
        let store = makeStore()
        let inactiveTab = TabID()
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.open(for: client, in: window, tab: nil)
        try store.setOptions(.init(path: "inactive.html"), scope: .tab(inactiveTab), from: client)
        try store.open(for: client, in: window, tab: inactiveTab)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.path, "panel.html")
        try store.closeChromePanel(for: client, in: window, tab: nil)
        XCTAssertFalse(store.isOpen(for: client, in: window))
        store.reconcilePresentation(in: window, spaceID: space, activeTab: inactiveTab, isAvailable: true)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: inactiveTab)?.path, "inactive.html")
        XCTAssertTrue(store.isOpen(for: client, in: window))
    }

    func testOpeningAGlobalPanelReplacesTheActiveTabsContextualPanel() throws {
        let store = makeStore()
        store.register(
            client: other, spaceID: space, defaults: .init(flavor: .sidePanel),
            displayName: "Other", baseURL: URL(string: "webkit-extension://other/")!)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: other)
        try store.open(for: other, in: window, tab: tab)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.clientID, other)
        // Chrome shows the panel opened last: another extension's global panel
        // takes over the tab that was showing a tab-specific one.
        try store.open(for: client, in: window, tab: nil)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.clientID, client)
        XCTAssertTrue(store.isOpen(for: client, in: window))
        XCTAssertFalse(store.isOpen(for: other, in: window))
    }

    func testClosingInactiveTabPanelDoesNotCloseVisiblePanel() throws {
        let store = makeStore()
        let inactiveTab = TabID()
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.open(for: client, in: window, tab: nil)
        try store.setOptions(.init(path: "inactive.html"), scope: .tab(inactiveTab), from: client)
        try store.open(for: client, in: window, tab: inactiveTab)
        try store.closeChromePanel(for: client, in: window, tab: inactiveTab)
        XCTAssertTrue(store.isOpen(for: client, in: window))
        store.reconcilePresentation(in: window, spaceID: space, activeTab: inactiveTab, isAvailable: true)
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: inactiveTab)?.documentURL)
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
}
