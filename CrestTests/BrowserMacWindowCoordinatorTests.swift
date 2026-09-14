import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMacWindowCoordinatorTests: XCTestCase {
    func testTearOffWaitsForDestinationAndMovesTheLivePageWithoutClosingSourceWindow() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.selectedTab)
        let space = try XCTUnwrap(source.browser.selectedSpace)
        source.pages.select(session: source.browser.session)
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
        XCTAssertNil(destination.browser.syncCoordinator)
        XCTAssertFalse(source.browser.session.space(id: space.id)?.tabs.contains { $0.id == tab.id } ?? true)
        XCTAssertNotNil(fixture.coordinator.existingModel(for: source.id))
        XCTAssertTrue(source.browser.selectedSpace?.archivedTabs.isEmpty == true)
    }

    func testCanceledOrStaleTearOffLeavesTheSourceUntouched() throws {
        let fixture = makeFixture()
        let source = try XCTUnwrap(fixture.coordinator.model(for: .initial))
        let tab = try XCTUnwrap(source.browser.selectedTab)
        let space = try XCTUnwrap(source.browser.selectedSpace)
        let item = BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        let request = try XCTUnwrap(fixture.coordinator.prepareTearOff(item, from: source.id))
        fixture.coordinator.cancelPendingTransfer(to: request.id)

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
        first.pages.select(session: first.browser.session)
        second.pages.select(session: second.browser.session)
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

    private func makeFixture() -> (browser: BrowserStore, coordinator: BrowserMacWindowCoordinator) {
        let tab = BrowserTab(title: "Window lifecycle", url: URL(string: "about:blank"), placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Window lifecycle", symbol: "globe",
            accent: .indigo, folders: [], tabs: [tab], selectedTabID: tab.id)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence())
        let pages = BrowserPagePool(monitorsMemoryPressure: false)
        return (
            browser,
            BrowserMacWindowCoordinator(
                browser: browser, pages: pages, spaceAccess: BrowserSpaceAccessController(),
                windowStatePersistence: InMemoryBrowserWindowStatePersistence())
        )
    }
}
