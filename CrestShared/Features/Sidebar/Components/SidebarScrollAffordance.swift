import SwiftUI

extension View {
    /// Marks real rows, before the empty hit area expands to fill the viewport.
    func sidebarScrollContent() -> some View {
        modifier(SidebarScrollContentExtent())
    }
}

extension EnvironmentValues {
    @Entry fileprivate var sidebarScrollActivity: SidebarScrollActivity? = nil
    /// Whether the sidebar is on screen, rather than slid away while it stays
    /// laid out.
    @Entry var sidebarIsShown = true
}

private struct SidebarScrollContentExtent: ViewModifier {
    @Environment(\.sidebarScrollActivity) private var activity

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { height in
            activity?.contentHeight = height
        }
    }
}

/// The same vertical-scroll affordance in windowed and touch sidebars. Its
/// geometry updates are observed only by the indicator, never the tab rows.
///
/// A shell may also ask it to reveal a row. It scrolls only as far as the row
/// needs, never while the person scrolls or drags, and without motion while
/// the sidebar is off screen. Asks that arrive before the row is laid out
/// collapse into the newest.
struct SidebarScrollAffordance: ViewModifier {
    var isDragging = false
    /// The row to reveal, by the identity it carries in the list; a new
    /// request asks again.
    var revealing: SidebarScrollReveal? = nil
    /// Called once the affordance took `revealing`, whether or not it scrolled.
    var didTakeReveal: () -> Void = {}
    /// Whether the person is busy with the list in a way a reveal must not
    /// move it under, such as renaming a row or dragging from it.
    var holdsStill = false
    @State private var activity = SidebarScrollActivity()
    @State private var position = ScrollPosition()
    @State private var pendingReveal: SidebarScrollReveal?
    @State private var latestRevealID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarIsShown) private var isShown

    func body(content: Content) -> some View {
        content
            .environment(\.sidebarScrollActivity, activity)
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: SidebarScrollMetrics.self) { geometry in
                SidebarScrollMetrics(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height + geometry.contentInsets.top
                        + geometry.contentInsets.bottom,
                    viewportHeight: geometry.containerSize.height,
                    visibleBottom: geometry.visibleRect.maxY)
            } action: { _, metrics in
                activity.update(metrics)
            }
            .onScrollPhaseChange { _, phase in
                activity.setScrolling(phase != .idle, byPerson: phase != .idle && phase != .animating)
            }
            .overlay {
                SidebarScrollIndicator(activity: activity, isDragging: isDragging) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        position.scrollTo(
                            y: min(
                                activity.metrics.maximumOffset,
                                activity.metrics.offset + activity.metrics.viewportHeight * 0.85))
                    }
                }
            }
            // A reveal's task outlives this copy of the modifier, so it reads
            // the hold through the activity rather than these values.
            .onChange(of: isDragging || holdsStill, initial: true) { _, held in activity.isHeldStill = held }
            .onChange(of: revealing, initial: true) { _, reveal in take(reveal) }
            .onDisappear { activity.reset() }
    }

    private func take(_ reveal: SidebarScrollReveal?) {
        guard let reveal else { return }
        didTakeReveal()
        guard !isDragging, !holdsStill, !activity.isMovedByPerson else { return }
        let isWaiting = pendingReveal != nil
        pendingReveal = reveal
        latestRevealID = reveal.requestID
        guard !isWaiting else { return }
        Task { @MainActor in
            // The row may have been inserted in this same turn; a lazy stack
            // lays it out on the next one.
            await Task.yield()
            guard let reveal = pendingReveal else { return }
            pendingReveal = nil
            guard !activity.isHeldStill, !activity.isMovedByPerson else { return }
            let animation: Animation? = reduceMotion || !isShown ? nil : .easeInOut(duration: 0.22)
            activity.revealDidStart()
            // A lazy list has not made a row far from view, so the list first
            // scrolls to where the row falls, then to the row once it exists.
            if let offset = activity.offsetRevealing(reveal.placement) {
                withAnimation(animation) { position.scrollTo(y: offset) }
                try? await Task.sleep(for: .milliseconds(animation == nil ? 50 : 260))
                // A newer reveal took over while the list moved.
                guard latestRevealID == reveal.requestID else { return }
                // The person took the list, or began to rename or drag, while
                // it moved.
                guard !activity.isHeldStill, !activity.isMovedByPerson else { return }
            }
            withAnimation(animation) {
                position.scrollTo(id: reveal.rowID)
            }
        }
    }
}

/// A row a sidebar list should bring into view, named by the identity the row
/// carries. Each request is new, so asking for the same row again asks again.
struct SidebarScrollReveal: Equatable {
    /// Where the row falls among the rows the list draws, which places it
    /// before a lazy list has made it.
    struct Placement: Equatable {
        let index: Int
        let count: Int
    }

    let requestID: UUID
    let rowID: UUID
    var placement: Placement? = nil
}

private struct SidebarScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var visibleBottom: CGFloat = 0
    var maximumOffset: CGFloat { max(0, contentHeight - viewportHeight) }
}

