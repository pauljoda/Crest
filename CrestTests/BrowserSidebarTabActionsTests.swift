import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import Crest

/// The shared row actions, driven through the closure seams both shells bind.
/// The compact shell's own binding is covered by
/// `MobileBrowserSidebarTabActionsTests`.
@MainActor
final class BrowserSidebarTabActionsTests: XCTestCase {
    func testPinnedIconChoiceAndRestorePreserveBrowsingState() throws {
        let context = makeContext()
        context.browser.session.spaces[0].tabs[0].placement = .pinned
        let assignment = BrowserTabRuntimeAssignment(
            tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id)
        let action = BrowserTabOrganizationAction(browser: context.browser, spaceAccess: context.access)
        let before = context.browser.session

        XCTAssertTrue(action.canCustomizePinnedIcon(for: assignment))
        XCTAssertEqual(context.browser.session, before, "Opening the editor cannot activate or load the pin")
        XCTAssertTrue(action.setPinnedTabEmoji("👩🏽‍🚀", for: assignment))
        let changed = context.browser.session.spaces[0].tabs[0]
        XCTAssertEqual(changed.emojiIcon, "👩🏽‍🚀")
        XCTAssertEqual(changed.url, before.spaces[0].tabs[0].url)
        XCTAssertEqual(changed.savedURL, before.spaces[0].tabs[0].savedURL)
        XCTAssertEqual(changed.lastActivatedAt, before.spaces[0].tabs[0].lastActivatedAt)
        XCTAssertEqual(context.browser.session.selectedSpaceID, before.selectedSpaceID)
        XCTAssertEqual(context.browser.selectedSpace?.selectedTabID, before.spaces[0].selectedTabID)
        XCTAssertEqual(context.browser.session.spaces[0].tabs[1], before.spaces[0].tabs[1])
        let restored = try JSONDecoder().decode(
            BrowserSession.self, from: JSONEncoder().encode(context.browser.session))
        XCTAssertEqual(restored.spaces[0].tabs[0].emojiIcon, "👩🏽‍🚀")

        XCTAssertTrue(action.clearPinnedTabIcon(for: assignment))
        XCTAssertEqual(context.browser.session.spaces[0].tabs[0].iconMode, .automatic)
        XCTAssertNil(context.browser.session.spaces[0].tabs[0].emojiIcon)
        XCTAssertEqual(context.browser.selectedSpace?.selectedTabID, before.spaces[0].selectedTabID)
    }

    func testPinnedIconActionsRejectInvalidatedTargetsWithoutMutatingEitherSpace() {
        let invalidations: [(Context) -> Void] = [
            { $0.browser.selectSpace($0.otherSpace.id) },
            { $0.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: $0.space.id) },
            { $0.browser.session.spaces[0] = self.replacingProfile(in: $0.browser.session.spaces[0]) },
            { $0.browser.session.spaces[0].tabs.removeFirst() },
            { $0.browser.session.spaces[0].tabs[0].placement = .saved },
            {
                let moved = $0.browser.session.spaces[0].tabs.removeFirst()
                $0.browser.session.spaces[1].tabs.append(moved)
            },
        ]
        for invalidate in invalidations {
            let context = makeContext()
            context.browser.session.spaces[0].tabs[0].placement = .pinned
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

    func testTabLinkUsesLiveTargetURLWithoutChangingSelectionOrSavedRoot() throws {
        let context = makeContext()
        let assignment = BrowserTabRuntimeAssignment(
            tabID: context.tab.id, spaceID: context.space.id, profileID: context.space.profile.id)
        let action = BrowserTabOrganizationAction(browser: context.browser, spaceAccess: context.access)
        let currentURL = try XCTUnwrap(URL(string: "https://sidebar.crest.test/current?q=a%20b#section"))
        context.browser.session.spaces[0].tabs[0].url = currentURL
        let before = context.browser.session

        XCTAssertEqual(action.linkURL(for: assignment), currentURL)
        XCTAssertEqual(context.browser.session, before)
        XCTAssertEqual(context.browser.session.spaces[0].tabs[0].savedURL, context.tab.savedURL)
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
        context.browser.session.spaces[0] = replacingProfile(in: context.space)
        XCTAssertNil(action.linkURL(for: assignment))
        context.browser.session.spaces[0] = context.space
        context.browser.session.spaces[0].tabs.removeAll()
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

extension BrowserSidebarTabActionsTests {
    /// Exercise the native event route: calling closeTab directly cannot detect
    /// a recognizer that fails to close a row or leaves its selection target mounted.
    func testMiddleClickClosesSelectedAndBackgroundTabsThroughNativeInput() async throws {
        let previous = BrowserTab(title: "Previous", url: URL(string: "about:blank#previous"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Middle Click", symbol: "globe",
            accent: .indigo, folders: [], tabs: [previous], selectedTabID: previous.id)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence(), browsingMode: .privateBrowsing)
        let pages = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 1100, height: 720),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: BrowserRootView(
                browser: browser, pages: pages, chrome: BrowserChromeState(),
                transientBrowsing: BrowserTransientBrowsingCoordinator(), startupBehavior: .lastActiveTab,
                initialSidebarWidth: 250, persistSidebarWidth: { _ in }
            ).environment(BrowserWindowTransparencyPreviewFixture.makeStore()))
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
            pages.reconcile(validTabIDs: [])
        }
        try await awaitMiddleClickState {
            pages.activeTabID == previous.id && self.nativeTabRows(in: window).contains { $0.tabID == previous.id }
        }

        for selecting in [true, false] {
            let id = try XCTUnwrap(
                browser.openNewTab(url: URL(string: "about:blank#closing")!, in: space.id, selecting: selecting))
            try await awaitMiddleClickState {
                self.nativeTabRows(in: window).contains { $0.tabID == id && !$0.bounds.isEmpty }
            }
            try postMiddleClick(on: id, in: window)
            try await awaitMiddleClickState {
                browser.selectedSpace?.contains(id) == false
                    && !self.nativeTabRows(in: window).contains { $0.tabID == id }
                    && pages.activeTabID == previous.id
            }

            XCTAssertEqual(browser.selectedTab?.id, previous.id)
            XCTAssertEqual(browser.selectedSpace?.currentTabs.map(\.id), [previous.id])
            XCTAssertEqual(browser.selectedSpace?.archivedTabs.filter { $0.id == id }.count, 1)
            XCTAssertEqual(nativeTabRows(in: window).compactMap(\.tabID), [previous.id])
            XCTAssertFalse(pages.containsResidentPage(for: id))
        }
    }

