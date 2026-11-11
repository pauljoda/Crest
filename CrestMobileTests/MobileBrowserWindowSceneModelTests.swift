import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserWindowSceneModelTests: XCTestCase {
    /// iPadOS restores a window scene with the value an earlier build saved,
    /// `{"rawValue": UUID}`. It restores the same window, a bare identity
    /// reads too, and this build saves the spelling an earlier build restores.
    func testAWindowRequestKeepsTheStoredIdentitySpellingAndReadsABareOne() throws {
        let id = UUID()
        let earlier = Data(#"{"rawValue":"\#(id.uuidString)"}"#.utf8)
        let bare = Data(#""\#(id.uuidString)""#.utf8)

        XCTAssertEqual(try JSONDecoder().decode(MobileWindowRequest.self, from: earlier).id, id)
        XCTAssertEqual(try JSONDecoder().decode(MobileWindowRequest.self, from: bare).id, id)
        let stored = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MobileWindowRequest(id: id)))
        XCTAssertEqual(stored as? [String: String], ["rawValue": id.uuidString])
    }

    /// A scene that closes takes its private workspace with it, once. Shown
    /// again, it browses privately in a new workspace, never in the closed one.
    func testAClosedSceneClosesItsPrivateWorkspaceAndOpensANewOneWhenShownAgain() throws {
        let rootBrowser = BrowserStore.hostingPages(.preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: rootBrowser, usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: UUID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .lastActiveTab,
            usesEphemeralWebsiteDataStores: true)
        let closing = model.privateBrowser
        let closed = closing.family.workspaceID

        model.closeWindowRuntime()
        model.closeWindowRuntime()

        XCTAssertFalse(closing.family.isOpen)
        XCTAssertNil(rootBrowser.core.state.workspaces[closed])
        model.activateWindow()
        XCTAssertFalse(model.privateBrowser === closing)
        XCTAssertTrue(model.privateBrowser.family.isOpen)
        XCTAssertNotEqual(model.privateBrowser.family.workspaceID, closed)
        let url = try XCTUnwrap(URL(string: "https://private.example"))
        let tab = try XCTUnwrap(model.privateBrowser.openNewTab(url: url))
        XCTAssertTrue(model.privateBrowser.openTabIDs.contains(tab))
    }

    /// The app's own store composes the scenes but is never on screen, so
    /// it keeps no tab from them: a scene opening on its Space's tab used
    /// last finds the only tab there, as the app arranges its stores, and a
    /// second scene still passes over the tab the first one shows.
    func testASceneShowsTheOnlyTabItsSpaceHoldsAndASecondSceneLeavesIt() throws {
        let tab = TabState.Seed(title: "Only", url: URL(string: "https://only.example"), placement: .current)
        let rootBrowser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [SpaceState.Seed(name: "Only", tabs: [tab])]))
        XCTAssertEqual(rootBrowser.shownTab?.id, tab.id)

        let scene = makeScene(over: rootBrowser)
        XCTAssertNil(scene.browser.shownTab)
        XCTAssertTrue(scene.browser.showLastUsedTab())
        XCTAssertEqual(scene.browser.shownTab?.id, tab.id)

        let second = makeScene(over: rootBrowser)
        XCTAssertFalse(second.browser.showLastUsedTab())
        XCTAssertNil(second.browser.shownTab)
    }

    /// Search greets a person back after a while away, still on the tab they
    /// left, once for each return. A quick trip, another tab, or a link that
    /// brought them back leaves the page alone.
    func testSearchGreetsAReturnAfterAWhileAwayUnlessALinkBroughtThePersonBack() {
        let greeting = MobileWindowGreeting()
        let tab = UUID()
        let left = Date(timeIntervalSinceReferenceDate: 0)
        let away = left.addingTimeInterval(MobileWindowGreeting.awayInterval)

        greeting.leave(showing: tab, at: left)
        XCTAssertFalse(greeting.comesBack(showing: tab, at: away.addingTimeInterval(-1)))
        greeting.leave(showing: tab, at: left)
        XCTAssertFalse(greeting.comesBack(showing: UUID(), at: away))
        greeting.leave(showing: tab, at: left)
        XCTAssertTrue(greeting.comesBack(showing: tab, at: away))
        XCTAssertFalse(greeting.comesBack(showing: tab, at: away))

        greeting.leave(showing: tab, at: left)
        greeting.yieldToExternalLink()
        XCTAssertFalse(greeting.comesBack(showing: tab, at: away))
    }

    /// A window greets its launch with search once, so the browser it shows
    /// anew, as after private browsing, picks up where the window was; and a
    /// link the window takes before its browser is ready keeps the greeting
    /// away from it.
    func testAWindowGreetsItsLaunchOnceAcrossItsBrowsersAndNeverOverALinkItTookFirst() async throws {
        let tab = TabState.Seed(title: "Last", url: URL(string: "https://last.example"), placement: .current)
        let rootBrowser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [SpaceState.Seed(name: "Personal", tabs: [tab])]),
            core: .hostingPages(contentRuleLists: EmptyContentRuleListProvider()))
        var greetings = 0
        let greet = {
            greetings += 1
            return true
        }

        let scene = makeScene(over: rootBrowser)
        await makeRoot(for: scene).prepareBrowser(presentSearch: greet)
        XCTAssertEqual(greetings, 1)
        await makeRoot(for: scene).prepareBrowser(presentSearch: greet)
        XCTAssertEqual(greetings, 1)

        let linked = makeScene(over: rootBrowser)
        XCTAssertTrue(linked.receiveExternalURL(try XCTUnwrap(URL(string: "https://link.example"))))
        await makeRoot(for: linked).prepareBrowser(presentSearch: greet)
        XCTAssertEqual(greetings, 1)
    }

    /// A scene as the app opens one, starting on search.
    private func makeScene(over rootBrowser: BrowserStore) -> MobileBrowserWindowSceneModel {
        MobileBrowserWindowSceneModel(
            id: UUID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: MobileBrowserPageStoreRegistry(
                primary: MobileBrowserPageStore(browser: rootBrowser, usesEphemeralWebsiteDataStores: true)),
            spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .search,
            usesEphemeralWebsiteDataStores: true)
    }

    /// The browser a scene shows, which it makes anew each time it shows one.
    private func makeRoot(for scene: MobileBrowserWindowSceneModel) -> MobileBrowserRootModel {
        MobileBrowserRootModel(
            browser: scene.browser, pages: scene.pages, navigation: scene.navigation, spaceAccess: scene.spaceAccess,
            windowState: scene.windowState, startupBehavior: scene.startupBehavior, greeting: scene.greeting,
            persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth)
    }
}
