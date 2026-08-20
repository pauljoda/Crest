import Foundation
import XCTest

@testable import CrestMobile

/// The compact shell's binding of the shared row actions. The guards belong to
/// `BrowserSidebarTabActionsTests`; what is tested here is only what this shell
/// binds them to — the store's favicon pull, and a page layer with nothing to
/// reconcile after a tab-list mutation.
@MainActor
final class MobileBrowserSidebarTabActionsTests: XCTestCase {
    /// A tab holding no page has no favicon to report, and the store says so
    /// rather than leaving the row to write something stale.
    func testFaviconPullThroughTheStoreReportsNothingForATabWithNoPage() async throws {
        let context = makeContext()
        let action = makeActions(context)

        let didPullIcon = await action.pullNewIcon(for: context.tab.id)

        XCTAssertFalse(didPullIcon)
        XCTAssertNil(
            try XCTUnwrap(context.browser.selectedSpace)
                .tabs.first(where: { $0.id == context.tab.id })?
                .faviconData
        )
    }

    /// The compact shell's single page follows the session on its own, so a
    /// clear goes through with nothing to reconcile behind it.
    func testClearingCurrentTabsNeedsNoPageReconciliation() throws {
        let context = makeContext()
        let action = makeActions(context)

        XCTAssertTrue(action.clearCurrentTabs())

        XCTAssertFalse(
            try XCTUnwrap(context.browser.selectedSpace)
                .tabs.contains(where: { $0.placement == .current })
        )
    }

    private func makeActions(_ context: Context) -> BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: BrowserSpaceRuntimeAssignment(space: context.space),
            browser: context.browser,
            pages: context.pages,
            spaceAccess: context.access
        )
    }

    private func makeContext() -> Context {
        let tab = BrowserTab(
            id: TabID(rawValue: Self.uuid(1)),
            title: "Current tab",
            url: URL(string: "https://sidebar.crest.test"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(2)),
            profile: BrowsingProfile(id: Self.uuid(3)),
            name: "Exact Space",
            symbol: "sidebar.left",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        return Context(
            browser: BrowserStore(
                session: BrowserSession(
                    spaces: [space],
                    selectedSpaceID: space.id
                ),
                persistence: InMemoryBrowserSessionPersistence(),
                browsingMode: .privateBrowsing
            ),
            pages: MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true),
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            space: space,
            tab: tab
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x49,
                0x43, 0x4F, 0x4E, 0x53, 0x00, 0x00, 0x00, finalByte
            )
        )
    }

    private struct Context {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let access: BrowserSpaceAccessController
        let space: BrowserSpace
        let tab: BrowserTab
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