    private func postMiddleClick(on id: TabID, in window: NSWindow) throws {
        let row = try XCTUnwrap(nativeTabRows(in: window).first { $0.tabID == id })
        let frame = row.convert(row.bounds, to: nil)
        let point = CGPoint(x: frame.minX + frame.width * 0.45, y: frame.midY)
        for type: NSEvent.EventType in [.otherMouseDown, .otherMouseUp] {
            let event = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1,
                    pressure: type == .otherMouseDown ? 1 : 0))
            let cgEvent = try XCTUnwrap(event.cgEvent)
            // NSEvent's factory defaults even otherMouse events to button 0.
            cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            NSApplication.shared.postEvent(try XCTUnwrap(NSEvent(cgEvent: cgEvent)), atStart: false)
        }
    }

    private func nativeTabRows(in window: NSWindow) -> [BrowserNativeTabSelectionTarget.TargetView] {
        func descendants(of view: NSView) -> [BrowserNativeTabSelectionTarget.TargetView] {
            if let target = view as? BrowserNativeTabSelectionTarget.TargetView { return [target] }
            return view.subviews.flatMap { descendants(of: $0) }
        }
        return window.contentView.map { descendants(of: $0) } ?? []
    }

    private func awaitMiddleClickState(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Native tab state did not settle", file: file, line: line)
    }
}

extension BrowserSidebarTabActionsTests {
    func testRetainedSidebarRootObservesClosedTabWithoutReplacement() async throws {
        let previous = BrowserTab(title: "Search", url: URL(string: "about:blank#search"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Retention", symbol: "globe", accent: .indigo,
            folders: [], tabs: [previous], selectedTabID: previous.id)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence(), browsingMode: .privateBrowsing)
        let closing = try XCTUnwrap(browser.openNewTab(url: URL(string: "about:blank#closing")!))
        let pages = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        pages.select(session: browser.session)
        // Keep the native root intact across closing, just as a cached pager host can.
        // Residency updates alone must not leave a closed tab in the sidebar snapshot.
        let root = RetainedSidebarContent(space: browser.selectedSpace!, browser: browser, pages: pages)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 250, height: 720), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
            pages.reconcile(validTabIDs: [])
        }
        try await awaitMiddleClickState { self.nativeTabRows(in: window).contains { $0.tabID == closing } }
        try postMiddleClick(on: closing, in: window)
        try await awaitMiddleClickState { browser.selectedSpace?.contains(closing) == false }
        pages.reconcile(session: browser.session)
        pages.select(session: browser.session)
        try await awaitMiddleClickState { !self.nativeTabRows(in: window).contains { $0.tabID == closing } }
        XCTAssertEqual(browser.selectedTab?.id, previous.id)
        XCTAssertFalse(pages.containsResidentPage(for: closing))
        XCTAssertFalse(nativeTabRows(in: window).contains { $0.tabID == closing })
        XCTAssertEqual(pages.activeTabID, previous.id)
        // The retained root must also stop exposing a Space whose profile changed.
        browser.session.spaces[0] = replacingProfile(in: space)
        try await awaitMiddleClickState { self.nativeTabRows(in: window).isEmpty }
    }
}

private struct RetainedSidebarContent: View {
    let space: BrowserSpace
    let browser: BrowserStore
    let pages: BrowserPagePool
    private let access = BrowserSpaceAccessController()
    private let utility = BrowserUtilityPresentationState()
    @Namespace private var commands
    @Namespace private var promotion

    var body: some View {
        let context = BrowserSidebarContext(
            browser: browser,
            pageAccess: BrowserSidebarPageAccess(pages: pages, browser: browser, spaceAccess: access),
            spaceAccess: access, capabilities: BrowserInteractionCapabilities(), availableSpaces: [space],
            utilityPresentation: utility,
            utilityActions: BrowserSidebarUtilityCoordinator(browser: browser, pages: pages, spaceAccess: access)
                .actions,
            utilitySearchText: .constant(""), utilityFilter: .constant(.all),
            chromeActions: BrowserSidebarChromeActions(presentSpaceSettings: { _ in }, presentHistory: {}),
            selectSpace: { _ in }, confirmClearHistory: { _ in }, dismissUtilityOnBlankSpace: {},
            toggleUtilitySwitcher: {})
        BrowserSidebarSpacePage(
            space: space, isSelected: true, context: context, pages: pages, openNewTab: {},
            commandSurfaceNamespace: commands, tabPromotionNamespace: promotion)
    }
}
