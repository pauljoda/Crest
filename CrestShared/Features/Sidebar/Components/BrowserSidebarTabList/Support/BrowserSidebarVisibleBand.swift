import Observation
import SwiftUI

/// The stretch of a scrolling sidebar's content that is on screen, and which
/// of its folders are far enough from it to be drawn as blocks of their own
/// height.
///
/// Building every folder of a long sidebar, on screen or not, was what made
/// it slow to scroll. The band moves in steps of a quarter of the screen, in
/// the content's own coordinates, which scrolling never moves, and only a
/// step changes what is drawn. Each folder's decision is a box of its own, so
/// a step redraws only the folders it changes. A folder is let go only once
/// it has stayed far from the screen across a step, so a frame it reports
/// for a moment while the list first lays out never lets it go, and nothing
/// is let go while a drag is in flight.
///
/// A folder is let go only while it is below the screen. Its tab rows sit in
/// lazy stacks, and when the rows a lazy stack has made above the screen are
/// dropped or drawn again, the scroll view moves the list back by about
/// their height, even though the block that takes their place is as tall.
/// Scrolling down a long folder let go of the folder above it, which threw
/// the list back past that folder; the folder was drawn again, and the list
/// never got further. So a folder the screen has passed stays drawn, and a
/// block it has passed waits until it comes near again.
@MainActor
final class BrowserSidebarVisibleBand {
    // MARK: - Types

    /// One folder's place in the content and whether it is drawn as a block.
    /// Only the decision is observed.
    @Observable
    @MainActor
    final class Slot {
        fileprivate(set) var isPlaceholder = false
        /// Whether a block has stood in for the folder, so drawing it now
        /// draws it again.
        @ObservationIgnored fileprivate(set) var wasLetGo = false
        @ObservationIgnored fileprivate var frame: CGRect?
        /// Whether the folder has a drawn height a block could take.
        @ObservationIgnored fileprivate var canLetGo = false
        /// The step at which the folder was first found far from the screen.
        @ObservationIgnored fileprivate var farSince: Int?
    }

    /// The scroll viewport's current vertical range in content coordinates,
    /// quantized so recycled tab runs update in small batches while smooth
    /// scrolling and immediately across large jumps.
    @Observable
    @MainActor
    final class Viewport {
        fileprivate(set) var visibleRange: ClosedRange<CGFloat>?
    }

    // MARK: - Static Variables

    /// The content's own coordinates, in which frames don't move as it scrolls.
    static let contentSpace = NamedCoordinateSpace.named("browser-sidebar-scroll-content")

    /// Step size for `viewport.visibleRange`, aligned to one row so smooth
    /// scrolling updates at most one recycled slot per frame instead of
    /// batching multiple row updates onto a single 120 Hz frame.
    private static let viewportQuantizationStep: CGFloat = 42

    /// How far below the screen, in screens, a drawn folder may be before it
    /// is let go, and how near a block must come to be drawn again. The gap
    /// between them keeps a folder at the edge from changing at every step.
    private static let releaseDistance: CGFloat = 2
    private static let drawDistance: CGFloat = 1

    // MARK: - Variables

    let viewport = Viewport()
    private var visible: ClosedRange<CGFloat>?
    private var step = 0
    private var isHolding = false
    private var slots: [UUID: Slot] = [:]

    // MARK: - Actions - Slots

    /// The folder's box, made the first time it is asked for.
    func slot(for folderID: UUID) -> Slot {
        if let slot = slots[folderID] { return slot }
        let slot = Slot()
        slots[folderID] = slot
        return slot
    }

    /// Forgets a folder whose row has gone, so it starts drawn when it returns.
    func forget(_ folderID: UUID) {
        slots[folderID] = nil
    }

    // MARK: - Mutators

    /// Follows where a folder sits in the content, and whether it has a drawn
    /// height a block could take.
    func place(_ folderID: UUID, at frame: CGRect, canLetGo: Bool) {
        let slot = slot(for: folderID)
        slot.frame = frame
        slot.canLetGo = canLetGo
        decide(slot)
    }

    /// Follows whether a folder has a drawn height a block could take.
    func allow(_ folderID: UUID, toLetGo canLetGo: Bool) {
        let slot = slot(for: folderID)
        slot.canLetGo = canLetGo
        decide(slot)
    }

    /// Follows the scroll view's visible rect, in quarter-screen steps for
    /// offscreen folders and finer steps for recycled tab runs. The first rect
    /// it is given is where it starts, not a step.
    func follow(_ visibleRect: CGRect) {
        guard visibleRect.height > 0 else { return }
        let viewportStep = Self.viewportQuantizationStep
        let viewportLower = (visibleRect.minY / viewportStep).rounded(.down) * viewportStep
        let viewportUpper = viewportLower + visibleRect.height.rounded(.up) + viewportStep
        let nextViewport = viewportLower...viewportUpper
        if nextViewport != viewport.visibleRange {
            viewport.visibleRange = nextViewport
        }
        let quarter = visibleRect.height / 4
        let top = (visibleRect.minY / quarter).rounded(.down) * quarter
        let next = top...(visibleRect.maxY / quarter).rounded(.up) * quarter
        guard next != visible else { return }
        if visible != nil { step += 1 }
        visible = next
        for slot in slots.values { decide(slot) }
    }

    /// Holds every drawn folder while a drag is in flight. Blocks that come
    /// near are still drawn.
    func hold(_ isHolding: Bool) {
        self.isHolding = isHolding
        guard !isHolding else { return }
        for slot in slots.values { decide(slot) }
    }

    private func decide(_ slot: Slot) {
        guard let frame = slot.frame, let visible else { return }
        let screen = visible.upperBound - visible.lowerBound
        let margin = screen * (slot.isPlaceholder ? Self.drawDistance : Self.releaseDistance)
        let isNear = frame.maxY >= visible.lowerBound - margin && frame.minY <= visible.upperBound + margin
        let isPassed = frame.maxY < visible.lowerBound
        guard !isNear, slot.canLetGo, slot.isPlaceholder || !isPassed else {
            slot.farSince = nil
            if slot.isPlaceholder { slot.isPlaceholder = false }
            return
        }
        guard !slot.isPlaceholder, !isHolding else { return }
        if let farSince = slot.farSince, farSince < step {
            slot.isPlaceholder = true
            slot.wasLetGo = true
        } else if slot.farSince == nil {
            slot.farSince = step
        }
    }
}

extension EnvironmentValues {
    /// The band a scrolling sidebar shows, where a shell keeps one.
    @Entry var browserSidebarVisibleBand: BrowserSidebarVisibleBand? = nil
}
