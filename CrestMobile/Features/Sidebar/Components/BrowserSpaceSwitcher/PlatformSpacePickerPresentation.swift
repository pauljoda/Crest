import SwiftUI
import UIKit

/// Only the highlight layer and icon lane follow touch samples. Icon buttons,
/// accessibility, ordering and overflow controls remain in the shared picker.
struct PlatformSpacePickerPresentation: UIViewRepresentable {
    let presentation: SpacePagerPresentation
    let style: CrestSpaceIconPickerStyle
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID?
    let frames: [UUID: CGRect]
    let selectionTint: Color?

    func makeUIView(context: Context) -> SpacePickerPresentationView { SpacePickerPresentationView() }

    func updateUIView(_ view: SpacePickerPresentationView, context: Context) {
        view.update(
            presentation: presentation, style: style, spaces: spaces, selectedSpaceID: selectedSpaceID,
            frames: frames, tint: selectionTint)
    }

    static func dismantleUIView(_ view: SpacePickerPresentationView, coordinator: ()) { view.disconnect() }
}

@MainActor
final class SpacePickerPresentationView: UIView {
    /// Wraps the group of the selected Space, behind the selection.
    private let groupOutline = CALayer()
    private let highlight = CALayer()
    private var outline = SpacePickerGroupOutline(profileIDs: [])
    private weak var presentation: SpacePagerPresentation?
    private var style = CrestSpaceIconPickerStyle.touch
    private weak var scrollView: UIScrollView?
    private var ids: [UUID] = []
    private var tint: UIColor?
    private var tones: [SpaceForegroundPresentation.Tone] = []
    private var frames: [UUID: CGRect] = [:]
    private var lastSnapshot: SpacePagerPresentation.Snapshot?
    private var scrollSegment: SpacePickerScrollProgress?
    private var lastPosition: CGFloat?
    private var needsInitialPosition = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.addSublayer(groupOutline)
        layer.addSublayer(highlight)
    }
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { disconnect() }
    }

    func update(
        presentation: SpacePagerPresentation, style: CrestSpaceIconPickerStyle, spaces: [BrowserSpaceIdentity],
        selectedSpaceID: UUID?, frames: [UUID: CGRect], tint: Color?
    ) {
        if self.presentation !== presentation {
            disconnect()
            self.presentation = presentation
        }
        self.style = style
        // Anchor resolution introduces subpixel rounding during native scrolling.
        // That is not a layout change and must not recenter manual overflow taps.
        let oldWidth = ids.first.flatMap { self.frames[$0]?.width } ?? 0
        let newWidth = spaces.first.flatMap { frames[$0.id]?.width } ?? 0
        if ids != spaces.map(\.id) || abs(oldWidth - newWidth) > 0.5 { needsInitialPosition = true }
        ids = spaces.map(\.id)
        outline = SpacePickerGroupOutline(profileIDs: spaces.map(\.profileID))
        let system = BrowserSpaceForegroundTone(readingIn: ColorScheme(traitCollection.userInterfaceStyle) ?? .light)
        tones = spaces.map {
            .init(
                id: $0.id,
                white: $0.branding.foregroundTone(system: system) == .light ? 1 : 0)
        }
        self.frames = frames
        self.tint = tint.map(UIColor.init)
        // The background representable joins its enclosing native scroll view
        // after SwiftUI attaches it. No scroll delegate or private view is replaced.
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil, self.presentation === presentation else { return }
            var ancestor = superview
            while let candidate = ancestor {
                if let scroll = candidate as? UIScrollView {
                    scrollView = scroll
                    break
                }
                ancestor = candidate.superview
            }
            presentation.observe(owner: self) { [weak self] in self?.receive($0) }
            if presentation.snapshot?.spaceIDs != ids {
                draw(at: CGFloat(ids.firstIndex { $0 == selectedSpaceID } ?? 0))
            }
        }
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot) {
        guard snapshot.spaceIDs == ids, snapshot.position.isFinite else { return }
        let previous = lastSnapshot
        lastSnapshot = snapshot
        if snapshot.phase != .idle, let scrollView, let destinationID = snapshot.destinationID,
            let destinationIndex = ids.firstIndex(of: destinationID),
            let destinationOffset = centeredOffset(at: CGFloat(destinationIndex))
        {
            if scrollSegment?.generation != snapshot.generation || scrollSegment?.phase != snapshot.phase
                || scrollSegment?.destinationID != destinationID
            {
                scrollSegment = SpacePickerScrollProgress(
                    generation: snapshot.generation, phase: snapshot.phase, destinationID: destinationID,
                    startPosition: previous?.position ?? snapshot.position,
                    destinationPosition: CGFloat(destinationIndex), startOffset: scrollView.contentOffset.x,
                    destinationOffset: destinationOffset)
            }
        } else if snapshot.phase == .idle {
            scrollSegment = nil
        }
        draw(at: snapshot.position)
    }

    private func centeredOffset(at position: CGFloat) -> CGFloat? {
        guard let sample = SpacePagerInterpolation(position: position, count: ids.count),
            let start = frames[ids[sample.lower]], let end = frames[ids[sample.upper]],
            let scrollView
        else { return nil }
        let frame = sample.frame(from: start, to: end)
        let center = convert(CGPoint(x: frame.midX, y: frame.midY), to: scrollView)
        let minimum = -scrollView.adjustedContentInset.left
        let maximum = max(
            minimum,
            scrollView.contentSize.width - scrollView.bounds.width
                + scrollView.adjustedContentInset.right)
        return min(maximum, max(minimum, center.x - scrollView.bounds.width / 2))
    }

    private func draw(at position: CGFloat) {
        guard let interpolation = SpacePagerInterpolation(position: position, count: ids.count),
            let start = frames[ids[interpolation.lower]], let end = frames[ids[interpolation.upper]]
        else { return }
        let group = outline.frame(
            at: position, frames: { [frames, ids] in frames[ids[$0]] },
            inset: CrestSpaceIconPickerMetrics.groupSelectionInset)
        let inset = group?.selectionInset ?? 0
        let frame = interpolation.frame(from: start, to: end).insetBy(dx: inset, dy: inset)
        let color = tint ?? UIColor(white: SpaceForegroundPresentation.white(at: position, tones: tones), alpha: 1)
        // The outline wears its primary's tone whichever member is selected.
        let primaryTones = tones.indices.map { tones[outline.primary(of: $0)] }
        let outlineColor =
            tint ?? UIColor(white: SpaceForegroundPresentation.white(at: position, tones: primaryTones), alpha: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = frame
        // Inside a group's outline the selection keeps the outline's corners,
        // drawn `inset` in, so the two stay concentric.
        highlight.cornerRadius = max(
            0, CrestSpaceIconPickerShape(style: style).cornerRadius(in: frame.insetBy(dx: -inset, dy: -inset)) - inset)
        highlight.cornerCurve = CrestSpaceIconPickerShape.layerCornerCurve
        highlight.backgroundColor = color.withAlphaComponent(0.22).cgColor
        // The outline grows into a group, holds within one and shrinks back
        // as the selection leaves.
        groupOutline.isHidden = group == nil
        if let group {
            groupOutline.frame = group.rect
            groupOutline.opacity = Float(group.opacity)
            groupOutline.cornerRadius = CrestSpaceIconPickerShape(style: style).cornerRadius(in: group.rect)
            groupOutline.cornerCurve = CrestSpaceIconPickerShape.layerCornerCurve
            groupOutline.backgroundColor = outlineColor.withAlphaComponent(0.11).cgColor
            groupOutline.borderColor = outlineColor.cgColor
            groupOutline.borderWidth = CrestSpaceIconPickerMetrics.groupOutlineStroke
        }
        CATransaction.commit()
        defer { lastPosition = position }
        // Repeated idle updates must leave manual overflow scrolling alone.
        guard needsInitialPosition || lastPosition != position,
            let scrollView, !scrollView.isDragging, !scrollView.isDecelerating,
            scrollView.bounds.width > 0
        else { return }
        guard let offset = scrollSegment?.offset(at: position) ?? centeredOffset(at: position) else { return }
        scrollView.setContentOffset(CGPoint(x: offset, y: scrollView.contentOffset.y), animated: false)
        needsInitialPosition = false
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        scrollView = nil
        lastPosition = nil
        lastSnapshot = nil
        scrollSegment = nil
        needsInitialPosition = true
    }
}
