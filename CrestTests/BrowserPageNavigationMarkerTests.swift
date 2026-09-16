import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageNavigationMarkerTests: XCTestCase {
    private var navigationSource: WKWebView?

    func testSameDocumentNavigationRetiresPendingURLAcrossHistoryTraversal() async throws {
        let page = try makePage()
        defer { page.prepareForSpaceDeletion() }
        let root = try XCTUnwrap(URL(string: "https://history.crest.test/feed"))
        let post = try XCTUnwrap(URL(string: "https://history.crest.test/post"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: root), responseHTML: "<html><title>Feed</title><body>Feed</body></html>")
        try await waitForNavigation { page.completedNavigationCount == 1 }
        let commits = page.committedNavigationCount

        // A site may intercept an allowed link and finish it in the existing
        // document. No didFinish callback will retire its pending destination.
        page.prepareForNavigation(to: post)
        _ = try await page.webView.evaluateJavaScript("history.pushState({}, '', '/post')")
        try await waitForNavigation { page.url == post }
        XCTAssertNil(page.pendingNavigationURL)
        XCTAssertEqual(page.displayURL, post)
        XCTAssertEqual(page.backHistory.map(\.url), page.webView.backForwardList.backList.reversed().map(\.url))

        _ = try await page.webView.evaluateJavaScript("history.back()")
        try await waitForNavigation { page.url == root }
        XCTAssertEqual(page.displayURL, root)
        XCTAssertEqual(page.committedNavigationCount, commits)

        _ = try await page.webView.evaluateJavaScript("history.forward()")
        try await waitForNavigation { page.url == post }
        _ = try await page.webView.evaluateJavaScript("history.replaceState({}, '', '/updated-post')")
        let replaced = try XCTUnwrap(URL(string: "https://history.crest.test/updated-post"))
        try await waitForNavigation { page.url == replaced }
        XCTAssertEqual(page.displayURL, replaced)
        XCTAssertNil(page.pendingNavigationURL)
    }

    func testLinkHistoryRetainsSameDocumentEntriesAndDiscardsForwardBranch() async throws {
        let page = try makePage()
        defer { page.prepareForSpaceDeletion() }
        let root = try XCTUnwrap(URL(string: "https://history.crest.test/root"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: root), responseHTML: "<html><title>History</title><body>History</body></html>")
        try await waitForNavigation { page.completedNavigationCount == 1 }
        let feed = try XCTUnwrap(URL(string: "https://history.crest.test/feed"))
        let post = try XCTUnwrap(URL(string: "https://history.crest.test/post"))
        for destination in [feed, post] {
            page.navigationHistory.recordLink(to: destination, in: page.webView.backForwardList)
            page.prepareForNavigation(to: destination)
            _ = try await page.webView.evaluateJavaScript("history.pushState({}, '', '\(destination.path)')")
            try await waitForNavigation { page.url == destination }
        }
        XCTAssertEqual(page.backHistory.map(\.url), [feed, root])
        page.goBack()
        try await waitForNavigation { page.url == feed }
        XCTAssertEqual(page.displayURL, feed)
        XCTAssertEqual(page.forwardHistory.map(\.url), [post])
        page.goForward(toDepth: 1)
        try await waitForNavigation { page.url == post }
        page.goBack(toDepth: 2)
        try await waitForNavigation { page.url == root }
        XCTAssertEqual(page.forwardHistory.map(\.url), [feed, post])
        page.goForward()
        try await waitForNavigation { page.url == feed }

        // Replacing the current entry must not create a duplicate. A new link
        // after Back must discard the old forward branch, even for equal URLs.
        _ = try await page.webView.evaluateJavaScript("history.replaceState({}, '', '/updated-feed')")
        let updated = try XCTUnwrap(URL(string: "https://history.crest.test/updated-feed"))
        try await waitForNavigation { page.url == updated }
        XCTAssertEqual(page.backHistory.map(\.url), [root])
        page.navigationHistory.recordLink(to: root, in: page.webView.backForwardList)
        page.prepareForNavigation(to: root)
        _ = try await page.webView.evaluateJavaScript("history.pushState({}, '', '/root')")
        try await waitForNavigation { page.url == root }
        XCTAssertEqual(page.backHistory.map(\.url), [updated, root])
        XCTAssertTrue(page.forwardHistory.isEmpty)

        // A replacement document returns ownership to WebKit's native list;
        // supplemental same-document items must not become obsolete targets.
        let replacement = try XCTUnwrap(URL(string: "https://history.crest.test/new-document"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: replacement), responseHTML: "<html><body>New document</body></html>")
        try await waitForNavigation { page.completedNavigationCount == 2 }
        XCTAssertEqual(page.backHistory.map(\.url), page.webView.backForwardList.backList.reversed().map(\.url))
    }

    private func waitForNavigation(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "The expected navigation did not settle.")
    }

    func testLinkDraggingRemainsAvailableAcrossSameDocumentNavigation() async throws {
        let page = try makePage()
        defer { page.prepareForSpaceDeletion() }
        let webView = page.webView
        let world = BrowserLinkDragContentBridge.world
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                    const configure = globalThis.__crestLinkDrag.configure;
                    globalThis.__crestLinkDrag.configure = (enabled, available) => {
                      configure(enabled, available);
                      globalThis.crestTestDragAvailable = available;
                    };
                    """,
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world
            ))
        let root = try XCTUnwrap(URL(string: "https://peek.crest.test/navigation"))
        webView.loadSimulatedRequest(
            URLRequest(url: root), responseHTML: "<html><body><a href='#section'>Section</a></body></html>")
        let deadline = Date().addingTimeInterval(10)
        while page.completedNavigationCount == 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(page.completedNavigationCount, 0)
        let ready = try await webView.callAsyncJavaScript(
            "return globalThis.crestTestDragAvailable;", in: nil, contentWorld: world)
        XCTAssertEqual(ready as? Bool, true)
        let commits = page.committedNavigationCount

        _ = try await webView.evaluateJavaScript("location.hash = 'section'")
        let fragment = try XCTUnwrap(URL(string: root.absoluteString + "#section"))
        let navigationDeadline = Date().addingTimeInterval(5)
        while webView.url != fragment && Date() < navigationDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(webView.url, fragment)
        XCTAssertEqual(page.committedNavigationCount, commits, "A fragment change keeps the existing document.")
        let available = try await webView.callAsyncJavaScript(
            "return globalThis.crestTestDragAvailable;", in: nil, contentWorld: world)
        XCTAssertEqual(available as? Bool, true, "In-page navigation must leave link dragging available.")
    }

    func testFreshPageRevealsAtCommitBeforeNavigationFinishes() throws {
        let page = try makePage()
        let navigation = try makeNavigation()

        XCTAssertFalse(
            BrowserPageSurfacePolicy.revealsWebContent(
                committedNavigationCount: page.committedNavigationCount
            )
        )

        page.webView(page.webView, didStartProvisionalNavigation: navigation)
        page.webView(page.webView, didCommit: navigation)

        XCTAssertEqual(page.committedNavigationCount, 1)
        XCTAssertEqual(page.completedNavigationCount, 0)
        XCTAssertTrue(
            BrowserPageSurfacePolicy.revealsWebContent(
                committedNavigationCount: page.committedNavigationCount
            )
        )
    }

    func testSupersededCommitCannotRevealAFreshPage() throws {
        let page = try makePage()
        let superseded = try makeNavigation()
        let current = try makeNavigation()

        page.webView(page.webView, didStartProvisionalNavigation: superseded)
        page.webView(page.webView, didStartProvisionalNavigation: current)
        page.webView(page.webView, didCommit: superseded)

        XCTAssertEqual(page.committedNavigationCount, 0)
        XCTAssertFalse(
            BrowserPageSurfacePolicy.revealsWebContent(
                committedNavigationCount: page.committedNavigationCount
            )
        )

        page.webView(page.webView, didCommit: current)

        XCTAssertEqual(page.committedNavigationCount, 1)
        XCTAssertTrue(
            BrowserPageSurfacePolicy.revealsWebContent(
                committedNavigationCount: page.committedNavigationCount
            )
        )
    }

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
            URL(string: "crest-extension://abcdef/options.html")
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
            BrowserExtensionExternalNavigationPolicy.shouldReplaceCurrentTabRuntime(
                currentURL: extensionURL,
                destinationURL: destinationURL,
                isTopLevel: page.isTopLevelNavigation(newWindowAction),
                isAppInitiated: false
            ),
            "A target=\"_blank\" link on an extension page must not be cancelled and reloaded in place."
        )
        XCTAssertTrue(
            BrowserExtensionExternalNavigationPolicy.shouldReplaceCurrentTabRuntime(
                currentURL: extensionURL,
                destinationURL: destinationURL,
                isTopLevel: true,
                isAppInitiated: false
            ),
            "A top-level navigation away from an extension page replaces that runtime in its existing tab."
        )
    }

    func testCrestExtensionURLsRemainInsideWebKit() throws {
        let extensionURL = try XCTUnwrap(
            URL(
                string:
                    "crest-extension://extension-fixture/options.html"
            )
        )

        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(for: extensionURL),
            .webKit
        )
        XCTAssertEqual(
            BrowserPopupSchemeRouting.classify(
                destinationURL: extensionURL
            ),
            .popupPolicy
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

    private func makeNavigation() throws -> WKNavigation {
        let source =
            navigationSource
            ?? WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        navigationSource = source
        return try XCTUnwrap(source.loadHTMLString("<html></html>", baseURL: nil))
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
