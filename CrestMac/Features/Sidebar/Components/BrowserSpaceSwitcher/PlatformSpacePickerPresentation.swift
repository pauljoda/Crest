import AppKit
import QuartzCore
import SwiftUI

/// Preserves the shared icon buttons while moving their highlight and native
/// scroll viewport with the page layers' actual presentation.
struct PlatformSpacePickerPresentation: NSViewRepresentable {
    let presentation: SpacePagerPresentation
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID?
    let frames: [SpaceID: CGRect]
    let selectionTint: Color?

    func makeNSView(context: Context) -> SpacePickerPresentationView {
        SpacePickerPresentationView()
    }

    func updateNSView(_ view: SpacePickerPresentationView, context: Context) {
        view.update(
            presentation: presentation, spaces: spaces,
            selectedSpaceID: selectedSpaceID, frames: frames, selectionTint: selectionTint)
    }

    static func dismantleNSView(_ view: SpacePickerPresentationView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
final class SpacePickerPresentationView: NSView {
    private struct ScrollSegment {
        let generation: UInt
        let phase: SpacePagerPresentation.Phase
        let destinationID: SpaceID
        let startPosition: CGFloat
        let destinationPosition: CGFloat
        let startOffset: CGFloat
        let destinationOffset: CGFloat
    }

    private let highlight = CAShapeLayer()
    private var presentation: SpacePagerPresentation?
    private weak var clipView: NSClipView?
    private var spaceIDs: [SpaceID] = []
    private var frames: [SpaceID: CGRect] = [:]
    private var colors: [SpaceID: NSColor] = [:]
    private var lastSnapshot: SpacePagerPresentation.Snapshot?
    private var scrollSegment: ScrollSegment?
    private var isObserving = false
    private var connectionScheduled = false
    private var lastViewportWidth: CGFloat = 0
    private var needsInitialPosition = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(highlight)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() } else { connectSoon() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { disconnect() } else { connectSoon() }
    }

    override func layout() {
        super.layout()
        if let clipView, lastViewportWidth != clipView.bounds.width {
            lastViewportWidth = clipView.bounds.width
            needsInitialPosition = true
            if let snapshot = lastSnapshot, snapshot.phase == .idle {
                receive(snapshot)
            }
        }
    }

    func update(
        presentation: SpacePagerPresentation, spaces: [BrowserSpace],
        selectedSpaceID: SpaceID?, frames: [SpaceID: CGRect], selectionTint: Color?
    ) {
        if self.presentation !== presentation {
            disconnect()
            self.presentation = presentation
        }
        let ids = spaces.map(\.id)
        if spaceIDs != ids {
            lastSnapshot = nil
            scrollSegment = nil
            needsInitialPosition = true
        }
        spaceIDs = ids
        if self.frames != frames { needsInitialPosition = true }
        self.frames = frames
        colors = Dictionary(
            uniqueKeysWithValues: spaces.map {
                ($0.id, NSColor(selectionTint ?? $0.branding.primaryColor.color))
            })
        if let snapshot = presentation.snapshot, snapshot.spaceIDs == ids {
            receive(snapshot)
        } else if let selectedSpaceID, let index = ids.firstIndex(of: selectedSpaceID) {
            drawHighlight(at: CGFloat(index))
        }
        connectSoon()
    }

    private func connectSoon() {
        guard !connectionScheduled else { return }
        connectionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            connectionScheduled = false
            guard window != nil, let scrollView = enclosingScrollView else { return }
            if clipView !== scrollView.contentView { needsInitialPosition = true }
            clipView = scrollView.contentView
            if !isObserving {
                isObserving = true
                presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
            }
            if needsInitialPosition, let snapshot = presentation?.snapshot, snapshot.phase == .idle {
                receive(snapshot)
            }
        }
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot) {
        guard snapshot.spaceIDs == spaceIDs, snapshot.position.isFinite else { return }
        let previous = lastSnapshot
        lastSnapshot = snapshot
        drawHighlight(at: snapshot.position)

        if snapshot.phase == .idle {
            if let scrollSegment, previous?.phase != .idle,
                snapshot.destinationID == scrollSegment.destinationID
            {
                advanceScroll(scrollSegment, position: snapshot.position)
                needsInitialPosition = false
            } else if needsInitialPosition || previous == nil || previous?.position != snapshot.position
                || previous?.phase != .idle
            {
                needsInitialPosition = true
                if let offset = centeredOffset(at: snapshot.position) {
                    scroll(to: offset)
                    needsInitialPosition = false
                }
            }
            scrollSegment = nil
            return
        }

        guard let destinationID = snapshot.destinationID,
            let destinationIndex = spaceIDs.firstIndex(of: destinationID),
            let clipView, let destinationOffset = centeredOffset(at: CGFloat(destinationIndex))
        else { return }
        if scrollSegment?.generation != snapshot.generation || scrollSegment?.phase != snapshot.phase
            || scrollSegment?.destinationID != destinationID
        {
            // Capture the real lane offset on interruption, release or reversal.
            // Manual overflow scrolling therefore cannot jump at gesture start.
            scrollSegment = ScrollSegment(
                generation: snapshot.generation, phase: snapshot.phase, destinationID: destinationID,
                startPosition: previous?.position ?? snapshot.position,
                destinationPosition: CGFloat(destinationIndex),
                startOffset: clipView.bounds.minX, destinationOffset: destinationOffset)
        }
        if let scrollSegment { advanceScroll(scrollSegment, position: snapshot.position) }
    }

