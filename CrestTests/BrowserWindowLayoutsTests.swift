import Foundation
import XCTest

@testable import Crest

/// A window outlives the process twice over: the core keeps what it shows in
/// its own file, and the platform keeps its sidebar layout in defaults, for the
/// sixteen windows used last.
@MainActor
final class BrowserWindowLayoutsTests: XCTestCase {
    func testASavedWindowReopensOnWhatItShowedEvenWhenTheDefaultSpaceDiffers() async throws {
        var session = BrowserSession.preview
        session.defaultSpaceID = session.spaces[0].id
        let harness = try BrowserStoredSessionHarness(session: session)
        let space = try XCTUnwrap(harness.store.session.spaces.last)
        let tab = try XCTUnwrap(space.tabs.last)
        let id = BrowserWindowID()
        let window = harness.store.makeWindowStore(BrowserWindowOpening(id: id, saved: true))
        XCTAssertTrue(window.activateSessionTab(tab.id, in: space.id))

        let relaunched = try await harness.relaunch()
        let reopened = relaunched.store.makeWindowStore(BrowserWindowOpening(id: id, saved: true))
        XCTAssertEqual(reopened.selectedSpaceID, space.id)
        XCTAssertEqual(reopened.selectedTab?.id, tab.id)
        // A window without a record still opens on the launch Space.
        XCTAssertEqual(relaunched.store.selectedSpaceID, session.spaces[0].id)
    }

    func testLayoutsSurviveARelaunchAndKeepTheSixteenWindowsUsedLast() throws {
        let suiteName = "crest.window-layouts-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let layouts = BrowserWindowLayouts(defaults: defaults)
        let ids = (0...BrowserWindowLayouts.maximumCount).map { _ in BrowserWindowID() }
        for (index, id) in ids.dropLast().enumerated() {
            layouts.save(BrowserWindowState(id: id, sidebarWidth: Double(200 + index), sidebarIsPresented: true))
        }
        // Using the oldest window again keeps it; the next oldest goes instead.
        layouts.save(BrowserWindowState(id: ids[0], sidebarWidth: 321, sidebarIsPresented: false))
        layouts.save(BrowserWindowState(id: ids[BrowserWindowLayouts.maximumCount], sidebarWidth: 280))

        let relaunched = BrowserWindowLayouts(defaults: defaults)
        XCTAssertEqual(relaunched.layout(for: ids[0])?.sidebarWidth, 321)
        XCTAssertEqual(relaunched.layout(for: ids[0])?.sidebarIsPresented, false)
        XCTAssertNil(relaunched.layout(for: ids[1]))
        XCTAssertEqual(relaunched.layout(for: ids[2])?.sidebarWidth, 202)
        XCTAssertEqual(relaunched.layout(for: ids[BrowserWindowLayouts.maximumCount])?.sidebarWidth, 280)
    }
}
