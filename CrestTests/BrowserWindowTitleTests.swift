import AppKit
import Observation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWindowTitleTests: XCTestCase {

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
            committedURL: space.tabs[1].url!,
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

    func testDeletingSpaceImmediatelyRedactsItsTitle() {
        let model = makeModel()
        XCTAssertTrue(model.browser.family.beginDeletingSpace(model.browser.selectedSpaceID))
        XCTAssertEqual(model.windowTitle, ProductIdentity.name)
    }

    func testSpaceSwitchRejectsThePreviousActivePage() async throws {
        let model = makeModel()
        model.pages.select(session: model.browser.presented)
        let page = try XCTUnwrap(model.pages.activePage)
        try await load("Live Alpha", into: page)
        let beta = BrowserTab(title: "Beta", url: URL(string: "https://beta.crest.test"), placement: .current)
        let destination = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Other", symbol: "circle", accent: .indigo,
            folders: [], tabs: [beta]
        )
        model.browser.session.spaces.append(destination)
        model.browser.selectSpace(destination.id)
        XCTAssertEqual(model.pages.activeTabID, model.browser.session.spaces[0].tabs[0].id)
        XCTAssertEqual(model.windowTitle, "Beta")
        let sessionBeforePageCallbacks = model.browser.session
        model.address = "Destination address draft"

        model.synchronizePageMetadata()
        model.recordCompletedNavigation()

        XCTAssertEqual(model.browser.session, sessionBeforePageCallbacks)
        XCTAssertEqual(model.address, "Destination address draft")
    }



    private func makeModel(browser: BrowserStore? = nil) -> BrowserRootModel {
        let alpha = BrowserTab(title: "Alpha", url: URL(string: "https://alpha.crest.test"), placement: .current)
        let beta = BrowserTab(title: "Beta", url: URL(string: "https://beta.crest.test"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [alpha, beta]
        )
        return BrowserRootModel(
            browser: browser
                ?? BrowserStore(
                    session: BrowserSession(spaces: [space])
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
