import Foundation
import XCTest

@testable import CrestMobile

/// The compact shell's binding of the shared row actions. The guards belong to
/// `BrowserSidebarTabActionsTests`; what is tested here is only what this shell
/// binds them to — the store's favicon pull, and a page layer with nothing to
/// reconcile after a tab-list mutation.
@MainActor
final class MobileBrowserSidebarTabActionsTests: XCTestCase {
    func testRegisteredTabsAndFoldersFormAScopedSelectionForBatchActions() throws {
        let context = makeContext()
        let folder = BrowserFolder(title: "Research", location: .current)
        context.browser.session.spaces[0].folders.append(folder)
        let other = BrowserSession.makeBlankSpace(number: 2)
        context.browser.session.spaces.append(other)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.space)
        let state = context.sidebarInteraction.sidebarReorderState
        state.register(
            row: .init(
                id: .folder(folder.id), space: assignment, section: .folders(parentID: nil),
                frame: CGRect(x: 0, y: 0, width: 240, height: 44)), owner: UUID())
        state.register(
            row: .init(
                id: .tab(context.tab.id), space: assignment, section: .tabs(placement: .current, folderID: nil),
                frame: CGRect(x: 0, y: 44, width: 240, height: 44)), owner: UUID())
        state.register(
            row: .init(
                id: .tab(TabID()), space: BrowserSpaceRuntimeAssignment(space: other),
                section: .tabs(placement: .current, folderID: nil),
                frame: CGRect(x: 0, y: 88, width: 240, height: 44)), owner: UUID())

        let units = BrowserSidebarSelection.itemUnits(
            in: context.browser, reorder: context.sidebarInteraction.sidebarReorderState)
        XCTAssertEqual(units, [[.folder(folder.id)], [.tab(context.tab.id)]])
        context.browser.tabMultiSelection.click(.folder(folder.id), units: units, command: true)
        context.browser.tabMultiSelection.click(.tab(context.tab.id), units: units, command: true, shift: true)
        let request = try XCTUnwrap(
            BrowserSidebarSelection.request(
                for: context.tab.id, browser: context.browser, reorder: context.sidebarInteraction.sidebarReorderState))
        XCTAssertEqual(request.rootItems, [.folder(folder.id), .tab(context.tab.id)])
        let actions = BrowserTabBatchActions(browser: context.browser, spaceAccess: context.access)
        context.browser.selectSpace(other.id)
        let before = context.browser.session
        XCTAssertFalse(actions.perform(request, action: .file(.saved)))
        XCTAssertEqual(context.browser.session, before)

        context.browser.selectSpace(context.space.id)
        XCTAssertTrue(actions.perform(request, action: .file(.saved)))
        XCTAssertEqual(context.browser.selectedSpace?.folders.first?.location, .saved)
        XCTAssertEqual(context.browser.selectedSpace?.tabs.first(where: { $0.id == context.tab.id })?.placement, .saved)
        XCTAssertEqual(context.browser.session.space(id: other.id), before.space(id: other.id))
    }

    func testLinkMenuOpensInTheRequestedSpaceAndPreservesItsSource() throws {
        let context = makeContext()
        let otherSpace = BrowserSession.makeBlankSpace(number: 2)
        context.browser.session.spaces.append(otherSpace)
        let host = BrowserLinkDestinationHost(browser: context.browser, spaceAccess: context.access)
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id
        )
        let url = try XCTUnwrap(URL(string: "https://destination.crest.test"))

        XCTAssertTrue(host.openLink(url, from: source, in: BrowserSpaceRuntimeAssignment(space: otherSpace)))

        XCTAssertEqual(context.browser.selectedSpace?.id, otherSpace.id)
        XCTAssertEqual(context.browser.selectedSpace?.profile.id, otherSpace.profile.id)
        XCTAssertEqual(context.browser.selectedTab?.url, url)
        XCTAssertEqual(context.browser.session.space(id: source.spaceID)?.tabs, context.space.tabs)
        XCTAssertEqual(context.browser.session.spaces.count, 2)
        XCTAssertFalse(host.openLink(url, from: source, in: BrowserSpaceRuntimeAssignment(space: otherSpace)))
    }

    func testNewTabCallsTheMobileCommandOncePerRequestWithoutInsertingTabs() {
        let context = makeContext()
        let action = makeActions(context)
        let session = context.browser.session
        var invocationCount = 0

        XCTAssertTrue(action.openNewTab { invocationCount += 1 })
        XCTAssertTrue(action.openNewTab { invocationCount += 1 })

        XCTAssertEqual(invocationCount, 2)
        XCTAssertEqual(context.browser.session, session)
    }

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
            reorderState: context.sidebarInteraction.sidebarReorderState,
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

    @MainActor
    private struct Context {
        let sidebarInteraction: BrowserSidebarInteractionState
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let access: BrowserSpaceAccessController
        let space: BrowserSpace
        let tab: BrowserTab

        init(
            browser: BrowserStore, pages: MobileBrowserPageStore, access: BrowserSpaceAccessController,
            space: BrowserSpace, tab: BrowserTab
        ) {
            self.browser = browser
            self.pages = pages
            self.access = access
            self.space = space
            self.tab = tab
            sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        }
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
