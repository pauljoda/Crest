import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarExactAssignmentTests: XCTestCase {
    func testCapturedTabCloseRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.closeTab(
                context.sourceTab.id,
                matching: assignment
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(context.store.spaceModel(context.source.id))
                .tabs.contains(context.sourceTab.id)
        )
    }

    func testVirtualRowRunReorderPreservesScrollOriginLiftPreviewAndGapMovement() throws {
        let state = BrowserSidebarReorderState()
        let space = BrowserSpaceRuntimeAssignment(spaceID: fixedUUID(10), profileID: fixedUUID(11))
        let regionID = UUID()
        let runID = UUID()
        let section = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)
        let tabIDs = (0..<60).map { _ in UUID() }
        let itemIDs = tabIDs.map(BrowserSidebarReorderItemID.tab)
        let indexByID = Dictionary(uniqueKeysWithValues: itemIDs.enumerated().map { ($1, $0) })
        let rowStride: CGFloat = 36

        // Register viewport and scrolled content origin (scrolled down 1080pt = 30 rows).
        let viewport = CGRect(x: 0, y: 100, width: 240, height: 600)
        state.register(scrollRegionFrame: viewport, for: regionID)
        state.register(scrollContentOrigin: CGPoint(x: 0, y: viewport.minY - 1080), for: regionID)
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(section),
                frame: CGRect(x: 0, y: 0, width: 240, height: CGFloat(tabIDs.count) * rowStride),
                minimumHeight: 36,
                supportsTouch: false
            ),
            for: UUID(),
            scrollRegionID: regionID,
            isContentRelative: true
        )
        let run = BrowserSidebarReorderGeometry.VirtualRowRun(
            id: runID,
            space: space,
            section: section,
            scrollRegionID: regionID,
            frame: CGRect(x: 0, y: 0, width: 240, height: CGFloat(tabIDs.count) * rowStride),
            rowStride: rowStride,
            itemIDs: itemIDs,
            itemIndexByID: indexByID,
            visibleIndices: 28..<50,
            auxiliaryClick: nil
        )
        state.register(virtualRun: run)

        // Row 35 sits at content y = 1260, so global y = 100 - 1080 + 1260 = 280.
        let pickedFrame = try XCTUnwrap(state.frame(ofRow: .tab(tabIDs[35]), in: space))
        XCTAssertEqual(pickedFrame.minY, 280, accuracy: 0.5)

        let pickedItem = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(tabID: tabIDs[35], spaceID: space.spaceID, profileID: space.profileID)
        )
        let startPointer = CGPoint(x: 120, y: pickedFrame.midY)
        state.begin(item: pickedItem, section: section, at: startPointer)

        // Floating lift preview must stay right under the pointer (not shifted by scroll).
        let preview = try XCTUnwrap(state.liftPreview)
        XCTAssertEqual(preview.grabOffset.height, rowStride / 2, accuracy: 1.0)
        XCTAssertEqual(preview.rowWidth, 240, accuracy: 0.5)

        // Updating the virtual run frame mid-drag (e.g. projected height change) must be held, not corrupt geometry.
        var shrunkenRun = run
        shrunkenRun.frame = CGRect(x: 0, y: 0, width: 240, height: CGFloat(tabIDs.count - 1) * rowStride)
        state.register(virtualRun: shrunkenRun)
        XCTAssertEqual(try XCTUnwrap(state.frame(ofRow: .tab(tabIDs[35]), in: space)).minY, 280, accuracy: 0.5)

        // Moving the pointer to the top edge of row 33 opens the gap before row 33.
        state.update(pointer: CGPoint(x: 120, y: pickedFrame.minY - rowStride * 2 + 4))
        XCTAssertEqual(state.layout.gap?.anchor, .before(.tab(tabIDs[33])))

        // Resting on row 33's projected center (shifted down by the open gap) offers nesting.
        state.update(pointer: CGPoint(x: 120, y: pickedFrame.midY - rowStride))
        XCTAssertEqual(state.resolvedTarget?.kind, .createCurrentFolder(tabIDs[33]))

        // Moving the pointer down to the top edge of row 37 moves the gap cleanly.
        state.update(pointer: CGPoint(x: 120, y: pickedFrame.minY + rowStride * 2 + 4))
        XCTAssertNotEqual(state.layout.gap?.anchor, .before(.tab(tabIDs[33])))
        XCTAssertNotNil(state.layout.gap)

        state.cancel()
    }

    private func makeContext(sourceIsProtected: Bool = false) -> (
        store: BrowserStore,
        source: SpaceState.Seed,
        destination: SpaceState.Seed,
        sourceTab: TabState.Seed
    ) {
        let sourceTab = TabState.Seed(
            id: fixedUUID(1),
            title: "Source tab",
            url: nil,
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let destinationTab = TabState.Seed.startPage(
            id: fixedUUID(2),
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let source = SpaceState.Seed(
            id: fixedUUID(3),
            profileID: fixedUUID(4),
            name: "Source",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab],
            accessPolicy: sourceIsProtected
                ? .deviceOwnerAuthentication
                : .open
        )
        let destination = SpaceState.Seed(
            id: fixedUUID(5),
            profileID: fixedUUID(6),
            name: "Destination",
            symbol: "2.circle",
            accent: .rose,
            folders: [],
            tabs: [destinationTab]
        )
        let store = BrowserStore(seed: SessionState.Seed(spaces: [source, destination]), core: .hostingPages())
        return (store, source, destination, sourceTab)
    }

    private func replaceProfile(
        of space: SpaceState.Seed,
        in store: BrowserStore
    ) {
        store.replaceProfileForTesting(of: space.id, with: fixedUUID(7))
    }

    private func fixedUUID(_ suffix: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x2D,
                0x45, 0x58, 0x41, 0x43, 0x54, 0x00, 0x00, suffix
            )
        )
    }

}
