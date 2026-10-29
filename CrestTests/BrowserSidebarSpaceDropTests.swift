import CoreGraphics
import XCTest

@testable import Crest

/// A tab released on a Space chip of the picker moves it there, and a locked
/// Space refuses it with a reason the person is shown.
@MainActor
final class BrowserSidebarSpaceDropTests: XCTestCase {
    // MARK: - Types

    @MainActor
    private struct Fixture {
        let store: BrowserStore
        let access: BrowserSpaceAccessController
        let source: SpaceModel
        let destination: SpaceModel
        let tabID: UUID

        /// Lifts the tab from its row and releases it on the destination's
        /// chip: the drop the state ends with, or nil where it refuses.
        func release() throws -> BrowserSidebarReorderDrop? {
            try hover().state.end()
        }

        /// Lifts the tab and holds it over the destination's chip.
        func hover() throws -> BrowserSidebarReorderContext {
            let item = BrowserSidebarReorderItem.tab(
                BrowserTabDragItem(tabID: tabID, spaceID: source.id, profileID: source.profileID))
            let context = BrowserSidebarReorderContext(
                browser: store, spaceAccess: access, state: BrowserSidebarReorderState())
            let chip = CGRect(x: 100, y: 60, width: 44, height: 44)
            context.state.register(
                zone: BrowserSidebarReorderZone(
                    target: .space(BrowserSpaceRuntimeAssignment(space: destination)), frame: chip),
                for: UUID())
            let plan = try XCTUnwrap(context.plan(for: item))
            context.state.stage(item: item, section: .tabs(placement: .current, folderID: nil), plan: plan)
            context.state.update(pointer: CGPoint(x: chip.midX, y: chip.midY))
            return context
        }

        func commit(_ drop: BrowserSidebarReorderDrop) {
            BrowserSidebarReorderContext(browser: store, spaceAccess: access, state: BrowserSidebarReorderState())
                .commit(drop)
        }

        var destinationHoldsTab: Bool {
            store.spaceModel(destination.id)?.tabs.model(tabID) != nil
        }
    }

    // MARK: - Variables

    // MARK: - Actions - Fixture

    /// The preview session's first Space with a current tab to lift, and its
    /// second, locked when `locksDestination`.
    private func fixture(locksDestination: Bool) throws -> Fixture {
        var session = SessionState.Seed.preview
        if locksDestination { session.spaces[1].settings.accessPolicy = .deviceOwnerAuthentication }
        let store = BrowserStore(seed: session)
        let access = BrowserSpaceAccessController()
        store.attachSpaceAccess(access)
        let source = try XCTUnwrap(store.spaceModels.first)
        return Fixture(
            store: store, access: access, source: source, destination: try XCTUnwrap(store.spaceModels.last),
            tabID: try XCTUnwrap(source.currentTabs.first?.id))
    }

    // MARK: - Tests

    func testReleasingOnASpaceChipMovesTheTab() throws {
        let fixture = try fixture(locksDestination: false)

        let drop = try XCTUnwrap(fixture.release())

        guard case .space(let landed) = drop.target.kind else { return XCTFail("The chip did not take the lift") }
        XCTAssertEqual(landed.spaceID, fixture.destination.id)
        fixture.commit(drop)
        XCTAssertTrue(fixture.destinationHoldsTab)
    }

    func testALockedSpaceRefusesTheDropAndSaysWhy() throws {
        let fixture = try fixture(locksDestination: true)

        let hovered = try fixture.hover()
        XCTAssertEqual(
            hovered.state.constraintMessage,
            String(localized: "The Space is locked or no longer active. Unlock it and select the tabs again."))
        XCTAssertNil(hovered.state.end(), "A locked Space refuses the drop.")
        XCTAssertFalse(fixture.destinationHoldsTab)
    }
}
