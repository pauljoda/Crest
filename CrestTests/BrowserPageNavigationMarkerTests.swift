import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageNavigationMarkerTests: XCTestCase {
    func testTheAppInitiatedMarkerIsConsumedByTheNavigationItAuthorized() throws {
        let page = try makePage()
        let fileURL = URL(fileURLWithPath: "/tmp/crest-desktop-fixture.html")
        let replay = ReplayNavigationAction(url: fileURL)

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

    func testARestoredInteractionStateMarkerIsConsumedTheSameWay() throws {
        let page = try makePage()
        let fileURL = URL(fileURLWithPath: "/tmp/crest-desktop-restored.html")
        let replay = ReplayNavigationAction(url: fileURL)

        // WebKit refuses random state, which is enough here: the marker is set
        // before the state is installed either way.
        _ = page.restoreInteractionState(
            Data((0..<256).map { _ in UInt8.random(in: 0...255) }),
            expecting: fileURL
        )
        XCTAssertTrue(page.isAppInitiated(replay))

        page.webView(page.webView, didStartProvisionalNavigation: nil)

        XCTAssertFalse(page.isAppInitiated(replay))
    }

    func testANewWindowRequestFromAnExtensionPageIsNotATopLevelNavigation() throws {
        let page = try makePage()
        let extensionURL = try XCTUnwrap(
            URL(string: "webkit-extension://abcdef/options.html")
        )
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/docs"))
        let newWindowAction = NewWindowNavigationAction(url: destinationURL)

        XCTAssertNil(
            newWindowAction.targetFrame,
            "WebKit reports no target frame for a new-window request."
        )
        XCTAssertFalse(
            page.isTopLevelNavigation(newWindowAction),
            "A missing target frame is a new window, not this page's main frame."
        )
        XCTAssertFalse(
            BrowserExtensionExternalNavigationPolicy.shouldOpenInBrowserTab(
                currentURL: extensionURL,
                destinationURL: destinationURL,
                isTopLevel: page.isTopLevelNavigation(newWindowAction),
                isAppInitiated: false
            ),
            "A target=\"_blank\" link on an extension page must not be cancelled and reloaded in place."
        )
        XCTAssertTrue(
            BrowserExtensionExternalNavigationPolicy.shouldOpenInBrowserTab(
                currentURL: extensionURL,
                destinationURL: destinationURL,
                isTopLevel: true,
                isAppInitiated: false
            ),
            "A genuine top-level navigation away from an extension page still opens a browser tab."
        )
    }

    private func makePage() throws -> BrowserPage {
        let tab = BrowserTab.startPage()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Marker",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let pool = BrowserPagePool()
        pool.select(tab: tab, space: space)
        return try XCTUnwrap(pool.activePage)
    }
}

/// Stands in for a navigation web content asks for while naming a URL Crest once
/// loaded itself. WebKit never lets an app build a real `WKNavigationAction`, and
/// the web source origin is what separates a replay from Crest's own load.
private final class ReplayNavigationAction: WKNavigationAction,
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

/// The action WebKit hands `decidePolicyFor` for a `target="_blank"` link or a
/// `window.open()`: no target frame at all, because the frame does not exist yet.
private final class NewWindowNavigationAction: WKNavigationAction {
    private let stubRequest: URLRequest

    init(url: URL) {
        stubRequest = URLRequest(url: url)
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { .linkActivated }
    override var targetFrame: WKFrameInfo? { nil }
}