@MainActor
@Observable
private final class SidebarScrollActivity {
    var contentHeight: CGFloat = 0 {
        didSet { if contentHeight != oldValue { layoutChangedAt = .now } }
    }
    var hasMoreBelow: Bool { contentHeight > metrics.visibleBottom + 1 }
    private(set) var metrics = SidebarScrollMetrics()
    private(set) var showsIndicator = false
    /// Whether the person is renaming or dragging, which a reveal never
    /// moves the list under.
    @ObservationIgnored var isHeldStill = false
    @ObservationIgnored private var isScrolling = false
    @ObservationIgnored private var isPersonScrolling = false
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    /// When the person last moved the list, and until when movement belongs
    /// to a reveal instead.
    @ObservationIgnored private var personMovedAt = ContinuousClock.Instant.now - .seconds(60)
    @ObservationIgnored private var revealMovesUntil = ContinuousClock.Instant.now - .seconds(60)
    /// When rows last came, went or changed height. The list then moves its
    /// offset to hold what is on screen still, which is not the person.
    @ObservationIgnored private var layoutChangedAt = ContinuousClock.Instant.now - .seconds(60)

    /// Whether the person is scrolling the list or just did, which a reveal
    /// never interrupts.
    var isMovedByPerson: Bool {
        isPersonScrolling || ContinuousClock.now - personMovedAt < .milliseconds(600)
    }

    func revealDidStart() {
        revealMovesUntil = .now + .milliseconds(700)
    }

    /// The offset that brings a row at `placement` just into view, estimated
    /// from the rows' average height, or nil when it is already in view or
    /// the list does not scroll.
    func offsetRevealing(_ placement: SidebarScrollReveal.Placement?) -> CGFloat? {
        guard let placement, placement.count > 0, metrics.maximumOffset > 0 else { return nil }
        let rowHeight = contentHeight / CGFloat(placement.count)
        let top = rowHeight * CGFloat(placement.index)
        let offset: CGFloat
        if top + rowHeight > metrics.offset + metrics.viewportHeight {
            offset = top + rowHeight * 2 - metrics.viewportHeight
        } else if top < metrics.offset {
            offset = top - rowHeight
        } else {
            return nil
        }
        return min(max(0, offset), metrics.maximumOffset)
    }

    func update(_ value: SidebarScrollMetrics) {
        let moved =
            abs(value.offset - metrics.offset) > 0.5
            && value.viewportHeight == metrics.viewportHeight && value.contentHeight == metrics.contentHeight
        if value.viewportHeight != metrics.viewportHeight || value.contentHeight != metrics.contentHeight {
            layoutChangedAt = .now
        }
        metrics = value
        // Discrete mouse wheels and programmatic drag autoscrolling may move
        // without a native gesture phase. They use the same idle deadline.
        if moved {
            let now = ContinuousClock.now
            if now > revealMovesUntil, now - layoutChangedAt > .milliseconds(250) { personMovedAt = now }
            showsIndicator = true
            if !isScrolling { scheduleIdle() }
        }
    }

    func setScrolling(_ scrolling: Bool, byPerson: Bool) {
        isScrolling = scrolling
        isPersonScrolling = byPerson
        idleTask?.cancel()
        if scrolling { showsIndicator = true } else { scheduleIdle() }
    }

    func reset() {
        idleTask?.cancel()
        idleTask = nil
        isScrolling = false
        isPersonScrolling = false
        showsIndicator = false
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            self?.showsIndicator = false
            self?.idleTask = nil
        }
    }
}

private struct SidebarScrollIndicator: View {
    let activity: SidebarScrollActivity
    let isDragging: Bool
    let scrollDown: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsBubble: Bool {
        activity.hasMoreBelow && !activity.showsIndicator && !isDragging
    }

    var body: some View {
        GeometryReader { geometry in
            let track = max(0, geometry.size.height - 8)
            let metrics = activity.metrics
            let height = min(track, max(24, track * metrics.viewportHeight / max(1, metrics.contentHeight)))
            let fraction = min(1, max(0, metrics.offset / max(1, metrics.maximumOffset)))
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.primary.opacity(0.45))
                    .frame(width: 3, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 3)
                    .offset(y: 4 + (track - height) * fraction)
                    .opacity(activity.showsIndicator && metrics.maximumOffset > 1 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Button(action: scrollDown) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(
                            width: CrestLayout.glassIconButtonDiameter / 2,
                            height: CrestLayout.glassIconButtonDiameter / 2
                        )
                        .glassEffect(.regular.interactive(), in: .circle)
                        .frame(
                            width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget,
                            alignment: .bottom
                        )
                        .contentShape(.circle)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .scaleEffect(reduceMotion || showsBubble ? 1 : 0.5, anchor: .bottom)
                .offset(y: reduceMotion ? -6 : showsBubble ? -6 : CrestLayout.glassIconButtonDiameter + 8)
                .opacity(showsBubble ? 1 : 0)
                .allowsHitTesting(showsBubble)
                .accessibilityHidden(!showsBubble)
                .accessibilityLabel("Show more tabs")
                .accessibilityIdentifier("sidebar-more-tabs")
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activity.showsIndicator)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsBubble)
            .clipped()
        }
    }
}
