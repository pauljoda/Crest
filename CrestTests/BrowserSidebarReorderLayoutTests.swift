import XCTest

@testable import Crest

final class BrowserSidebarReorderLayoutTests: XCTestCase {
    private let space = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
    private let source = BrowserSidebarReorderItemID.folder(FolderID())
    private let current = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)

    @MainActor
    func testNativeDragCompletionClearsTheMatchingLiftButNotANewerSession() throws {
        let state = BrowserSidebarReorderState()
        let item = BrowserSidebarReorderItem.tab(
            .init(tabID: TabID(), spaceID: space.spaceID, profileID: space.profileID))
        state.stage(item: item, section: current)
        let first = try XCTUnwrap(state.sessionToken)
        state.update(pointer: CGPoint(x: 50, y: 100))
        XCTAssertEqual(state.sessionToken, first)
        XCTAssertTrue(state.hidesSource(item.id))
        state.cancel(session: first)
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertFalse(state.hidesSource(item.id))
        XCTAssertNil(state.layout.gapFrame)

        state.stage(item: item, section: current)
        let second = try XCTUnwrap(state.sessionToken)
        XCTAssertNotEqual(first, second)
        state.update(pointer: CGPoint(x: 50, y: 100))
        state.cancel(session: first)
        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.sessionToken, second)
        state.cancel(session: second)
        XCTAssertFalse(state.hasLiftInFlight)
    }

    func testAdjacentFolderEdgesOfferTheirParentSectionForTabs() {
        for placement in [TabPlacement.saved, .current] {
            let parent = BrowserSidebarReorderSection.tabs(placement: placement, folderID: nil)
            let first = FolderID()
            let second = FolderID()
            let zones = [
                BrowserSidebarReorderZone(
                    target: .section(parent), frame: CGRect(x: 8, y: 100, width: 240, height: 240)),
                BrowserSidebarReorderZone(
                    target: .section(.tabs(placement: placement, folderID: first)),
                    frame: CGRect(x: 8, y: 100, width: 240, height: 80)),
                BrowserSidebarReorderZone(
                    target: .section(.tabs(placement: placement, folderID: second)),
                    frame: CGRect(x: 8, y: 180, width: 240, height: 80)),
            ]
            let item = BrowserSidebarReorderItem.tab(
                .init(tabID: TabID(), spaceID: space.spaceID, profileID: space.profileID))
            for y in [CGFloat(176), 180, 184] {
                XCTAssertEqual(
                    BrowserSidebarReorderPolicy.zone(at: CGPoint(x: 100, y: y), in: zones, accepting: item)?.target,
                    .section(parent))
            }
            XCTAssertEqual(
                BrowserSidebarReorderPolicy.zone(at: CGPoint(x: 100, y: 210), in: zones, accepting: item)?.target,
                .section(.tabs(placement: placement, folderID: second)))
        }
    }

    func testSavedFolderProjectionRetainsAnUnfiledTabBetweenFolders() {
        let first = BrowserFolder(title: "First")
        let second = BrowserFolder(title: "Second")
        let firstTab = BrowserTab(
            title: "First member", url: URL(string: "https://example.com/"), placement: .saved, folderID: first.id)
        let middle = BrowserTab(title: "Between", url: URL(string: "https://example.com/"), placement: .saved)
        let secondTab = BrowserTab(
            title: "Second member", url: URL(string: "https://example.com/"), placement: .saved, folderID: second.id)
        let items = BrowserSidebarFolderListItem.items(
            tabs: [firstTab, middle, secondTab], tree: BrowserFolderTree(folders: [first, second]), location: .saved)
        XCTAssertEqual(items.map(\.id), [.folder(first.id), .tab(middle.id), .folder(second.id)])
    }

    func testSourceDescendantsAndTheirDropZonesDisappearTogether() {
        let childID = FolderID()
        var layout = layout(before: row(.tab(TabID()), y: 300, height: 40))
        layout.hiddenIDs.insert(.folder(childID))
        XCTAssertNil(layout.frame(for: row(source, y: 100, height: 160)))
        XCTAssertNil(layout.frame(for: row(.folder(childID), y: 140, height: 100)))
        XCTAssertNil(
            layout.frame(
                for: .init(
                    target: .section(.folders(parentID: childID)),
                    frame: CGRect(x: 8, y: 180, width: 240, height: 60))))
    }

    @MainActor
    func testExpandedFolderPassesItsSiblingWithoutDraggingAnEntireFolderHeight() throws {
        let state = BrowserSidebarReorderState()
        let siblingID = FolderID()
        let sibling = row(.folder(siblingID), y: 260, height: 80)
        let following = row(.tab(TabID()), y: 340, height: 40)
        for row in [row(source, y: 100, height: 160), sibling, following] {
            state.register(row: row, owner: UUID())
        }
        state.register(
            zone: .init(target: .section(current), frame: CGRect(x: 8, y: 100, width: 240, height: 280)), for: UUID())
        state.register(
            zone: .init(
                target: .section(.folders(parentID: siblingID)),
                frame: CGRect(x: 8, y: 300, width: 240, height: 40)), for: UUID())
        state.begin(
            item: .folder(
                .init(folderID: try XCTUnwrap(source.folderID), spaceID: space.spaceID, profileID: space.profileID)),
            section: current, at: CGPoint(x: 80, y: 120))
        state.update(pointer: CGPoint(x: 80, y: 168))
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: following.id, index: 1))

        // Animation measurements and a held pointer cannot oscillate the slot.
        for _ in 0..<50 {
            state.register(row: row(.folder(siblingID), y: 100, height: 80), owner: UUID())
            state.update(pointer: CGPoint(x: 80, y: 168))
        }
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: following.id, index: 1))

        state.update(pointer: CGPoint(x: 80, y: 130))
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: sibling.id, index: 0))

        state.cancel()
        XCTAssertFalse(state.layout.isActive)
        XCTAssertNil(state.layout.gapFrame)
    }

    @MainActor
    func testAutoscrollMovesTheExistingGapBeforeResolvingTheHeldPointer() throws {
        let state = BrowserSidebarReorderState()
        let regionID = UUID()
        let sibling = row(.folder(FolderID()), y: 260, height: 80)
        let following = row(.tab(TabID()), y: 340, height: 40)
        state.register(scrollRegionFrame: CGRect(x: 0, y: 0, width: 260, height: 600), for: regionID)
        for row in [row(source, y: 100, height: 160), sibling, following] {
            state.register(row: row, owner: UUID(), scrollRegionID: regionID)
        }
        state.register(
            zone: .init(target: .section(current), frame: CGRect(x: 8, y: 100, width: 240, height: 280)),
            for: UUID(), scrollRegionID: regionID)
        state.begin(
            item: .folder(
                .init(folderID: try XCTUnwrap(source.folderID), spaceID: space.spaceID, profileID: space.profileID)),
            section: current, at: CGPoint(x: 80, y: 120))
        state.update(pointer: CGPoint(x: 80, y: 168))
        let target = state.resolvedTarget
        state.scrollableContentDidMove(in: regionID, by: -10)
        XCTAssertEqual(state.resolvedTarget, target)

        state.update(pointer: CGPoint(x: 80, y: 168))

    }

    @MainActor
    func testPinnedToStackUsesRowHeightAndMovesFollowingSectionsWithTheGrid() throws {
        let state = BrowserSidebarReorderState()
        let ids = (0..<5).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let pinned = BrowserSidebarReorderSection.tabs(placement: .pinned, folderID: nil)
        let grid = BrowserPinnedTabReorderLayout(ids: ids, availableWidth: 176)
        let bounds = CGRect(x: 8, y: 20, width: grid.availableWidth, height: grid.height)
        for id in ids {
            state.register(
                row: .init(
                    id: id, space: space, section: pinned,
                    frame: try XCTUnwrap(grid.frame(for: .tab(id), in: bounds))), owner: UUID())
        }
        let destination = row(.tab(TabID()), y: 400, height: 40)
        state.register(row: destination, owner: UUID())
        state.register(zone: .init(target: .section(pinned), frame: bounds, minimumHeight: 12), for: UUID())
        state.register(zone: .init(target: .section(current), frame: destination.frame), for: UUID())
        state.begin(
            item: .tab(.init(tabID: try XCTUnwrap(ids[0].tabID), spaceID: space.spaceID, profileID: space.profileID)),
            section: pinned, at: CGPoint(x: 30, y: 40))
        state.update(pointer: CGPoint(x: 90, y: 350))
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: current, beforeID: destination.id, index: 0))

        for _ in 0..<50 { state.update(pointer: CGPoint(x: 90, y: 350)) }

    }

    private func row(_ id: BrowserSidebarReorderItemID, y: CGFloat, height: CGFloat) -> BrowserSidebarReorderRow {
        BrowserSidebarReorderRow(
            id: id, space: space, section: current,
            frame: CGRect(x: 8, y: y, width: 240, height: height))
    }

    private func layout(before destination: BrowserSidebarReorderRow) -> BrowserSidebarReorderLayout {
        BrowserSidebarReorderLayout(
            sourceID: source, sourceFrame: CGRect(x: 8, y: 100, width: 240, height: 160),
            hiddenIDs: [source],
            gap: .init(
                section: current, anchor: .before(destination.id),
                frame: destination.frame, containingFolders: []))
    }
}
