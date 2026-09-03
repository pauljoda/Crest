import Foundation
import XCTest

@testable import Crest

/// The shared row actions, driven through the closure seams both shells bind.
/// The compact shell's own binding is covered by
/// `MobileBrowserSidebarTabActionsTests`.
@MainActor
final class BrowserSidebarTabActionsTests: XCTestCase {
    func testLinkDestinationOpensANewTabInTheChosenSpaceWithoutMovingTheSource() throws {
        let context = makeContext()
        let host = BrowserLinkDestinationHost(browser: context.browser, spaceAccess: context.access)
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id
        )
        let destination = BrowserSpaceRuntimeAssignment(space: context.otherSpace)
        let url = try XCTUnwrap(URL(string: "https://destination.crest.test/article"))

        XCTAssertEqual(host.otherSpaces(from: source).map(\.id), [context.otherSpace.id])
        XCTAssertTrue(host.openLink(url, from: source, in: destination))

        XCTAssertEqual(context.browser.session.spaces.count, 2)
        XCTAssertEqual(context.browser.session.space(id: context.space.id)?.tabs, context.space.tabs)
        let selected = try XCTUnwrap(context.browser.selectedSpace)
        XCTAssertEqual(selected.id, destination.spaceID)
        XCTAssertEqual(selected.profile.id, destination.profileID)
        XCTAssertEqual(context.browser.selectedTab?.url, url)
        XCTAssertNotEqual(context.browser.selectedTab?.id, context.tab.id)
    }

    func testLinkDestinationRejectsAStaleSourceAndLockedDestination() throws {
        let context = makeContext()
        let host = BrowserLinkDestinationHost(browser: context.browser, spaceAccess: context.access)
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id
        )
        let destination = BrowserSpaceRuntimeAssignment(space: context.otherSpace)
        let url = try XCTUnwrap(URL(string: "https://destination.crest.test"))
        context.browser.selectSpace(context.otherSpace.id)
        XCTAssertFalse(host.openLink(url, from: source, in: destination))
        context.browser.selectSpace(context.space.id)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.otherSpace.id)
        XCTAssertTrue(host.otherSpaces(from: source).isEmpty)
        XCTAssertFalse(host.openLink(url, from: source, in: destination))
        context.browser.updateSpaceAccessPolicy(.open, in: context.otherSpace.id)
        context.browser.session.spaces[0] = replacingProfile(in: context.space)
        XCTAssertFalse(host.openLink(url, from: source, in: destination))
        XCTAssertEqual(context.browser.session.space(id: destination.spaceID)?.tabs.count, 0)
    }

    func testNewTabInvokesTheExistingCommandOnceWithoutEditingTheSession() {
        let context = makeContext()
        let action = makeActions(context, pullFavicon: { _, _ in nil })
        let session = context.browser.session
        var invocationCount = 0

        XCTAssertTrue(action.openNewTab { invocationCount += 1 })

        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(context.browser.session, session)
    }

    func testNewTabIsRefusedAfterTheSelectionMoves() {
        let context = makeContext()
        let action = makeActions(context, pullFavicon: { _, _ in nil })
        context.browser.selectSpace(context.otherSpace.id)
        var invocationCount = 0

        XCTAssertFalse(action.openNewTab { invocationCount += 1 })

        XCTAssertEqual(invocationCount, 0)
        XCTAssertEqual(context.browser.selectedSpace?.id, context.otherSpace.id)
    }

    func testNewTabIsRefusedAfterTheProfileIsReplaced() {
        let context = makeContext()
        let action = makeActions(context, pullFavicon: { _, _ in nil })
        context.browser.session.spaces[0] = replacingProfile(in: context.space)
        var invocationCount = 0

        XCTAssertFalse(action.openNewTab { invocationCount += 1 })

        XCTAssertEqual(invocationCount, 0)
    }

    func testNewTabIsRefusedWhenAProtectedSpaceIsLocked() async {
        let context = makeContext(isProtected: true)
        let action = makeActions(context, pullFavicon: { _, _ in nil })
        var invocationCount = 0

        XCTAssertFalse(action.openNewTab { invocationCount += 1 })
        let didUnlock = await context.access.unlock(context.space)
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(action.openNewTab { invocationCount += 1 })
        context.access.lock(context.space.id)
        XCTAssertFalse(action.openNewTab { invocationCount += 1 })

        XCTAssertEqual(invocationCount, 1)
    }

    func testNewTabIsRefusedDuringSidebarReordering() {
        let context = makeContext()
        let action = makeActions(context, pullFavicon: { _, _ in nil })
        context.browser.sidebarReorderState.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: context.tab.id,
                    spaceID: context.space.id,
                    profileID: context.space.profile.id
                )
            ),
            section: .tabs(placement: .saved, folderID: nil),
            at: .zero
        )
        var invocationCount = 0

        XCTAssertFalse(action.openNewTab { invocationCount += 1 })
        context.browser.sidebarReorderState.cancel()
        XCTAssertTrue(action.openNewTab { invocationCount += 1 })

        XCTAssertEqual(invocationCount, 1)
    }

    func testFaviconPullCannotWriteAfterProfileReplacementDuringAwait() async throws {
        let context = makeContext()
        let expectedData = Data("replacement-race".utf8)
        let action = makeActions(context) { _, _ in
            context.browser.session.spaces[0] = self.replacingProfile(
                in: context.space
            )
            return (expectedData, nil)
        }

        let didPullIcon = await action.pullNewIcon(for: context.tab.id)
        XCTAssertFalse(didPullIcon)
        XCTAssertNil(
            try XCTUnwrap(context.browser.session.space(id: context.space.id))
                .tabs.first(where: { $0.id == context.tab.id })?
                .faviconData
        )
    }

    func testFaviconPullCannotWriteAfterProtectedSpaceRelocksDuringAwait() async throws {
        let context = makeContext(isProtected: true)
        let didUnlockSpace = await context.access.unlock(context.space)
        XCTAssertTrue(didUnlockSpace)
        let action = makeActions(context) { _, _ in
            context.access.lock(context.space.id)
            return (Data("relocked".utf8), nil)
        }

        let didPullIcon = await action.pullNewIcon(for: context.tab.id)
        XCTAssertFalse(didPullIcon)
        XCTAssertNil(
            try XCTUnwrap(context.browser.selectedSpace)
                .tabs.first(where: { $0.id == context.tab.id })?
                .faviconData
        )
    }

    func testExactAssignmentAcceptsPulledFavicon() async throws {
        let context = makeContext()
        let expectedData = Data("exact-favicon".utf8)
        let expectedAccent = BrowserTabIconAccent(
            red: 0.2,
            green: 0.4,
            blue: 0.6
        )
        let action = makeActions(context) { _, _ in
            (expectedData, expectedAccent)
        }

        let didPullIcon = await action.pullNewIcon(for: context.tab.id)
        XCTAssertTrue(didPullIcon)
        let tab = try XCTUnwrap(
            context.browser.selectedSpace?.tabs.first(where: {
                $0.id == context.tab.id
            })
        )
        XCTAssertEqual(tab.faviconData, expectedData)
        XCTAssertEqual(tab.iconAccent, expectedAccent)
    }

    /// Clearing archives the Space's current tabs and then, once, tells the page
    /// layer to catch up — the pool it left behind is holding cards for tabs
    /// that no longer exist.
    func testClearingCurrentTabsArchivesThemAndSyncsThePageLayer() throws {
        let context = makeContext()
        var syncCount = 0
        let action = makeActions(
            context,
            syncPagesAfterMutation: { syncCount += 1 },
            pullFavicon: { _, _ in nil }
        )

        XCTAssertTrue(action.clearCurrentTabs())

        let space = try XCTUnwrap(
            context.browser.session.space(id: context.space.id)
        )
        XCTAssertFalse(space.tabs.contains(where: { $0.placement == .current }))
        XCTAssertTrue(space.tabs.contains(where: { $0.id == context.tab.id }))
        XCTAssertEqual(syncCount, 1)
    }

    /// A clear captured before the reader moved on finds nothing to clear, and
    /// leaves the page layer alone rather than reconciling against a Space it
    /// no longer speaks for.
    func testClearingCurrentTabsIsRefusedAfterTheSelectionMoves() throws {
        let context = makeContext()
        var syncCount = 0
        let action = makeActions(
            context,
            syncPagesAfterMutation: { syncCount += 1 },
            pullFavicon: { _, _ in nil }
        )
        context.browser.selectSpace(context.otherSpace.id)

        XCTAssertFalse(action.clearCurrentTabs())

        XCTAssertTrue(
            try XCTUnwrap(context.browser.session.space(id: context.space.id))
                .tabs.contains(where: { $0.placement == .current })
        )
        XCTAssertEqual(syncCount, 0)
    }

    private func makeActions(
        _ context: Context,
        syncPagesAfterMutation: @escaping @MainActor () -> Void = {},
        pullFavicon:
            @escaping @MainActor (
                TabID,
                BrowserSpaceRuntimeAssignment
            ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?
    ) -> BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: context.assignment,
            browser: context.browser,
            spaceAccess: context.access,
            syncPagesAfterMutation: syncPagesAfterMutation,
            pullFavicon: pullFavicon
        )
    }

    private func makeContext(isProtected: Bool = false) -> Context {
        let tab = BrowserTab(
            id: TabID(rawValue: Self.uuid(1)),
            title: "Exact tab",
            url: URL(string: "https://sidebar.crest.test"),
            placement: .saved
        )
        let currentTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(5)),
            title: "Current tab",
            url: URL(string: "https://sidebar.crest.test/current"),
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
            tabs: [tab, currentTab],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open,
            selectedTabID: currentTab.id
        )
        let otherSpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(6)),
            profile: BrowsingProfile(id: Self.uuid(7)),
            name: "Other Space",
            symbol: "square.grid.2x2",
            accent: .rose,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        return Context(
            browser: BrowserStore(
                session: BrowserSession(
                    spaces: [space, otherSpace],
                    selectedSpaceID: space.id
                ),
                persistence: InMemoryBrowserSessionPersistence(),
                browsingMode: .privateBrowsing
            ),
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            space: space,
            otherSpace: otherSpace,
            tab: tab
        )
    }

    private func replacingProfile(in space: BrowserSpace) -> BrowserSpace {
        BrowserSpace(
            id: space.id,
            profile: BrowsingProfile(id: Self.uuid(4)),
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            branding: space.branding,
            folders: space.folders,
            tabs: space.tabs,
            archivedTabs: space.archivedTabs,
            history: space.history,
            browsingPreferences: space.browsingPreferences,
            credentialPreferences: space.credentialPreferences,
            accessPolicy: space.accessPolicy,
            isSavedTabsExpanded: space.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt,
            selectedTabID: space.selectedTabID
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
        let access: BrowserSpaceAccessController
        let space: BrowserSpace
        let otherSpace: BrowserSpace
        let tab: BrowserTab

        var assignment: BrowserSpaceRuntimeAssignment {
            BrowserSpaceRuntimeAssignment(space: space)
        }
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
