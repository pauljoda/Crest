import XCTest

@testable import Crest

final class CrestSpacePickerReorderingTests: XCTestCase {
    func testEdgeScrollContinuesBeyondTheViewportButStopsAwayFromTheRow() {
        let viewport = CGRect(x: 100, y: 100, width: 104, height: 36)
        XCTAssertEqual(CrestSpacePickerReordering.autoscrollStep(at: CGPoint(x: 152, y: 118), in: viewport), 0)
        XCTAssertLessThan(CrestSpacePickerReordering.autoscrollStep(at: CGPoint(x: 110, y: 118), in: viewport), 0)
        XCTAssertGreaterThan(CrestSpacePickerReordering.autoscrollStep(at: CGPoint(x: 195, y: 118), in: viewport), 0)
        XCTAssertEqual(CrestSpacePickerReordering.autoscrollStep(at: CGPoint(x: 80, y: 118), in: viewport), -6)
        XCTAssertEqual(CrestSpacePickerReordering.autoscrollStep(at: CGPoint(x: 230, y: 118), in: viewport), 6)
        XCTAssertEqual(CrestSpacePickerReordering.autoscrollStep(at: CGPoint(x: 230, y: 180), in: viewport), 0)
        XCTAssertEqual(CrestSpacePickerReordering.autoscrollStep(at: CGPoint(x: 300, y: 118), in: viewport), 0)
    }

    func testScrollingUnderAStationaryPointerKeepsTheCrestVisibleAndUpdatesItsDestination() throws {
        let ids = (0..<5).map { _ in SpaceID() }
        var frames = Dictionary(
            uniqueKeysWithValues: ids.enumerated().map {
                ($0.element, CGRect(x: 100 + $0.offset * 40, y: 100, width: 40, height: 30))
            })
        let viewport = CGRect(x: 100, y: 100, width: 104, height: 36)
        var drag = CrestSpacePickerReordering()
        drag.update(
            source: ids[0], ids: ids, frames: frames,
            start: CGPoint(x: 120, y: 115), pointer: CGPoint(x: 225, y: 115), viewport: viewport)
        XCTAssertEqual(drag.targetID, ids[2])
        XCTAssertEqual(frames[ids[0]]!.midX + drag.translation.width, 184)

        frames = frames.mapValues { $0.offsetBy(dx: -40, dy: 0) }
        drag.contentMoved(by: -40, ids: ids, frames: frames)
        XCTAssertEqual(drag.targetID, ids[3])
        XCTAssertEqual(frames[ids[0]]!.midX + drag.translation.width, 184)

        frames = frames.mapValues { $0.offsetBy(dx: -40, dy: 0) }
        drag.contentMoved(by: -40, ids: ids, frames: frames)
        XCTAssertEqual(drag.targetID, ids[4])
        XCTAssertEqual(frames[ids[0]]!.midX + drag.translation.width, 184)
        XCTAssertEqual(try XCTUnwrap(drag.end()).target, ids[4])
        XCTAssertNil(drag.sourceID)
    }

    func testScrollingBackAndMovingThePointerDoesNotAccumulateLiftDrift() {
        let ids = (0..<4).map { _ in SpaceID() }
        var frames = Dictionary(
            uniqueKeysWithValues: ids.enumerated().map {
                ($0.element, CGRect(x: 100 + $0.offset * 40, y: 100, width: 40, height: 30))
            })
        var drag = CrestSpacePickerReordering()
        let start = CGPoint(x: 200, y: 115)
        let pointer = CGPoint(x: 120, y: 115)
        drag.update(source: ids[2], ids: ids, frames: frames, start: start, pointer: pointer)
        frames = frames.mapValues { $0.offsetBy(dx: 35, dy: 0) }
        drag.contentMoved(by: 35, ids: ids, frames: frames)
        XCTAssertEqual(frames[ids[2]]!.midX + drag.translation.width, 120)
        drag.update(source: ids[2], ids: ids, frames: frames, start: start, pointer: CGPoint(x: 126, y: 115))
        XCTAssertEqual(frames[ids[2]]!.midX + drag.translation.width, 126)
        XCTAssertEqual(drag.targetID, ids[0])
    }

    func testDraggingRightOpensAGapAndCommitsOnlyOnRelease() throws {
        let ids = (0..<4).map { _ in SpaceID() }
        let frames = Dictionary(
            uniqueKeysWithValues: ids.enumerated().map {
                ($0.element, CGRect(x: 100 + $0.offset * 40, y: 100, width: 40, height: 30))
            })
        var drag = CrestSpacePickerReordering()
        drag.update(
            source: ids[0], ids: ids, frames: frames, start: CGPoint(x: 120, y: 115), pointer: CGPoint(x: 202, y: 116))

        XCTAssertEqual(drag.targetID, ids[2])
        XCTAssertEqual(drag.offset(for: ids[0], ids: ids, frames: frames), CGSize(width: 82, height: 1))
        XCTAssertEqual(drag.offset(for: ids[1], ids: ids, frames: frames), CGSize(width: -40, height: 0))
        XCTAssertEqual(drag.offset(for: ids[2], ids: ids, frames: frames), CGSize(width: -40, height: 0))
        XCTAssertEqual(drag.offset(for: ids[3], ids: ids, frames: frames), .zero)
        let move = try XCTUnwrap(drag.end())
        XCTAssertEqual(move.source, ids[0])
        XCTAssertEqual(move.target, ids[2])
        XCTAssertNil(drag.sourceID)
    }

    func testDraggingLeftMovesNeighborsRightAndCanReturnToOriginalSlot() {
        let ids = (0..<3).map { _ in SpaceID() }
        let frames = Dictionary(
            uniqueKeysWithValues: ids.enumerated().map {
                ($0.element, CGRect(x: $0.offset * 40, y: 0, width: 40, height: 30))
            })
        var drag = CrestSpacePickerReordering()
        drag.update(
            source: ids[2], ids: ids, frames: frames, start: CGPoint(x: 100, y: 15), pointer: CGPoint(x: 20, y: 15))
        XCTAssertEqual(drag.targetID, ids[0])
        XCTAssertEqual(drag.offset(for: ids[0], ids: ids, frames: frames), CGSize(width: 40, height: 0))
        XCTAssertEqual(drag.offset(for: ids[1], ids: ids, frames: frames), CGSize(width: 40, height: 0))

        drag.update(
            source: ids[2], ids: ids, frames: frames, start: CGPoint(x: 100, y: 15), pointer: CGPoint(x: 96, y: 15))
        XCTAssertEqual(drag.offset(for: ids[0], ids: ids, frames: frames), .zero)
        XCTAssertNil(drag.end())
    }

    func testReleasingOutsideTheRowCancelsReordering() {
        let ids = [SpaceID(), SpaceID()]
        let frames = [
            ids[0]: CGRect(x: 0, y: 0, width: 40, height: 30), ids[1]: CGRect(x: 40, y: 0, width: 40, height: 30),
        ]
        var drag = CrestSpacePickerReordering()
        drag.update(
            source: ids[0], ids: ids, frames: frames, start: CGPoint(x: 20, y: 15), pointer: CGPoint(x: 60, y: 100))
        XCTAssertEqual(drag.offset(for: ids[1], ids: ids, frames: frames), .zero)
        XCTAssertNil(drag.end())
    }
}