    private func advanceScroll(_ segment: ScrollSegment, position: CGFloat) {
        let distance = segment.destinationPosition - segment.startPosition
        guard abs(distance) > 0.000_001 else { return }
        let fraction = min(1, max(0, (position - segment.startPosition) / distance))
        scroll(to: segment.startOffset + (segment.destinationOffset - segment.startOffset) * fraction)
    }

    private func centeredOffset(at position: CGFloat) -> CGFloat? {
        guard let clipView, let document = clipView.documentView,
            let frame = interpolatedFrame(at: position)
        else { return nil }
        let center = document.convert(CGPoint(x: frame.midX, y: frame.midY), from: self)
        let minimum = document.bounds.minX
        let maximum = max(minimum, document.bounds.maxX - clipView.bounds.width)
        return min(maximum, max(minimum, center.x - clipView.bounds.width / 2))
    }

    private func scroll(to offset: CGFloat) {
        guard let clipView, abs(clipView.bounds.minX - offset) > 0.001 else { return }
        clipView.scroll(to: CGPoint(x: offset, y: clipView.bounds.minY))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    private func drawHighlight(at position: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let frame = interpolatedFrame(at: position), let color = interpolatedColor(at: position) else {
            highlight.isHidden = true
            return
        }
        highlight.isHidden = false
        highlight.frame = frame
        let stroke = CrestLayout.hairline
        highlight.path = CGPath(
            roundedRect: CGRect(origin: .zero, size: frame.size).insetBy(dx: stroke / 2, dy: stroke / 2),
            cornerWidth: CrestSpaceIconPickerMetrics.cornerRadius,
            cornerHeight: CrestSpaceIconPickerMetrics.cornerRadius, transform: nil)
        highlight.fillColor =
            color.withAlphaComponent(
                color.alphaComponent * CrestSpaceIconPickerMetrics.selectionFillOpacity
            ).cgColor
        highlight.strokeColor = color.cgColor
        highlight.lineWidth = stroke
    }

    private func interpolation(at position: CGFloat) -> (SpaceID, SpaceID, CGFloat)? {
        guard !spaceIDs.isEmpty else { return nil }
        let position = min(CGFloat(spaceIDs.count - 1), max(0, position))
        let lower = Int(position.rounded(.down))
        let upper = min(spaceIDs.count - 1, lower + 1)
        return (spaceIDs[lower], spaceIDs[upper], position - CGFloat(lower))
    }

    private func interpolatedFrame(at position: CGFloat) -> CGRect? {
        guard let (lower, upper, fraction) = interpolation(at: position),
            let start = frames[lower], let end = frames[upper],
            start.width > 0, start.height > 0, end.width > 0, end.height > 0
        else { return nil }
        return CGRect(
            x: start.minX + (end.minX - start.minX) * fraction,
            y: start.minY + (end.minY - start.minY) * fraction,
            width: start.width + (end.width - start.width) * fraction,
            height: start.height + (end.height - start.height) * fraction)
    }

    private func interpolatedColor(at position: CGFloat) -> NSColor? {
        guard let (lower, upper, fraction) = interpolation(at: position),
            let start = colors[lower]?.usingColorSpace(.deviceRGB),
            let end = colors[upper]?.usingColorSpace(.deviceRGB)
        else { return nil }
        return NSColor(
            red: start.redComponent + (end.redComponent - start.redComponent) * fraction,
            green: start.greenComponent + (end.greenComponent - start.greenComponent) * fraction,
            blue: start.blueComponent + (end.blueComponent - start.blueComponent) * fraction,
            alpha: start.alphaComponent + (end.alphaComponent - start.alphaComponent) * fraction)
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        isObserving = false
        clipView = nil
        scrollSegment = nil
        lastViewportWidth = 0
        needsInitialPosition = true
    }
}
