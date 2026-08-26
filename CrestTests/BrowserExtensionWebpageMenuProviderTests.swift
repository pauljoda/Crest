import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebpageMenuProviderTests: XCTestCase {
    func testMissingOrStaleResidentTabReturnsNoItems() {
        let provider = BrowserExtensionWebpageMenuProvider(
            extensionControllerPool: BrowserExtensionControllerPool()
        )

        XCTAssertTrue(
            provider.items(
                for: TabID(),
                in: SpaceID(),
                context: makeContext()
            ).isEmpty
        )
    }

    func testResidentTabWithNoLoadedExtensionsReturnsNoItems() throws {
        let tab = BrowserTab(
            title: "No Extensions",
            url: makeContext().pageURL,
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "No Extensions",
            symbol: "puzzlepiece.extension",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let registry = BrowserExtensionWebpageMenuRegistry()
        let pool = BrowserExtensionControllerPool(
            webpageMenuRegistry: registry
        )
        let pages = ProviderPageStub()
        pages.webViews[tab.id] = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(
                for: space.profile,
                webExtensionController: pool.controller(for: space)
            )
        )
        pool.connect(browser: browser, pageProvider: pages)
        let unrelatedClient = try XCTUnwrap(
            BrowserExtensionServiceClientID("another-space.extension")
        )
        try registry.replaceDefinitions(
            message: [
                "api": "contextMenus.replace",
                "items": [
                    [
                        "id": "string:private-image",
                        "type": "normal",
                        "title": "Private Image",
                        "contexts": ["image"],
                        "documentUrlPatterns": [],
                        "targetUrlPatterns": [],
                        "enabled": true,
                        "visible": true,
                    ] as [String: Any]
                ],
            ],
            for: unrelatedClient
        )
        let provider = BrowserExtensionWebpageMenuProvider(
            extensionControllerPool: pool
        )

        XCTAssertTrue(
            provider.items(
                for: tab.id,
                in: space.id,
                context: makeContext()
            ).isEmpty,
            "Definitions owned by another client or profile cannot contribute without a matching loaded context in this Space."
        )
    }

    private func makeContext() -> BrowserExtensionWebpageMenuContext {
        BrowserExtensionWebpageMenuContext(
            pageURL: URL(string: "https://example.com/page")!,
            documentURL: URL(string: "https://example.com/page")!,
            linkURL: nil,
            sourceURL: URL(string: "https://example.com/photo.webp"),
            selectionText: nil,
            isEditable: false,
            isMainFrame: true
        )
    }
}

@MainActor
private final class ProviderPageStub:
    BrowserExtensionPageProviding
{
    var webViews: [TabID: WKWebView] = [:]

    func extensionWebView(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> WKWebView? {
        webViews[tabID]
    }

    func extensionReaderModeState(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserReaderModeState {
        .unavailable
    }

    func setExtensionReaderModeActive(
        _ isActive: Bool,
        for tabID: TabID,
        in spaceID: SpaceID
    ) async throws {}

    func extensionWindowGeometry(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowGeometry {
        .unavailable
    }

    func prepareExtensionSelection(session: BrowserSession) {}

    func select(session: BrowserSession) {}
}
