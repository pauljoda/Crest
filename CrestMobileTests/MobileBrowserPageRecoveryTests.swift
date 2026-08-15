import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageRecoveryTests: XCTestCase {

    // MARK: - Reclaimed web-content processes

    func testTerminationOffScreenNeitherReloadsNorSpendsTheRecoveryBudget() {
        let space = makeSpace(index: 1)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            openNewTab: { _ in }
        )
        XCTAssertNil(page.webView.window, "A resident background page is attached to no window.")

        page.recordWebContentTermination()
        page.recordWebContentTermination()
        page.recordWebContentTermination()

        XCTAssertFalse(
            page.showsProcessFailure,
            "iOS reclaiming a background tab's process is routine eviction, not repeated failure."
        )
    }

    func testAReclaimedBackgroundPageIsRestoredWhenItIsSelectedAgain() throws {
        let space = makeSpace(index: 2)
        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pages = MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true)
        pages.select(session: session)
        let page = try XCTUnwrap(pages.activePage)

        page.recordWebContentTermination()

        XCTAssertTrue(page.needsWebContentRestore)
        XCTAssertFalse(page.showsProcessFailure)

        pages.deactivatePagePresentation()
        pages.select(session: session)

        XCTAssertTrue(try XCTUnwrap(pages.activePage) === page)
        XCTAssertFalse(
            page.needsWebContentRestore,
            "Selecting the tab again is where a reclaimed page comes back."
        )
    }

    // MARK: - App-initiated navigation marker

    func testTheAppInitiatedMarkerIsConsumedByTheNavigationItAuthorized() throws {
        let space = makeSpace(index: 4)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            openNewTab: { _ in }
        )
        let fileURL = URL(fileURLWithPath: "/tmp/crest-mobile-fixture.html")
        let replay = MobileReplayNavigationAction(url: fileURL)

        page.load(fileURL)
        XCTAssertTrue(
            page.isAppInitiated(replay),
            "The load Crest just asked for is app-initiated until WebKit honors it."
        )

        page.webView(page.webView, didStartProvisionalNavigation: nil)

        XCTAssertFalse(
            page.isAppInitiated(replay),
            "Web content must not be able to replay a file URL Crest once loaded."
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: fileURL,
                isAppInitiated: page.isAppInitiated(replay)
            ),
            .blocked
        )
    }

    private func makeSpace(index: Int) -> BrowserSpace {
        let tab = BrowserTab.startPage(
            id: TabID(rawValue: fixedUUID(index * 10 + 1)),
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(index * 10 + 2)),
            profile: BrowsingProfile(id: fixedUUID(index * 10 + 3)),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}

/// Stands in for a navigation web content asks for while naming a URL Crest once
/// loaded itself. WebKit never lets an app build a real `WKNavigationAction`, and
/// the web source origin is what separates a replay from Crest's own load.
private final class MobileReplayNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest

    init(url: URL) {
        stubRequest = URLRequest(url: url)
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { .other }
    override var targetFrame: WKFrameInfo? { nil }
    var browserSourceOrigin: BrowserSiteOrigin? {
        BrowserSiteOrigin(scheme: "https", host: "replay.crest.test", port: 443)
    }
}
