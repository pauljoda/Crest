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

    func testFirefoxWindowOverridesRemainLocalAndAreReleasedWithTheirHost() throws {
        let store = BrowserExtensionSidebarStore(behaviorPersistence: InMemoryBrowserExtensionSidebarBehaviorStore())
        let second = BrowserWindowID()
        store.register(
            client: client, spaceID: space, defaults: .init(flavor: .sidebarAction, path: "manifest.html"),
            displayName: "Firefox", baseURL: baseURL)
        try store.setOptions(.init(path: "first.html", title: "First"), scope: .hostWindow(window), from: client)
        try store.setOptions(.init(path: "second.html", title: "Second"), scope: .hostWindow(second), from: client)
        try store.open(for: client, in: window, tab: tab)
        try store.open(for: client, in: second, tab: tab)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.path, "first.html")
        XCTAssertEqual(store.panel(in: second, spaceID: space, activeTab: tab)?.path, "second.html")
        try store.clearTitle(scope: .hostWindow(window), from: client)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.title, "Firefox")
        XCTAssertEqual(store.panel(in: second, spaceID: space, activeTab: tab)?.title, "Second")
        store.release(window: window)
        try store.open(for: client, in: window, tab: tab)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.path, "manifest.html")
        XCTAssertEqual(store.panel(in: second, spaceID: space, activeTab: tab)?.path, "second.html")
    }

    func testFirefoxSidebarFollowsActiveTabOverridesAndResetsToInheritedResources() throws {
        let store = BrowserExtensionSidebarStore(behaviorPersistence: InMemoryBrowserExtensionSidebarBehaviorStore())
        store.register(
            client: client, spaceID: space,
            defaults: .init(flavor: .sidebarAction, path: "manifest.html"),
            displayName: "Firefox", baseURL: baseURL)
        let second = TabID()
        try store.setOptions(.init(path: "global.html"), scope: .default, from: client)
        try store.setOptions(.init(path: "window.html"), scope: .window, from: client)
        try store.setOptions(.init(path: "tab.html"), scope: .tab(tab), from: client)
        try store.open(for: client, in: window, tab: tab)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.path, "tab.html")
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: tab)?.tabID)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: second, isAvailable: true)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: second)?.path, "window.html")
        try store.setOptions(.init(path: "inactive.html"), scope: .tab(tab), from: client)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: second)?.path, "window.html")
        XCTAssertEqual(store.retainedPanels(in: window, spaceID: space).map(\.path), ["window.html"])
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.path, "inactive.html")
        store.reconcilePresentation(in: window, spaceID: space, activeTab: nil, isAvailable: false)
        XCTAssertEqual(
            store.retainedPanels(in: window, spaceID: space).map(\.path), ["inactive.html"],
            "Switching Spaces must retain the resolved document, not replace it with its default")
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        for (scope, inheritedPath) in [
            (BrowserExtensionSidebarScope.tab(tab), "window.html"), (.window, "global.html"),
            (.default, "manifest.html"),
        ] {
            try store.setOptions(.init(path: ""), scope: scope, from: client)
            XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.path, inheritedPath)
            XCTAssertEqual(store.retainedPanels(in: window, spaceID: space).map(\.path), [inheritedPath])
            XCTAssertTrue(store.isOpen(for: client, in: window))
        }
        try store.close(for: client, in: window, tab: nil)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: second, isAvailable: true)
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: second))
    }

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

    func testTabPanelOverridesGlobalOnlyForItsOwnerAndScopedCloseRestoresGlobal() throws {
        let store = makeStore()
        store.register(
            client: other, spaceID: space, defaults: .init(flavor: .sidePanel),
            displayName: "Other", baseURL: URL(string: "webkit-extension://other/")!)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
        try store.open(for: client, in: window, tab: nil)
        let inactive = TabID()
        try store.setChromeOptions(.init(path: "side.html?anchor=one"), tab: inactive, from: other)
        try store.open(for: other, in: window, tab: inactive)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: tab)?.clientID, client)
        store.reconcilePresentation(in: window, spaceID: space, activeTab: inactive, isAvailable: true)
        let opened = store.panel(in: window, spaceID: space, activeTab: inactive)
        XCTAssertEqual(opened?.clientID, other)
        XCTAssertEqual(opened?.tabID, inactive)
        XCTAssertThrowsError(try store.closeChromePanel(for: other, in: window, tab: nil))
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: inactive), opened)
        try store.closeChromePanel(for: other, in: window, tab: inactive)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: inactive)?.clientID, client)
        XCTAssertEqual(store.retainedPanels(in: window, spaceID: space).count, 1)
        try store.open(for: other, in: window, tab: inactive)
        try store.open(for: client, in: window, tab: inactive)
        XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: inactive)?.clientID, client)
        XCTAssertEqual(store.retainedPanels(in: window, spaceID: space).count, 1)
    }

    func testUserCloseClearsGlobalAndActiveTabButRetainsOtherTabs() throws {
        for useToggle in [false, true] {
            let store = makeStore()
            let otherTab = TabID()
            try store.open(for: client, in: window, tab: nil)
            for target in [tab, otherTab] {
                try store.setChromeOptions(.init(path: "tab.html"), tab: target, from: client)
                try store.open(for: client, in: window, tab: target)
            }
            store.reconcilePresentation(in: window, spaceID: space, activeTab: tab, isAvailable: true)
            if useToggle {
                try store.toggle(for: client, in: window, tab: tab)
            } else {
                store.closePresentedPanel(in: window, spaceID: space, activeTab: tab)
            }
            XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: tab))
            XCTAssertEqual(store.retainedPanels(in: window, spaceID: space).map(\.tabID), [otherTab])
            store.reconcilePresentation(in: window, spaceID: space, activeTab: otherTab, isAvailable: true)
            XCTAssertEqual(store.panel(in: window, spaceID: space, activeTab: otherTab)?.tabID, otherTab)
        }
    }

    func testClosingTheSourceTabReleasesItsDocument() throws {
        let store = makeStore()
        try store.setChromeOptions(.init(path: "source.html"), tab: tab, from: client)
        try store.open(for: client, in: window, tab: tab)
        let browserSpace = BrowserSpace(
            id: space, profile: BrowsingProfile(), name: "Work", symbol: "briefcase",
            accent: .indigo, folders: [], tabs: [], selectedTabID: nil)
        store.repair(using: .init(spaces: [browserSpace], selectedSpaceID: space))
        store.reconcilePresentation(in: window, spaceID: space, activeTab: nil, isAvailable: true)
        XCTAssertNil(store.panel(in: window, spaceID: space, activeTab: nil))
        XCTAssertTrue(store.retainedPanels(in: window, spaceID: space).isEmpty)
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

    func testManifestFlavorAndUnresolvedLocalization() throws {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "side_panel": ["default_path": "chrome.html"],
            "sidebar_action": ["default_panel": "firefox.html", "default_title": "__MSG_title__"],
        ]
        let chrome = try XCTUnwrap(
            BrowserExtensionSidebarManifestPolicy.defaults(
                manifest: manifest, referenceEnvironment: .chromium
            ))
        let firefox = try XCTUnwrap(
            BrowserExtensionSidebarManifestPolicy.defaults(
                manifest: manifest, referenceEnvironment: .firefox
            ))
        XCTAssertEqual(chrome.path, "chrome.html")
        XCTAssertEqual(firefox.path, "firefox.html")
        XCTAssertNil(firefox.title)
        XCTAssertTrue(firefox.opensAtInstall)
        XCTAssertTrue(BrowserExtensionSidebarManifestPolicy.declaresSidebar(manifest: manifest))
        XCTAssertNil(
            BrowserExtensionSidebarManifestPolicy.defaults(
                manifest: ["manifest_version": 2, "side_panel": ["default_path": "panel.html"]],
                referenceEnvironment: .chromium
            ))
    }
}
