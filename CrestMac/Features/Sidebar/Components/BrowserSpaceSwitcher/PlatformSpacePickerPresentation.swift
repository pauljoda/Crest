import AppKit
import QuartzCore
import SwiftUI

/// Preserves the shared icon buttons while moving their highlight and native
/// scroll viewport with the page layers' actual presentation.
struct PlatformSpacePickerPresentation: NSViewRepresentable {
    let presentation: SpacePagerPresentation
    let style: CrestSpaceIconPickerStyle
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID?
    let frames: [UUID: CGRect]
    let selectionTint: Color?

    func makeNSView(context: Context) -> SpacePickerPresentationView {
        SpacePickerPresentationView()
    }

    func updateNSView(_ view: SpacePickerPresentationView, context: Context) {
        view.update(
            presentation: presentation, style: style, spaces: spaces,
            selectedSpaceID: selectedSpaceID, frames: frames, selectionTint: selectionTint)
    }

    static func dismantleNSView(_ view: SpacePickerPresentationView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
final class SpacePickerPresentationView: NSView {

    /// Wraps the group of the selected Space, behind the selection.
    private let groupOutline = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private var outline = SpacePickerGroupOutline(profileIDs: [])
    private var presentation: SpacePagerPresentation?
    private var style = CrestSpaceIconPickerStyle.compact
    private weak var clipView: NSClipView?
    private var spaceIDs: [UUID] = []
    private var frames: [UUID: CGRect] = [:]
    private var colors: [UUID: NSColor] = [:]
    /// Each Space's colour for a stroke: lifted toward the colour its text
    /// reads in, so the selection and a group's outline hold against a
    /// backdrop of their own hue.
    private var strokes: [UUID: NSColor] = [:]
    private var lastSnapshot: SpacePagerPresentation.Snapshot?
    private var scrollSegment: SpacePickerScrollProgress?
    private var activeTransition: SpacePagerSettlement?
    private var isObserving = false
    private var connectionScheduled = false
    private var lastViewportWidth: CGFloat = 0
    private var needsInitialPosition = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(groupOutline)
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
        presentation: SpacePagerPresentation, style: CrestSpaceIconPickerStyle, spaces: [BrowserSpaceIdentity],
        selectedSpaceID: UUID?, frames: [UUID: CGRect], selectionTint: Color?
    ) {
        if self.presentation !== presentation {
            disconnect()
            self.presentation = presentation
        }
        self.style = style
        let ids = spaces.map(\.id)
        if spaceIDs != ids {
            lastSnapshot = nil
            scrollSegment = nil
            needsInitialPosition = true
        }
        spaceIDs = ids
        outline = SpacePickerGroupOutline(profileIDs: spaces.map(\.profileID))
        if self.frames != frames { needsInitialPosition = true }
        self.frames = frames
        let system = BrowserSpaceForegroundTone(
            readingIn: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        colors = [:]
        strokes = [:]
        for space in spaces {
            let color = NSColor(selectionTint ?? space.branding.primaryColor.color)
            let reading: NSColor = space.branding.foregroundTone(system: system) == .light ? .white : .black
            colors[space.id] = color
            strokes[space.id] =
                color.blended(withFraction: CrestSpaceIconPickerMetrics.strokeLift, of: reading) ?? color
        }
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
        // Core Animation owns the complete release. Reinstalling from sampled
        // positions would turn a delayed callback into the visible catch-up jump.
        if let transition = snapshot.transition, activeTransition == transition { return }
        let previous = lastSnapshot
        lastSnapshot = snapshot
        let visibleScrollOffset =
            activeTransition == nil
            ? clipView?.bounds.minX : clipView?.layer?.presentation()?.bounds.minX ?? clipView?.bounds.minX
        highlight.removeAllAnimations()
        groupOutline.removeAllAnimations()
        clipView?.layer?.removeAnimation(forKey: "spaceTransition.bounds.origin")
        activeTransition = nil
        if let visibleScrollOffset, snapshot.phase != .idle { scroll(to: visibleScrollOffset) }
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
            scrollSegment = SpacePickerScrollProgress(
                generation: snapshot.generation, phase: snapshot.phase, destinationID: destinationID,
                startPosition: previous.flatMap { $0.generation == snapshot.generation ? $0.position : nil }
                    ?? snapshot.position,
                destinationPosition: CGFloat(destinationIndex),
                startOffset: clipView.bounds.minX, destinationOffset: destinationOffset)
        }
        if let transition = snapshot.transition {
            if animateHighlight(transition) { activeTransition = transition }
            if let scrollSegment, let layer = clipView.layer {
                let start = NSValue(point: CGPoint(x: scrollSegment.startOffset, y: clipView.bounds.minY))
                let end = NSValue(point: CGPoint(x: scrollSegment.destinationOffset, y: clipView.bounds.minY))
                scroll(to: scrollSegment.destinationOffset)
                transition.animate(
                    layer, keyPath: "bounds.origin", values: [start, end], followsSpaceBoundaries: false)
            }
        } else if let scrollSegment {
            advanceScroll(scrollSegment, position: snapshot.position)
        }
    }

    private func animateHighlight(_ transition: SpacePagerSettlement) -> Bool {
        let frames = transition.positions.compactMap { selectionFrame(at: $0) }
        let colors = transition.positions.compactMap { interpolated(self.colors, at: $0) }
        let strokes = transition.positions.compactMap { interpolated(self.strokes, at: $0) }
        guard frames.count == transition.positions.count, colors.count == frames.count, strokes.count == frames.count
        else { return false }
        animateOutline(transition)
        transition.animate(
            highlight, keyPath: "position", values: frames.map { NSValue(point: CGPoint(x: $0.midX, y: $0.midY)) })
        transition.animate(highlight, keyPath: "bounds.size", values: frames.map { NSValue(size: $0.size) })
        let insets = transition.positions.map { selectionInset(at: $0) }
        transition.animate(
            highlight, keyPath: "path", values: zip(frames, insets).map { selectionPath(in: $0.size, inset: $1) })
        transition.animate(
            highlight, keyPath: "fillColor",
            values: colors.map {
                $0.withAlphaComponent($0.alphaComponent * CrestSpaceIconPickerMetrics.selectionFillOpacity).cgColor
            })
        transition.animate(highlight, keyPath: "strokeColor", values: strokes.map(\.cgColor))
        return true
    }

    /// Moves the group outline on the selection's clock: it grows into a
    /// group, holds within one and shrinks back as the selection leaves.
    private func animateOutline(_ transition: SpacePagerSettlement) {
        let outlines = transition.positions.map { outlineFrame(at: $0) }
        let colors = transition.positions.compactMap { outlineColor(self.colors, at: $0) }
        let strokes = transition.positions.compactMap { outlineColor(self.strokes, at: $0) }
        guard outlines.allSatisfy({ $0 != nil }), colors.count == outlines.count, strokes.count == outlines.count
        else {
            groupOutline.isHidden = true
            return
        }
        let frames = outlines.compactMap { $0 }
        groupOutline.isHidden = false
        transition.animate(
            groupOutline, keyPath: "position",
            values: frames.map { NSValue(point: CGPoint(x: $0.rect.midX, y: $0.rect.midY)) })
        transition.animate(groupOutline, keyPath: "bounds.size", values: frames.map { NSValue(size: $0.rect.size) })
        transition.animate(groupOutline, keyPath: "opacity", values: frames.map { Float($0.opacity) })
        transition.animate(groupOutline, keyPath: "path", values: frames.map { outlinePath(in: $0.rect.size) })
        transition.animate(
            groupOutline, keyPath: "fillColor",
            values: colors.map {
                $0.withAlphaComponent($0.alphaComponent * CrestSpaceIconPickerMetrics.groupOutlineFillOpacity).cgColor
            })
        transition.animate(groupOutline, keyPath: "strokeColor", values: strokes.map(\.cgColor))
    }

    private func advanceScroll(_ segment: SpacePickerScrollProgress, position: CGFloat) {
        scroll(to: segment.offset(at: position))
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
        guard let frame = selectionFrame(at: position), let color = interpolated(colors, at: position),
            let stroke = interpolated(strokes, at: position)
        else {
            highlight.isHidden = true
            groupOutline.isHidden = true
            return
        }
        drawOutline(at: position)
        highlight.isHidden = false
        highlight.frame = frame
        highlight.path = selectionPath(in: frame.size, inset: selectionInset(at: position))
        highlight.fillColor =
            color.withAlphaComponent(
                color.alphaComponent * CrestSpaceIconPickerMetrics.selectionFillOpacity
            ).cgColor
        highlight.strokeColor = stroke.cgColor
        highlight.lineWidth = CrestSpaceIconPickerMetrics.selectionStroke
    }

    /// Draws the group outline at `position`, or hides it where it wraps
    /// nothing.
    private func drawOutline(at position: CGFloat) {
        guard let outline = outlineFrame(at: position), let color = outlineColor(colors, at: position),
            let stroke = outlineColor(strokes, at: position)
        else {
            groupOutline.isHidden = true
            return
        }
        groupOutline.isHidden = false
        groupOutline.frame = outline.rect
        groupOutline.opacity = Float(outline.opacity)
        groupOutline.path = outlinePath(in: outline.rect.size)
        groupOutline.fillColor =
            color.withAlphaComponent(color.alphaComponent * CrestSpaceIconPickerMetrics.groupOutlineFillOpacity).cgColor
        groupOutline.strokeColor = stroke.cgColor
        groupOutline.lineWidth = CrestSpaceIconPickerMetrics.groupOutlineStroke
    }

    /// The selection's path in a frame `size` set `inset` inside a group's
    /// outline: the outline's shape drawn that far in, so the two keep
    /// concentric corners.
    private func selectionPath(in size: CGSize, inset: CGFloat) -> CGPath {
        CrestSpaceIconPickerShape(style: style)
            .inset(by: inset + CrestSpaceIconPickerMetrics.selectionStroke / 2)
            .path(in: CGRect(origin: .zero, size: size).insetBy(dx: -inset, dy: -inset))
            .cgPath
    }

    private func outlinePath(in size: CGSize) -> CGPath {
        CrestSpaceIconPickerShape(style: style)
            .inset(by: CrestSpaceIconPickerMetrics.groupOutlineStroke / 2)
            .path(in: CGRect(origin: .zero, size: size))
            .cgPath
    }

    private func outlineFrame(at position: CGFloat) -> SpacePickerGroupOutline.Frame? {
        outline.frame(
            at: position, frames: { [frames, spaceIDs] in frames[spaceIDs[$0]] },
            inset: CrestSpaceIconPickerMetrics.groupSelectionInset)
    }

    /// The selection's frame at `position`: the segment, inset inside a
    /// group's outline.
    private func selectionFrame(at position: CGFloat) -> CGRect? {
        guard let frame = interpolatedFrame(at: position) else { return nil }
        let inset = selectionInset(at: position)
        return frame.insetBy(dx: inset, dy: inset)
    }

    /// How far the selection sits inside a group's outline at `position`.
    private func selectionInset(at position: CGFloat) -> CGFloat {
        outlineFrame(at: position)?.selectionInset ?? 0
    }

    private func interpolatedFrame(at position: CGFloat) -> CGRect? {
        guard let sample = SpacePagerInterpolation(position: position, count: spaceIDs.count),
            let start = frames[spaceIDs[sample.lower]], let end = frames[spaceIDs[sample.upper]],
            start.width > 0, start.height > 0, end.width > 0, end.height > 0
        else { return nil }
        return sample.frame(from: start, to: end)
    }

    /// The group outline's colour from `palette` at `position`: its
    /// primary's, so it stays one colour while the selection moves through
    /// the group.
    private func outlineColor(_ palette: [UUID: NSColor], at position: CGFloat) -> NSColor? {
        interpolated(palette, at: position) { outline.primary(of: $0) }
    }

    /// The colour from `palette` at `position`, blending the colours of the
    /// Spaces `index` picks for the positions either side of it.
    private func interpolated(
        _ palette: [UUID: NSColor], at position: CGFloat, of index: (Int) -> Int = { $0 }
    ) -> NSColor? {
        guard let sample = SpacePagerInterpolation(position: position, count: spaceIDs.count),
            let start = palette[spaceIDs[index(sample.lower)]]?.usingColorSpace(.deviceRGB),
            let end = palette[spaceIDs[index(sample.upper)]]?.usingColorSpace(.deviceRGB)
        else { return nil }
        let fraction = sample.fraction
        return NSColor(
            red: start.redComponent + (end.redComponent - start.redComponent) * fraction,
            green: start.greenComponent + (end.greenComponent - start.greenComponent) * fraction,
            blue: start.blueComponent + (end.blueComponent - start.blueComponent) * fraction,
            alpha: start.alphaComponent + (end.alphaComponent - start.alphaComponent) * fraction)
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        isObserving = false
        clipView?.layer?.removeAnimation(forKey: "spaceTransition.bounds.origin")
        clipView = nil
        scrollSegment = nil
        activeTransition = nil
        highlight.removeAllAnimations()
        groupOutline.removeAllAnimations()
        lastViewportWidth = 0
        needsInitialPosition = true
    }
}
