import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageConfigurationTests: XCTestCase {
    func testMobilePageSuspendsInactiveWebContentLikeTheSharedFactory() {
        let space = makeSpace(index: 1)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            openNewTab: { _ in }
        )
        let configuration = page.webView.configuration

        XCTAssertEqual(
            configuration.preferences.inactiveSchedulingPolicy,
            .suspend,
            "iOS is the platform that jetsams, so resident background tabs must let WebKit suspend them."
        )
        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
        XCTAssertTrue(configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertFalse(configuration.limitsNavigationsToAppBoundDomains)
        XCTAssertTrue(configuration.upgradeKnownHostsToHTTPS)
        XCTAssertTrue(configuration.allowsAirPlayForMediaPlayback)
        XCTAssertFalse(configuration.suppressesIncrementalRendering)
    }

    func testMobilePageKeepsItsPlatformSpecificMediaAndPeekDecoration() {
        let space = makeSpace(index: 2)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            openNewTab: { _ in }
        )
        let configuration = page.webView.configuration

        XCTAssertEqual(
            configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended,
            "Mobile keeps the recommended content mode rather than the shared desktop default."
        )
        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(configuration.allowsInlineMediaPlayback)
        XCTAssertTrue(configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertTrue(
            configuration.userContentController.userScripts.contains {
                $0.source == MobileMediaPlaybackPolicy.inlineVideoScript.source
            }
        )
        XCTAssertTrue(
            page.hasActiveLinkPeekBridge,
            "Routing through the shared factory must keep the link-peek bridge installed."
        )
    }

    func testMobileWebViewIsOnlyInspectableInADebugBuild() {
        let space = makeSpace(index: 3)
        let page = MobileBrowserPage(
            tab: space.tabs[0],
            space: space,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            openNewTab: { _ in }
        )

        #if DEBUG
            XCTAssertTrue(
                page.webView.isInspectable,
                "A debug build keeps Web Inspector available for development."
            )
        #else
            XCTAssertFalse(
                page.webView.isInspectable,
                "iOS ships no developer tooling, so a release web view must not accept an attached inspector."
            )
        #endif
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
