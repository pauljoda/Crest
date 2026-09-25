import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMacWindowCoordinatorTests: XCTestCase {
    func testQuickWindowPromotionReusesAHiddenWindowAndRevealsThePromotedTab() throws {
        let fixture = makeFixture()
        let destination = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let window = makeNativeWindow()
        defer {
            fixture.coordinator.closeWindow(destination.id)
            window.close()
        }
        XCTAssertTrue(fixture.coordinator.attach(window, to: destination.id))
        let previousTabID = destination.browser.selectedTab?.id
        let promotedTabID = try XCTUnwrap(fixture.browser.openNewTab(url: URL(string: "about:blank")!))
        XCTAssertEqual(destination.browser.selectedTab?.id, previousTabID)
        XCTAssertFalse(window.isVisible)

        XCTAssertTrue(fixture.coordinator.activateExistingWindow(for: fixture.browser))

        XCTAssertEqual(destination.browser.selectedTab?.id, promotedTabID)
        XCTAssertTrue(window.isVisible)
        XCTAssertNotNil(destination.pages.activePage)
    }

    func testQuickWindowPromotionPrefersItsOwningWindowAndFallsBackAfterItCloses() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let other = try XCTUnwrap(fixture.coordinator.model(for: .normal(sourceWindowID: source.id)))
        let sourceWindow = makeNativeWindow()
        let otherWindow = makeNativeWindow()
        defer {
            fixture.coordinator.closeWindow(source.id)
            fixture.coordinator.closeWindow(other.id)
            sourceWindow.close()
            otherWindow.close()
        }
        XCTAssertTrue(fixture.coordinator.attach(sourceWindow, to: source.id))
        XCTAssertTrue(fixture.coordinator.attach(otherWindow, to: other.id))
        let otherTabID = other.browser.selectedTab?.id
        let promotedTabID = try XCTUnwrap(source.browser.openNewTab(url: URL(string: "about:blank")!))

        XCTAssertTrue(fixture.coordinator.activateExistingWindow(for: source.browser))
        XCTAssertEqual(other.browser.selectedTab?.id, otherTabID)
        XCTAssertTrue(sourceWindow.isVisible)
        XCTAssertFalse(otherWindow.isVisible)

        fixture.coordinator.closeWindow(source.id)
        sourceWindow.close()
        XCTAssertTrue(fixture.coordinator.activateExistingWindow(for: source.browser))
        XCTAssertEqual(other.browser.selectedTab?.id, promotedTabID)
        XCTAssertTrue(otherWindow.isVisible)

        fixture.coordinator.closeWindow(other.id)
        otherWindow.close()
        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: source.browser))
    }

    func testQuickWindowPromotionDoesNotUseATemporaryWindowForTheSharedWorkspace() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: source.browser))
        let space = try XCTUnwrap(source.browser.selectedSpace)
        let temporary = try XCTUnwrap(
            fixture.coordinator.model(
                for: .temporary(
                    sourceWindowID: source.id, assignment: BrowserSpaceRuntimeAssignment(space: space))))
        let window = makeNativeWindow()
        defer {
            fixture.coordinator.closeWindow(temporary.id)
            fixture.coordinator.closeWindow(source.id)
            window.close()
        }
        XCTAssertTrue(fixture.coordinator.attach(window, to: temporary.id))

        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: source.browser))
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(fixture.coordinator.activateExistingWindow(for: temporary.browser))
        XCTAssertFalse(window.isVisible)

        let primaryPages = BrowserPagePool(browser: fixture.browser.makeWindowStore(), monitorsMemoryPressure: false)
        let registry = BrowserPagePoolRegistry(primary: primaryPages)
        registry.register(temporary.pages, browser: temporary.browser, for: temporary.id)
        let context = try XCTUnwrap(
            BrowserQuickWindowContextResolver(
                browser: fixture.browser, pages: primaryPages, pagePoolRegistry: registry
            ).context(targetWindowID: temporary.id))
        XCTAssertTrue(context.browser === fixture.browser)
        XCTAssertTrue(context.pages === primaryPages)
        XCTAssertFalse(context.supportsLivePagePromotion)
    }

    func testTearOffWaitsForDestinationAndMovesTheLivePageWithoutClosingSourceWindow() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.selectedTab)
        let space = try XCTUnwrap(source.browser.selectedSpace)
        source.pages.select(session: source.browser.presented)
        let page = try XCTUnwrap(source.pages.activePage)
        let request = try XCTUnwrap(
            fixture.coordinator.prepareTearOff(
                BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profile.id),
                from: source.id))

        XCTAssertNotNil(source.browser.session.space(id: space.id)?.tabs.first { $0.id == tab.id })
        let destination = try XCTUnwrap(fixture.coordinator.model(for: request))
        XCTAssertTrue(destination.browser.session.spaces.allSatisfy { $0.tabs.isEmpty })

        XCTAssertTrue(fixture.coordinator.completePendingTransfer(to: destination.id))

        XCTAssertTrue(destination.pages.activePage === page)
        XCTAssertEqual(destination.browser.selectedTab?.id, tab.id)
        XCTAssertTrue(destination.browser.isTemporaryWorkspace)
        XCTAssertFalse(destination.browser.syncsSession)
        XCTAssertFalse(source.browser.session.space(id: space.id)?.tabs.contains { $0.id == tab.id } ?? true)
        XCTAssertNotNil(fixture.coordinator.existingModel(for: source.id))
        XCTAssertTrue(source.browser.selectedSpace?.archivedTabs.isEmpty == true)

        // Closing the window closes its workspace, and a scene that asks for
        // the window again while SwiftUI tears it down opens nothing.
        let workspace = destination.browser.family
        fixture.coordinator.closeWindow(destination.id)
        XCTAssertFalse(workspace.isOpen)
        XCTAssertNil(fixture.coordinator.model(for: request))
    }

    func testCanceledOrStaleTearOffLeavesTheSourceUntouched() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.selectedTab)
        let space = try XCTUnwrap(source.browser.selectedSpace)
        let item = BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        let request = try XCTUnwrap(fixture.coordinator.prepareTearOff(item, from: source.id))
        let canceled = try XCTUnwrap(fixture.coordinator.existingModel(for: request.id)).browser.family
        fixture.coordinator.cancelPendingTransfer(to: request.id)

        // The canceled window's workspace closes with it.
        XCTAssertFalse(canceled.isOpen)
        XCTAssertNil(fixture.browser.core.state.workspaces[canceled.workspaceID])
        XCTAssertFalse(fixture.coordinator.completePendingTransfer(to: request.id))
        XCTAssertEqual(source.browser.selectedTab?.id, tab.id)
        XCTAssertNil(fixture.coordinator.existingModel(for: request.id))
        XCTAssertNil(fixture.coordinator.model(for: request), "A late scene must not recreate a canceled transfer.")

        let stale = try XCTUnwrap(fixture.coordinator.prepareTearOff(item, from: source.id))
        source.browser.closeTab(tab.id)
        XCTAssertFalse(fixture.coordinator.completePendingTransfer(to: stale.id))
        XCTAssertNil(fixture.coordinator.existingModel(for: stale.id))
    }

    func testClosingOneNormalWindowKeepsTheOtherWindowAndSharedTabs() throws {
        let fixture = makeFixture()
        let first = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let second = try XCTUnwrap(
            fixture.coordinator.model(for: .normal(sourceWindowID: first.id)))
        let tabID = try XCTUnwrap(first.browser.selectedTab?.id)
        first.pages.select(session: first.browser.presented)
        second.pages.select(session: second.browser.presented)
        let page = try XCTUnwrap(second.pages.activePage)

        fixture.coordinator.closeWindow(first.id)

        XCTAssertEqual(second.browser.selectedTab?.id, tabID)
        XCTAssertTrue(second.pages.activePage === page)
        XCTAssertNotNil(fixture.coordinator.existingModel(for: second.id))
        XCTAssertTrue(fixture.browser.session.spaces.contains { $0.tabs.contains { $0.id == tabID } })
    }

    func testCancelingAPreparedNativeTearOffClosesItsShellAndRejectsLateAttachment() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.selectedTab)
        let space = try XCTUnwrap(source.browser.selectedSpace)
        let request = try XCTUnwrap(
            fixture.coordinator.prepareTearOff(
                BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profile.id),
                from: source.id, at: CGPoint(x: 500, y: 500)))
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        fixture.coordinator.preparePresentation(window, for: request.id)
        window.orderFront(nil)

        fixture.coordinator.cancelPendingTransfer(to: request.id)

        XCTAssertFalse(window.isVisible)
        XCTAssertNil(fixture.coordinator.existingModel(for: request.id))
        XCTAssertFalse(fixture.coordinator.attach(window, to: request.id))
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(source.browser.selectedTab?.id, tab.id)
    }

    func testACommittedTearOffRemainsAvailableWhenItsRowCannotBeMeasured() async throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.selectedTab)
        let space = try XCTUnwrap(source.browser.selectedSpace)
        let request = try XCTUnwrap(
            fixture.coordinator.prepareTearOff(
                BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profile.id),
                from: source.id, at: CGPoint(x: 500, y: 500)))
        let destination = try XCTUnwrap(fixture.coordinator.existingModel(for: request.id))
        let placement = try XCTUnwrap(destination.tearOffPlacement)
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            fixture.coordinator.closeWindow(destination.id)
            fixture.coordinator.closeWindow(source.id)
            window.close()
        }
        fixture.coordinator.preparePresentation(window, for: request.id)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(fixture.coordinator.attach(window, to: request.id))
        XCTAssertEqual(destination.browser.selectedTab?.id, tab.id)

        for _ in 0..<80 where placement.isPending {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertFalse(placement.isPending)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(destination.browser.selectedTab?.id, tab.id)
        XCTAssertTrue(source.browser.selectedSpace?.tabs.isEmpty == true)
    }

    /// SwiftUI builds a restored window before it hands back the request the
    /// window was saved with. The window still comes back under its own
    /// identity, on what it showed, and never on the initial window's model.
    func testARestoredWindowReopensItsOwnRecordAndNotTheInitialWindow() async throws {
        var session = BrowserSession.preview
        session.defaultSpaceID = session.spaces[0].id
        let harness = try BrowserStoredSessionHarness(session: session)
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let launched = makeCoordinator(over: harness.store)
        let main = try XCTUnwrap(launched.model(for: .initial))
        let second = try XCTUnwrap(launched.model(for: .normal(sourceWindowID: main.id)))
        let space = try XCTUnwrap(harness.store.session.spaces.last)
        let tab = try XCTUnwrap(space.tabs.last)
        XCTAssertTrue(second.browser.activateSessionTab(tab.id, in: space.id))

        let relaunched = try await harness.relaunch()
        relaunched.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let coordinator = makeCoordinator(over: relaunched.store)
        let center = NotificationCenter()
        let restoration = BrowserMacWindowRestoration(center: center)
        let restoredScene = SceneRequest()
        let initialScene = SceneRequest()
        let restoring = Task { await restoration.window(presentedBy: { restoredScene.value }, in: coordinator) }
        let opening = Task { await restoration.window(presentedBy: { initialScene.value }, in: coordinator) }
        await Task.yield()
        restoredScene.value = BrowserMacWindowRequest(id: second.id, kind: .normal, sourceWindowID: main.id)
        center.post(name: NSApplication.didFinishRestoringWindowsNotification, object: nil)
        let restoredRequest = await restoring.value
        let initialRequest = await opening.value
        let restored = try XCTUnwrap(coordinator.model(for: XCTUnwrap(restoredRequest)))
        let initial = try XCTUnwrap(coordinator.model(for: XCTUnwrap(initialRequest)))

        XCTAssertEqual(restored.id, second.id)
        XCTAssertEqual(initial.id, BrowserMacWindowRequest.initial.id)
        XCTAssertEqual(restored.browser.selectedSpaceID, space.id)
        XCTAssertEqual(restored.browser.selectedTab?.id, tab.id)
        XCTAssertEqual(initial.browser.selectedSpaceID, session.spaces[0].id)
        // A scene opened without a request while the initial window is open
        // presents a window of its own.
        let anotherRequest = await restoration.window(presentedBy: { nil }, in: coordinator)
        let another = try XCTUnwrap(anotherRequest)
        XCTAssertFalse([BrowserMacWindowRequest.initial.id, second.id].contains(another.id))
        XCTAssertFalse(coordinator.model(for: another) === initial)
    }

    /// SwiftUI saves a window's request with the window. A request an earlier
    /// build saved restores here, a bare identity reads too, and this build
    /// saves the spelling an earlier build restores.
    func testAWindowRequestKeepsTheStoredIdentitySpellingAndReadsABareOne() throws {
        let spaceID = SpaceID()
        let request = BrowserMacWindowRequest.temporary(
            sourceWindowID: BrowserMacWindowRequest.initial.id,
            assignment: BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: UUID()))

        let stored = try XCTUnwrap(StoredIdentityJSON.document(of: request) as? [String: Any])
        XCTAssertEqual(stored["id"] as? [String: String], StoredIdentityJSON.wrapped(request.id))
        XCTAssertEqual(
            stored["sourceWindowID"] as? [String: String],
            StoredIdentityJSON.wrapped(BrowserMacWindowRequest.initial.id))
        let assignment = try XCTUnwrap(stored["sourceAssignment"] as? [String: Any])
        XCTAssertEqual(assignment["spaceID"] as? [String: String], StoredIdentityJSON.wrapped(spaceID))
        XCTAssertEqual(try StoredIdentityJSON.decode(BrowserMacWindowRequest.self, from: stored), request)
        XCTAssertEqual(
            try StoredIdentityJSON.decode(BrowserMacWindowRequest.self, from: StoredIdentityJSON.bare(stored)),
            request)
    }

    /// A lifted row's payload comes back as the same row; the selection the
    /// lift captured stays with the lift and never enters the payload.
    func testDragItemsSurviveTheirTransferEncoding() throws {
        let browser = BrowserStore(session: .preview)
        let space = try XCTUnwrap(browser.selectedSpace)
        let tabs = space.tabs.filter { !$0.isStartPage }.prefix(2).map(\.id)
        let selection = try XCTUnwrap(browser.capturedSelection(ids: tabs))
        var tab = BrowserTabDragItem(
            tabID: tabs[0], spaceID: space.id, profileID: space.profile.id, selection: selection)
        var folder = BrowserFolderDragItem(
            folderID: FolderID(), spaceID: space.id, profileID: space.profile.id, memberTabIDs: tabs,
            selection: selection)
        var split = BrowserSplitGroupDragItem(
            groupID: SplitGroupID(), spaceID: space.id, profileID: space.profile.id, memberTabIDs: tabs,
            selection: selection)
        let decodedTab = try JSONDecoder().decode(BrowserTabDragItem.self, from: JSONEncoder().encode(tab))
        let decodedFolder = try JSONDecoder().decode(BrowserFolderDragItem.self, from: JSONEncoder().encode(folder))
        let decodedSplit = try JSONDecoder().decode(BrowserSplitGroupDragItem.self, from: JSONEncoder().encode(split))
        (tab.selection, folder.selection, split.selection) = (nil, nil, nil)

        XCTAssertEqual(decodedTab, tab)
        XCTAssertEqual(decodedFolder, folder)
        XCTAssertEqual(decodedSplit, split)
    }

    private func makeNativeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func makeCoordinator(over browser: BrowserStore) -> BrowserMacWindowCoordinator {
        BrowserMacWindowCoordinator(
            browser: browser, pages: BrowserPagePool(browser: browser, monitorsMemoryPressure: false),
            spaceAccess: BrowserSpaceAccessController(), windowLayouts: BrowserWindowLayouts(defaults: nil))
    }

    private func makeFixture() -> (browser: BrowserStore, coordinator: BrowserMacWindowCoordinator) {
        let tab = BrowserTab(title: "Window lifecycle", url: URL(string: "about:blank"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Window lifecycle", symbol: "globe",
            accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore.hostingPages(
            BrowserSession(spaces: [space]),
            showing: space.id, tabs: [space.id: tab.id])
        let pages = BrowserPagePool(browser: browser, monitorsMemoryPressure: false)
        return (
            browser,
            BrowserMacWindowCoordinator(
                browser: browser, pages: pages, spaceAccess: BrowserSpaceAccessController(),
                windowLayouts: BrowserWindowLayouts(defaults: nil))
        )
    }
}

/// The request SwiftUI has handed back to a scene so far.
@MainActor
private final class SceneRequest {
    var value: BrowserMacWindowRequest?
}
