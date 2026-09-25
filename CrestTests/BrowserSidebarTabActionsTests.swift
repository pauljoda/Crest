import Foundation
import XCTest

@testable import Crest

/// The shared row actions, driven through the closure seams both shells bind.
/// The compact shell's own binding is covered by
/// `MobileBrowserSidebarTabActionsTests`.
@MainActor
final class BrowserSidebarTabActionsTests: XCTestCase {
    func testPinnedIconActionsRejectInvalidatedTargetsWithoutMutatingEitherSpace() {
        let invalidations: [(Context) -> Void] = [
            { $0.browser.selectSpace($0.otherSpace.id) },
            { $0.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: $0.space.id) },
            { $0.browser.replaceProfileForTesting(of: $0.space.id, with: Self.uuid(4)) },
            { $0.browser.deleteTab($0.tab.id, in: $0.space.id) },
            { $0.browser.moveTab($0.tab.id, to: .saved) },
            { $0.browser.moveTab($0.tab.id, from: $0.space.id, into: $0.otherSpace.id) },
        ]
        for invalidate in invalidations {
            let context = makeContext(placement: .pinned)
            let assignment = BrowserTabRuntimeAssignment(
                tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id)
            let action = BrowserTabOrganizationAction(browser: context.browser, spaceAccess: context.access)
            XCTAssertTrue(action.setPinnedTabEmoji("🌙", for: assignment))
            invalidate(context)
            let before = context.browser.session

            XCTAssertFalse(action.canCustomizePinnedIcon(for: assignment))
            XCTAssertFalse(action.setPinnedTabEmoji("⭐️", for: assignment))
            XCTAssertFalse(action.clearPinnedTabIcon(for: assignment))
            XCTAssertEqual(context.browser.session, before)
        }
    }

    func testTabLinkRejectsStaleSpaceProfileMissingAndLockedTargets() {
        let context = makeContext()
        let assignment = BrowserTabRuntimeAssignment(
            tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id)
        let action = BrowserTabOrganizationAction(browser: context.browser, spaceAccess: context.access)
        XCTAssertNotNil(action.linkURL(for: assignment))
        context.browser.selectSpace(context.otherSpace.id)
        XCTAssertNil(action.linkURL(for: assignment))
        context.browser.selectSpace(context.space.id)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.space.id)
        XCTAssertNil(action.linkURL(for: assignment))
        context.browser.updateSpaceAccessPolicy(.open, in: context.space.id)
        context.browser.replaceProfileForTesting(of: context.space.id, with: Self.uuid(4))
        XCTAssertNil(action.linkURL(for: assignment))
        context.browser.replaceProfileForTesting(of: context.space.id, with: context.space.profile.id)
        for tab in context.space.tabs { context.browser.deleteTab(tab.id, in: context.space.id) }
        XCTAssertNil(action.linkURL(for: assignment))
    }

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
        context.browser.replaceProfileForTesting(of: context.space.id, with: Self.uuid(4))
        let destinationTabs = context.browser.session.space(id: destination.spaceID)?.tabs
        XCTAssertFalse(host.openLink(url, from: source, in: destination))
        XCTAssertEqual(context.browser.session.space(id: destination.spaceID)?.tabs, destinationTabs)
    }

    func testSelectionSearchRejectsEmptyOrInvalidatedSources() throws {
        let invalidations: [(Context) -> Void] = [
            { $0.browser.selectSpace($0.otherSpace.id) },
            { $0.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: $0.space.id) },
            { $0.browser.replaceProfileForTesting(of: $0.space.id, with: Self.uuid(4)) },
            { context in
                for tab in context.space.tabs { context.browser.deleteTab(tab.id, in: context.space.id) }
            },
        ]
        for invalidate in invalidations {
            let context = makeContext()
            let host = BrowserLinkDestinationHost(browser: context.browser, spaceAccess: context.access)
            let source = BrowserTabRuntimeAssignment(
                tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id
            )
            XCTAssertNil(host.selectionSearch(for: " \n ", from: source))
            let search = try XCTUnwrap(host.selectionSearch(for: "selected words", from: source))
            invalidate(context)
            let before = context.browser.session

            XCTAssertNil(host.selectionSearch(for: "selected words", from: source))
            XCTAssertFalse(
                host.openLink(search.url, from: search.source, in: BrowserSpaceRuntimeAssignment(space: context.space)))
            XCTAssertEqual(context.browser.session, before)
        }
    }

    func testNewTabIsRefusedAfterTheProfileIsReplaced() {
        let context = makeContext()
        let action = makeActions(context, pullFavicon: { _, _ in nil })
        context.browser.replaceProfileForTesting(of: context.space.id, with: Self.uuid(4))
        var invocationCount = 0

        XCTAssertFalse(action.openNewTab { invocationCount += 1 })

        XCTAssertEqual(invocationCount, 0)
    }

    func testFaviconPullCannotWriteAfterProfileReplacementDuringAwait() async throws {
        let context = makeContext()
        let expectedData = Data("replacement-race".utf8)
        let action = makeActions(context) { _, _ in
            context.browser.replaceProfileForTesting(of: context.space.id, with: Self.uuid(4))
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
            reorderState: context.sidebarInteraction.sidebarReorderState,
            spaceAccess: context.access,
            syncPagesAfterMutation: syncPagesAfterMutation,
            pullFavicon: pullFavicon
        )
    }

    private func makeContext(isProtected: Bool = false, placement: TabPlacement = .saved) -> Context {
        let tab = BrowserTab(
            id: Self.uuid(1),
            title: "Exact tab",
            url: URL(string: "https://sidebar.crest.test"),
            placement: placement
        )
        let currentTab = BrowserTab(
            id: Self.uuid(5),
            title: "Current tab",
            url: URL(string: "https://sidebar.crest.test/current"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let space = BrowserSpace(
            id: Self.uuid(2),
            profile: BrowsingProfile(id: Self.uuid(3)),
            name: "Exact Space",
            symbol: "sidebar.left",
            accent: .indigo,
            folders: [],
            tabs: [tab, currentTab],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open
        )
        let otherSpace = BrowserSpace(
            id: Self.uuid(6),
            profile: BrowsingProfile(id: Self.uuid(7)),
            name: "Other Space",
            symbol: "square.grid.2x2",
            accent: .rose,
            folders: [],
            tabs: []
        )
        let browser = BrowserStore(session: BrowserSession(spaces: [space, otherSpace]))
        let access = BrowserSpaceAccessController(authenticator: AcceptingAuthenticator())
        browser.attachSpaceAccess(access)
        return Context(
            browser: browser,
            access: access,
            space: space,
            otherSpace: otherSpace,
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
        let access: BrowserSpaceAccessController
        let space: BrowserSpace
        let otherSpace: BrowserSpace
        let tab: BrowserTab

        init(
            browser: BrowserStore, access: BrowserSpaceAccessController, space: BrowserSpace, otherSpace: BrowserSpace,
            tab: BrowserTab
        ) {
            self.browser = browser
            self.access = access
            self.space = space
            self.otherSpace = otherSpace
            self.tab = tab
            sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        }

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
