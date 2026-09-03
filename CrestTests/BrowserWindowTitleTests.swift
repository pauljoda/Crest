import AppKit
import Observation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWindowTitleTests: XCTestCase {
    func testRestoredSelectionUsesOnlyItsOwnTabTitle() {
        let model = makeModel()
        XCTAssertEqual(model.windowTitle, "Alpha")
        model.browser.selectTab(model.browser.selectedSpace!.tabs[1].id)
        XCTAssertEqual(model.windowTitle, "Beta")
    }

    func testCustomTabTitleWinsAndWhitespaceRenameReturnsToPageTitle() {
        let model = makeModel()
        model.browser.session.spaces[0].tabs[0].customTitle = "  My tab  "
        XCTAssertEqual(model.windowTitle, "My tab")
        model.browser.session.spaces[0].tabs[0].customTitle = " \n "
        XCTAssertEqual(model.windowTitle, "Alpha")
    }

    func testStartPageAndMissingSelectionNeverRetainThePreviousTitle() {
        let model = makeModel()
        model.browser.session.spaces[0].tabs = [.startPage()]
        model.browser.session.spaces[0].selectedTabID = model.browser.session.spaces[0].tabs[0].id
        XCTAssertEqual(model.windowTitle, String(localized: "Start Page"))
        model.browser.session.spaces[0].tabs = []
        model.browser.session.spaces[0].selectedTabID = nil
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
    }

    func testBlankTitlesUseSafeHostWithoutCredentialsPathOrQuery() {
        let model = makeModel()
        model.browser.session.spaces[0].tabs[0].title = " \n\t "
        model.browser.session.spaces[0].tabs[0].url = URL(
            string: "https://user:secret@www.example.com:8443/private?token=secret")
        XCTAssertEqual(model.windowTitle, "example.com:8443")
        model.browser.session.spaces[0].tabs[0].url = URL(string: "file:///private/secret.html")
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
    }

    func testLockedSpaceRedactsTitleAndURLBeforePageReconciliation() async {
        let model = makeModel()
        model.browser.session.spaces[0].accessPolicy = .deviceOwnerAuthentication
        let space = model.browser.selectedSpace!
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
        let unlocked = await model.spaceAccess.unlock(space)
        XCTAssertTrue(unlocked)
        XCTAssertEqual(model.windowTitle, "Alpha")
        let changed = expectation(description: "Window title observes relock")
        withObservationTracking {
            _ = model.windowTitle
        } onChange: {
            changed.fulfill()
        }
        model.spaceAccess.lock(space.id)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
    }

    func testWindowLocalSelectionDoesNotFollowAnotherWindow() {
        let first = makeModel()
        let second = makeModel(browser: first.browser.makeWindowStore())
        second.browser.selectTab(second.browser.selectedSpace!.tabs[1].id)
        second.browser.updateSelectedTabFromPage(url: nil, title: "Other window changed")
        XCTAssertEqual(first.windowTitle, "Alpha")
        XCTAssertEqual(second.windowTitle, "Other window changed")
    }

    func testBackgroundMetadataDoesNotOverwriteFocusedSplitMember() {
        let model = makeModel()
        let group = SplitGroupID()
        model.browser.session.spaces[0].tabs[0].splitGroupID = group
        model.browser.session.spaces[0].tabs[1].splitGroupID = group
        let space = model.browser.selectedSpace!
        model.browser.updateTabFromPage(
            url: space.tabs[1].url,
            title: "Background Beta",
            for: space.tabs[1].id,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
        XCTAssertEqual(model.windowTitle, "Alpha")
        model.browser.selectTab(space.tabs[1].id)
        XCTAssertEqual(model.windowTitle, "Background Beta")
        model.browser.selectTab(space.tabs[0].id)
        XCTAssertEqual(model.windowTitle, "Alpha")
    }

    func testTabClosureAndRestorationRecomputeTheTitle() {
        let model = makeModel()
        let alpha = model.browser.selectedTab!
        model.browser.closeTab(alpha.id)
        XCTAssertNil(model.browser.selectedTab)
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
        model.browser.restoreArchivedTab(alpha.id)
        XCTAssertEqual(model.windowTitle, "Alpha")
    }

    func testDeletingSpaceImmediatelyRedactsItsTitle() {
        let model = makeModel()
        XCTAssertTrue(model.browser.family.beginDeletingSpace(model.browser.session.selectedSpaceID))
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
    }

    func testNavigationFailureDoesNotKeepThePreviousDocumentTitle() async throws {
        let model = makeModel()
        model.pages.select(session: model.browser.session)
        let page = try XCTUnwrap(model.pages.activePage)
        try await load("Previous Document", into: page)
        page.prepareForNavigation(to: URL(string: "https://failed.crest.test/secret"))
        page.recordNavigationFailure(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost),
            phase: .provisional, navigation: nil
        )
        XCTAssertNotNil(page.navigationFailure)
        XCTAssertEqual(model.windowTitle, "failed.crest.test")
    }

    func testSpaceSwitchRejectsThePreviousActivePage() async throws {
        let model = makeModel()
        model.pages.select(session: model.browser.session)
        let page = try XCTUnwrap(model.pages.activePage)
        try await load("Live Alpha", into: page)
        var destination = model.browser.selectedSpace!
        destination = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Other", symbol: "circle", accent: .indigo,
            folders: [], tabs: [destination.tabs[1]], selectedTabID: destination.tabs[1].id
        )
        model.browser.session.spaces.append(destination)
        model.browser.selectSpace(destination.id)
        XCTAssertEqual(model.pages.activeTabID, model.browser.session.spaces[0].tabs[0].id)
        XCTAssertEqual(model.windowTitle, "Beta")
    }

    func testLiveDocumentTitleAndEmptyTitleAreObservedWithoutStoredMetadata() async throws {
        let model = makeModel()
        model.pages.select(session: model.browser.session)
        let page = try XCTUnwrap(model.pages.activePage)
        try await load("Live Alpha", into: page)
        XCTAssertEqual(model.windowTitle, "Live Alpha")
        let changed = expectation(description: "Window title observes document title")
        withObservationTracking {
            _ = model.windowTitle
        } onChange: {
            changed.fulfill()
        }
        try await page.webView.evaluateJavaScript("document.title = 'Updated Alpha'")
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(model.windowTitle, "Updated Alpha")
        try await page.webView.evaluateJavaScript("document.title = ''")
        try await waitUntil { page.title.isEmpty }
        XCTAssertEqual(model.windowTitle, "alpha.crest.test")
    }

    func testPendingNavigationDoesNotReuseThePreviousDocumentTitle() async throws {
        let model = makeModel()
        model.pages.select(session: model.browser.session)
        let page = try XCTUnwrap(model.pages.activePage)
        try await load("Previous Document", into: page)
        page.prepareForNavigation(to: URL(string: "https://destination.crest.test/private"))
        XCTAssertEqual(model.windowTitle, "destination.crest.test")
    }

    func testExtensionCommandsUseWindowIdentityNotPageTitle() {
        let browserWindow = NSWindow()
        browserWindow.identifier = NSUserInterfaceItemIdentifier(BrowserSceneID.browser.rawValue)
        browserWindow.title = "A webpage title"
        XCTAssertTrue(BrowserExtensionCommandMonitor.acceptsWindow(browserWindow))
        for role in BrowserSceneID.allCases where role != .browser {
            let other = NSWindow()
            other.identifier = NSUserInterfaceItemIdentifier(role.rawValue)
            other.title = ProductIdentity.name
            XCTAssertFalse(BrowserExtensionCommandMonitor.acceptsWindow(other))
        }
        XCTAssertFalse(BrowserExtensionCommandMonitor.acceptsWindow(nil))
    }

    private func makeModel(browser: BrowserStore? = nil) -> BrowserRootModel {
        let alpha = BrowserTab(title: "Alpha", url: URL(string: "https://alpha.crest.test"), placement: .current)
        let beta = BrowserTab(title: "Beta", url: URL(string: "https://beta.crest.test"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [alpha, beta], selectedTabID: alpha.id
        )
        return BrowserRootModel(
            browser: browser
                ?? BrowserStore(
                    session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
                    persistence: InMemoryBrowserSessionPersistence()
                ),
            pages: BrowserPagePool(),
            chrome: BrowserChromeState(),
            spaceAccess: BrowserSpaceAccessController(authenticator: TitleAuthenticator()),
            windowState: nil, startupBehavior: .lastActiveTab,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )
    }

    private func load(_ title: String, into page: BrowserPage) async throws {
        page.webView.loadSimulatedRequest(
            URLRequest(url: URL(string: "https://alpha.crest.test")!),
            responseHTML: "<html><head><title>\(title)</title></head><body>Fixture</body></html>"
        )
        try await waitUntil { page.title == title && !page.isLoading }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for document metadata")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private final class TitleAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason: String) async throws -> Bool { true }
    }
}
