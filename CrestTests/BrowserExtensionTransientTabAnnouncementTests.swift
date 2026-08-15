import WebKit
import XCTest

@testable import Crest

/// Pins the order a new web view is introduced to extensions in.
///
/// WebKit injects a granted extension's content scripts while a page loads and
/// answers the `runtime` messages they send only for a web view it can map onto
/// a tab the host has announced. A script that asks its background for
/// configuration before that announcement is rejected outright — WebKit logs
/// `Tab not found for message for content script message` — and nothing retries
/// it, so an extension that styles pages keeps whatever partial state it applied
/// until the document is reloaded.
///
/// Both paths that build a web view and navigate it in the same turn have to
/// announce first: a Peek, whose page the session never carries as a tab at all,
/// and the cards a selection brings on screen.
@MainActor
final class BrowserExtensionTransientTabAnnouncementTests: XCTestCase {

    /// Forwards to the real pool while recording what the coordinator saw at
    /// the moment it announced each tab.
    ///
    /// The coordinator resolves every tab's web view while projecting the state
    /// it diffs, so the loading state captured here is the page's state at
    /// announcement time — which is exactly the ordering under test.
    private final class AnnouncementProbe: BrowserExtensionPageProviding {
        private let pool: BrowserPagePool
        private(set) var loadingWhenResolved: [TabID: [Bool]] = [:]

        init(pool: BrowserPagePool) {
            self.pool = pool
        }

        func extensionWebView(
            for tabID: TabID,
            in spaceID: SpaceID
        ) -> WKWebView? {
            let webView = pool.extensionWebView(for: tabID, in: spaceID)
            if let webView {
                loadingWhenResolved[tabID, default: []].append(webView.isLoading)
            }
            return webView
        }

        func extensionReaderModeState(
            for tabID: TabID,
            in spaceID: SpaceID
        ) -> BrowserReaderModeState {
            pool.extensionReaderModeState(for: tabID, in: spaceID)
        }

        func setExtensionReaderModeActive(
            _ isActive: Bool,
            for tabID: TabID,
            in spaceID: SpaceID
        ) async throws {
            try await pool.setExtensionReaderModeActive(
                isActive,
                for: tabID,
                in: spaceID
            )
        }

        func extensionWindowGeometry(
            in spaceID: SpaceID
        ) -> BrowserExtensionWindowGeometry {
            pool.extensionWindowGeometry(in: spaceID)
        }

        func prepareExtensionSelection(session: BrowserSession) {
            pool.prepareExtensionSelection(session: session)
        }

        func select(session: BrowserSession) {
            pool.select(session: session)
        }
    }

    // MARK: - Peek

    func testAPeekPageIsAnnouncedToExtensionsBeforeItNavigates() throws {
        let space = makeSpace(tabs: [])
        let harness = try makeHarness(space: space)
        let url = try XCTUnwrap(URL(string: "https://example.com/"))

        let lease = try XCTUnwrap(
            harness.pages.makeTransientPageLease(url: url, in: space)
        )

        // The page extensions were told about is the page the person is
        // reading: an adapter that cannot answer with a web view is a tab
        // extensions can see but never reach.
        let webView = try XCTUnwrap(
            harness.pages.extensionWebView(
                for: lease.extensionTabID,
                in: space.id
            )
        )
        let observed = try XCTUnwrap(
            harness.probe.loadingWhenResolved[lease.extensionTabID]
        )
        XCTAssertFalse(observed.isEmpty, "The Peek page was never announced.")
        XCTAssertTrue(
            observed.allSatisfy { $0 == false },
            "The Peek page was announced after it had already started loading."
        )
        // The load did start, so the readings above are an ordering rather than
        // a page that simply never navigated.
        XCTAssertTrue(webView.isLoading)
    }

    func testReleasingAPeekWithdrawsTheTabExtensionsWereTold() throws {
        let space = makeSpace(tabs: [])
        let harness = try makeHarness(space: space)
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let lease = try XCTUnwrap(
            harness.pages.makeTransientPageLease(url: url, in: space)
        )
        XCTAssertNotNil(
            harness.pages.extensionWebView(
                for: lease.extensionTabID,
                in: space.id
            )
        )

        lease.release()

        XCTAssertNil(
            harness.pages.extensionWebView(
                for: lease.extensionTabID,
                in: space.id
            )
        )
    }

    func testAdoptingAPeekWithdrawsItsTransientAnnouncement() throws {
        let space = makeSpace(tabs: [])
        let harness = try makeHarness(space: space)
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let lease = try XCTUnwrap(
            harness.pages.makeTransientPageLease(url: url, in: space)
        )
        let transientTabID = lease.extensionTabID

        // Promotion hands the live page to a real tab, which announces itself.
        let adopted = BrowserTab(title: "Adopted", url: url, placement: .current)
        var promoted = space
        promoted.tabs = [adopted]
        promoted.selectedTabID = adopted.id
        XCTAssertTrue(
            harness.pages.adoptTransientPage(
                lease,
                as: adopted.id,
                in: promoted
            )
        )

        XCTAssertNil(
            harness.pages.extensionWebView(for: transientTabID, in: space.id),
            "One web view was left described as two tabs."
        )
        XCTAssertNotNil(
            harness.pages.extensionWebView(for: adopted.id, in: space.id)
        )
    }

    // MARK: - Split members

    func testSplitMembersAreAnnouncedBeforeTheirFirstNavigation() throws {
        let group = SplitGroupID()
        let leading = BrowserTab(
            title: "Leading",
            url: URL(string: "https://example.com/leading"),
            placement: .current,
            splitGroupID: group
        )
        let trailing = BrowserTab(
            title: "Trailing",
            url: URL(string: "https://example.com/trailing"),
            placement: .current,
            splitGroupID: group
        )
        let space = makeSpace(
            tabs: [leading, trailing],
            selectedTabID: leading.id
        )
        let harness = try makeHarness(space: space)

        harness.pages.select(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id)
        )

        for member in [leading, trailing] {
            let observed = try XCTUnwrap(
                harness.probe.loadingWhenResolved[member.id],
                "A split member was never announced."
            )
            XCTAssertTrue(
                observed.allSatisfy { $0 == false },
                """
                A split member was announced after it had already started \
                loading, so a content script injected into it can be answered \
                only once the page is reloaded.
                """
            )
            XCTAssertTrue(
                try XCTUnwrap(
                    harness.pages.extensionWebView(
                        for: member.id,
                        in: space.id
                    )
                ).isLoading
            )
        }
    }

    // MARK: - Support

    private struct Harness {
        let pages: BrowserPagePool
        let extensions: BrowserExtensionControllerPool
        let browser: BrowserStore
        let probe: AnnouncementProbe
    }

    private func makeHarness(space: BrowserSpace) throws -> Harness {
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let extensions = BrowserExtensionControllerPool(
            usesEphemeralWebKitStorage: true
        )
        let pages = BrowserPagePool(extensionControllerPool: extensions)
        let probe = AnnouncementProbe(pool: pages)
        extensions.connect(browser: browser, pageProvider: probe)
        // Registers the Space's controller, so announcements have somewhere to
        // land rather than being diffed against nothing.
        _ = extensions.controller(for: space)
        return Harness(
            pages: pages,
            extensions: extensions,
            browser: browser,
            probe: probe
        )
    }

    private func makeSpace(
        tabs: [BrowserTab],
        selectedTabID: TabID? = nil
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Announcement",
            symbol: "puzzlepiece.extension.fill",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: selectedTabID
        )
    }
}
