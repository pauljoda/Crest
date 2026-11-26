import CoreGraphics
import Testing

@testable import Crest

@MainActor
@Suite("Picture in Picture Geometry")
struct BrowserPictureInPictureGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let aspect: CGFloat = 16.0 / 9.0

    @Test("Corner resize stops at display edge without pushing the anchored corner")
    func cornerResizeStopsAtDisplayEdge() {
        let initial = CGRect(x: 1068, y: 12, width: 360, height: 202.5)

        // Dragging bottom-left corner far past the bottom edge keeps top-right anchored.
        let bottomLeft = BrowserPictureInPictureWindow.resized(
            initial, to: 1200, in: screen, horizontal: -1, vertical: -1,
            borderWidth: 0, aspect: aspect, backingScale: 2)
        #expect(abs(bottomLeft.maxX - initial.maxX) < 0.001)
        #expect(abs(bottomLeft.maxY - initial.maxY) < 0.001)
        #expect(bottomLeft.minY >= screen.minY)
        #expect(bottomLeft.minX >= screen.minX)

        // Dragging top-left corner far past the left edge keeps bottom-right anchored.
        let topLeft = BrowserPictureInPictureWindow.resized(
            initial, to: 2000, in: screen, horizontal: -1, vertical: 1,
            borderWidth: 0, aspect: aspect, backingScale: 2)
        #expect(abs(topLeft.maxX - initial.maxX) < 0.001)
        #expect(abs(topLeft.minY - initial.minY) < 0.001)
        #expect(topLeft.minX >= screen.minX)
        #expect(topLeft.maxY <= screen.maxY)

        // Dragging top-right corner far past the right edge keeps bottom-left anchored.
        let topRight = BrowserPictureInPictureWindow.resized(
            initial, to: 1200, in: screen, horizontal: 1, vertical: 1,
            borderWidth: 0, aspect: aspect, backingScale: 2)
        #expect(abs(topRight.minX - initial.minX) < 0.001)
        #expect(abs(topRight.minY - initial.minY) < 0.001)
        #expect(topRight.maxX <= screen.maxX)
        #expect(topRight.maxY <= screen.maxY)

        // Dragging bottom-right corner keeps top-left anchored.
        let bottomRight = BrowserPictureInPictureWindow.resized(
            initial, to: 1200, in: screen, horizontal: 1, vertical: -1,
            borderWidth: 0, aspect: aspect, backingScale: 2)
        #expect(abs(bottomRight.minX - initial.minX) < 0.001)
        #expect(abs(bottomRight.maxY - initial.maxY) < 0.001)
        #expect(bottomRight.maxX <= screen.maxX)
        #expect(bottomRight.minY >= screen.minY)
    }

    @Test("Side resize stops at display edge without shifting the opposite edge")
    func sideResizeStopsAtDisplayEdge() {
        let initial = CGRect(x: 1068, y: 12, width: 360, height: 202.5)

        // Expanding right edge into the right screen boundary keeps the left edge fixed.
        let rightDrag = BrowserPictureInPictureWindow.resized(
            initial, to: 900, in: screen, horizontal: 1, vertical: 0,
            borderWidth: 0, aspect: aspect, backingScale: 2)
        #expect(abs(rightDrag.minX - initial.minX) < 0.001)
        #expect(rightDrag.maxX <= screen.maxX)

        // Expanding bottom edge into the bottom screen boundary keeps the top edge fixed.
        let bottomDrag = BrowserPictureInPictureWindow.resized(
            initial, to: 900, in: screen, horizontal: 0, vertical: -1,
            borderWidth: 0, aspect: aspect, backingScale: 2)
        #expect(abs(bottomDrag.maxY - initial.maxY) < 0.001)
        #expect(bottomDrag.minY >= screen.minY)

        // Expanding left edge with a border keeps the right edge fixed and aspect ratio intact.
        let border: CGFloat = 6
        let bordered = CGRect(x: 1056, y: 12, width: 372, height: 360 / aspect + border * 2)
        let leftDrag = BrowserPictureInPictureWindow.resized(
            bordered, to: 800, in: screen, horizontal: -1, vertical: 0,
            borderWidth: border, aspect: aspect, backingScale: 2)
        #expect(abs(leftDrag.maxX - bordered.maxX) < 0.001)
        let contentAspect = (leftDrag.width - border * 2) / (leftDrag.height - border * 2)
        #expect(abs(contentAspect - aspect) < 0.01)
    }

    @Test("Corner drag width delta is continuous across opposing axis signs")
    func cornerDragDeltaIsContinuous() {
        // Crossing |dx| == |dy * aspect| with opposing outward signs must never jump.
        let dx: CGFloat = -60
        let crossingY = -60 / aspect
        let before = BrowserPictureInPictureWindow.resizeWidthDelta(
            dx: dx, dy: crossingY + 0.5, horizontalEdge: -1, verticalEdge: 1, aspect: aspect)
        let after = BrowserPictureInPictureWindow.resizeWidthDelta(
            dx: dx, dy: crossingY - 0.5, horizontalEdge: -1, verticalEdge: 1, aspect: aspect)
        #expect(abs(before - after) < 1.0)

        // Dragging along the exact outward aspect diagonal tracks the pointer 1:1.
        let diagonal = BrowserPictureInPictureWindow.resizeWidthDelta(
            dx: -100, dy: 100 / aspect, horizontalEdge: -1, verticalEdge: 1, aspect: aspect)
        #expect(abs(diagonal - 100) < 0.001)
    }

    @Test("Minimum width is respected without drifting the anchored corner")
    func minimumWidthRespectsAnchor() {
        let initial = CGRect(x: 1068, y: 12, width: 360, height: 202.5)
        let shrunk = BrowserPictureInPictureWindow.resized(
            initial, to: 40, in: screen, horizontal: -1, vertical: 1,
            borderWidth: 0, aspect: aspect, backingScale: 2)
        #expect(abs(shrunk.width - BrowserPictureInPictureWindow.minimumWidth) < 0.001)
        #expect(abs(shrunk.maxX - initial.maxX) < 0.001)
        #expect(abs(shrunk.minY - initial.minY) < 0.001)
    }
}
