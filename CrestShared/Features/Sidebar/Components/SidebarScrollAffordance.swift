import SwiftUI

extension View {
    /// Marks real rows, before the empty hit area expands to fill the viewport.
    func sidebarScrollContent() -> some View {
        modifier(SidebarScrollContentExtent())
    }
}

extension EnvironmentValues {
    @Entry fileprivate var sidebarScrollActivity: SidebarScrollActivity? = nil
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
/// On the Mac the list shows AppKit's own scroll bar, so its thumb can be
/// dragged and its track clicked, and it follows Show scroll bars in System
/// Settings: an overlay bar while the list moves, or one that always shows.
/// A touch list draws a quiet bar of its own while it moves.
///
/// A shell may also ask it to reveal a row. It moves the list only as far as
/// the row needs, never while the person scrolls the list or is busy with it,
/// and drops a reveal it cannot make rather than making it later.
struct SidebarScrollAffordance: ViewModifier {
    /// How long the scroll a press of the indicator asks for takes.
    private static let pageScrollDuration: TimeInterval = 0.22
    #if os(macOS)
        private static let systemIndicators = ScrollIndicatorVisibility.automatic
        private static let drawsIndicator = false
    #else
        private static let systemIndicators = ScrollIndicatorVisibility.never
        private static let drawsIndicator = true
    #endif
    /// How many times a reveal looks for its row, and how long it lets the
    /// list lay out, or finish moving, in between.
    private static let revealSteps = 6
    private static let revealLayoutWait: Duration = .milliseconds(40)
    private static let revealMoveWait: Duration = .milliseconds(260)
    /// The steps a reveal waits for a row the list has not laid out before it
    /// goes where the row falls, so the list lays it out.
    private static let revealEstimateSteps = 2

    var isDragging = false
    /// A row to bring into view, which the affordance takes once.
    var reveal: SidebarScrollReveal? = nil
    /// Called once the affordance took `reveal`, whether or not it moved.
    var didTakeReveal: () -> Void = {}
    @State private var activity = SidebarScrollActivity()
    @State private var position = ScrollPosition()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.sidebarScrollActivity, activity)
            .scrollIndicators(Self.systemIndicators)
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
                SidebarScrollIndicator(activity: activity, drawsBar: Self.drawsIndicator, isDragging: isDragging) {
                    activity.willMoveItself()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.pageScrollDuration)) {
                        position.scrollTo(
                            y: min(
                                activity.metrics.maximumOffset,
                                activity.metrics.offset + activity.metrics.viewportHeight * 0.85))
                    }
                }
            }
            .onChange(of: reveal, initial: true) { _, reveal in take(reveal) }
            .onDisappear { activity.reset() }
    }

    // MARK: - Actions - Revealing

    private func take(_ reveal: SidebarScrollReveal?) {
        guard let reveal else { return }
        didTakeReveal()
        activity.revealing?.cancel()
        guard !reveal.isHeld(), !activity.isMovedByPerson else { return }
        activity.revealing = Task { @MainActor in
            let animation: Animation? =
                reveal.animates && !reduceMotion ? .easeInOut(duration: Self.pageScrollDuration) : nil
            for step in 0..<Self.revealSteps {
                // The row may have come in this same turn; the list lays it
                // out and measures it on the next.
                try? await Task.sleep(for: step == 0 || animation == nil ? Self.revealLayoutWait : Self.revealMoveWait)
                guard !Task.isCancelled, !reveal.isHeld(), !activity.isMovedByPerson, let location = reveal.locate()
                else { return }
                switch location {
                case .placed(let row, let viewport):
                    if let offset = activity.offsetRevealing(row, in: viewport) {
                        activity.willMoveItself()
                        withAnimation(animation) { position.scrollTo(y: offset) }
                    }
                    return
                case .leading(let row, let viewport, let estimate):
                    // Once the row on the way is in view, the list goes to
                    // where the row itself falls, so it lays the row out.
                    let offset = activity.offsetRevealing(row, in: viewport) ?? activity.offsetNear(estimate)
                    if let offset {
                        activity.willMoveItself()
                        withAnimation(animation) { position.scrollTo(y: offset) }
                    }
                case .estimated(let estimate):
                    guard step >= Self.revealEstimateSteps, let offset = activity.offsetNear(estimate) else { continue }
                    activity.willMoveItself()
                    withAnimation(animation) { position.scrollTo(y: offset) }
                }
            }
        }
    }
}

/// A row a shell asks its sidebar list to bring into view, once. `locate`
/// answers where the row is now, or nil when there is nothing to reveal;
/// `isHeld`, whether the person is busy with the list in a way a reveal must
/// not move it under; and `animates`, whether the list moves visibly. Asks
/// compare by `id`, so asking for the same row again asks anew.
struct SidebarScrollReveal: Equatable {
    // MARK: - Types

    /// Where a row is: laid out at a frame in the same space as the list's
    /// viewport; not laid out yet, behind a row on the way to it that is,
    /// such as an open folder; or not laid out at all. A row not laid out
    /// carries how far down the list it falls, from 0 at the top to 1 at the
    /// foot, where the list goes so it lays the row out.
    enum Location {
        case placed(CGRect, viewport: CGRect)
        case leading(CGRect, viewport: CGRect, estimate: Double)
        case estimated(Double)
    }

    // MARK: - Variables

    let id: UUID
    let animates: Bool
    let locate: @MainActor () -> Location?
    let isHeld: @MainActor () -> Bool

    // MARK: - Actions - Comparing

    static func == (lhs: SidebarScrollReveal, rhs: SidebarScrollReveal) -> Bool {
        lhs.id == rhs.id
    }
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
    /// How long the indicator stays once scrolling stops.
    private static let indicatorIdleDelay: Duration = .milliseconds(600)
    /// How long after the person last moved the list a reveal leaves it
    /// alone, and how long the list's own moves take to settle.
    private static let personMoveHold: Duration = .milliseconds(600)
    private static let ownMoveSettle: Duration = .milliseconds(400)
    /// How far from the viewport's top a revealed row lands, and from its
    /// foot, where the "Show more tabs" bubble sits.
    private static let revealTopMargin: CGFloat = 8
    private static let revealBottomMargin: CGFloat = CrestLayout.minimumHitTarget

    var contentHeight: CGFloat = 0
    var hasMoreBelow: Bool { contentHeight > metrics.visibleBottom + 1 }
    private(set) var metrics = SidebarScrollMetrics()
    private(set) var showsIndicator = false
    @ObservationIgnored private var isScrolling = false
    @ObservationIgnored private var isPersonScrolling = false
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    /// The reveal in progress, which a newer one replaces.
    @ObservationIgnored var revealing: Task<Void, Never>?
    /// When the person last moved the list, and until when movement is the
    /// list's own, from a reveal or the indicator.
    @ObservationIgnored private var personMovedAt = ContinuousClock.now - .seconds(60)
    @ObservationIgnored private var ownMoveUntil = ContinuousClock.now - .seconds(60)

    /// Whether the person is scrolling the list or just did, which a reveal
    /// never moves it under.
    var isMovedByPerson: Bool {
        isPersonScrolling || ContinuousClock.now - personMovedAt < Self.personMoveHold
    }

    /// The offset that brings `row` just into `viewport`, both in one space,
    /// moving the list as little as it can; nil when the row is in view. A
    /// row taller than the viewport lands at its top.
    func offsetRevealing(_ row: CGRect, in viewport: CGRect) -> CGFloat? {
        let below = row.maxY + Self.revealBottomMargin - viewport.maxY
        let above = viewport.minY + Self.revealTopMargin - row.minY
        let delta: CGFloat
        if below > 0.5 {
            delta = min(below, -above)
        } else if above > 0.5 {
            delta = -above
        } else {
            return nil
        }
        let offset = min(max(0, metrics.offset + delta), metrics.maximumOffset)
        return abs(offset - metrics.offset) > 0.5 ? offset : nil
    }

    /// The offset that centers the point `fraction` of the way down the list,
    /// or nil when the list is already there or does not scroll.
    func offsetNear(_ fraction: Double) -> CGFloat? {
        guard metrics.maximumOffset > 0 else { return nil }
        let offset = min(max(0, contentHeight * fraction - metrics.viewportHeight / 2), metrics.maximumOffset)
        return abs(offset - metrics.offset) > metrics.viewportHeight / 4 ? offset : nil
    }

    /// The list is about to move itself, which is not the person.
    func willMoveItself() {
        ownMoveUntil = .now + Self.ownMoveSettle
    }

    func update(_ value: SidebarScrollMetrics) {
        let moved =
            abs(value.offset - metrics.offset) > 0.5
            && value.viewportHeight == metrics.viewportHeight && value.contentHeight == metrics.contentHeight
        metrics = value
        // Discrete mouse wheels and programmatic drag autoscrolling may move
        // without a native gesture phase. They use the same idle deadline.
        if moved {
            // The person's gesture moves the list, and so does a move without
            // a gesture phase, such as a discrete mouse wheel, unless the list
            // moved itself.
            if isPersonScrolling || (!isScrolling && ContinuousClock.now > ownMoveUntil) { personMovedAt = .now }
            showsIndicator = true
            if !isScrolling { scheduleIdle() }
        }
    }

    func setScrolling(_ scrolling: Bool, byPerson: Bool) {
        // The hold runs from the end of the person's gesture, momentum
        // included, never from the end of the list's own animation.
        if byPerson || isPersonScrolling { personMovedAt = .now }
        isScrolling = scrolling
        isPersonScrolling = byPerson
        idleTask?.cancel()
        if scrolling { showsIndicator = true } else { scheduleIdle() }
    }

    func reset() {
        idleTask?.cancel()
        idleTask = nil
        revealing?.cancel()
        revealing = nil
        isScrolling = false
        isPersonScrolling = false
        showsIndicator = false
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.indicatorIdleDelay) } catch { return }
            self?.showsIndicator = false
            self?.idleTask = nil
        }
    }
}

private struct SidebarScrollIndicator: View {
    /// The bubble's size, and how far its centered hit frame drops, so the
    /// bubble itself sits just above the sidebar's foot.
    private static let bubbleDiameter: CGFloat = 22
    private static let bubbleDrop: CGFloat = 5
    /// How strongly the scroll indicator's bar draws.
    private static let barOpacity = 0.45
    /// How long the indicator and its bubble take to show or hide.
    private static let fadeDuration: TimeInterval = 0.2

    let activity: SidebarScrollActivity
    /// Whether the indicator draws the bar, where the list shows no system one.
    let drawsBar: Bool
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
                if drawsBar {
                    Capsule()
                        .fill(.primary.opacity(Self.barOpacity))
                        .frame(width: 3, height: height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 3)
                        .offset(y: 4 + (track - height) * fraction)
                        .opacity(activity.showsIndicator && metrics.maximumOffset > 1 ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // The bubble stands on the device's material, as the pins do,
                // and takes presses a full hit target around it, so a touch
                // just beside it scrolls rather than reaching the row behind.
                Button(action: scrollDown) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .labelStyle(.iconOnly)
                .buttonStyle(
                    CrestChromeButtonStyle(
                        controlSize: CGSize(width: Self.bubbleDiameter, height: Self.bubbleDiameter),
                        cornerRadius: Self.bubbleDiameter / 2, restsOnMaterial: true,
                        hitOutset: (CrestLayout.minimumHitTarget - Self.bubbleDiameter) / 2)
                )
                .scaleEffect(reduceMotion || showsBubble ? 1 : 0.5, anchor: .bottom)
                .offset(y: reduceMotion || showsBubble ? Self.bubbleDrop : CrestLayout.minimumHitTarget + 8)
                .opacity(showsBubble ? 1 : 0)
                .allowsHitTesting(showsBubble)
                .accessibilityHidden(!showsBubble)
                .accessibilityLabel("Show more tabs")
                .accessibilityIdentifier("sidebar-more-tabs")
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: Self.fadeDuration), value: activity.showsIndicator)
            .animation(reduceMotion ? nil : .easeInOut(duration: Self.fadeDuration), value: showsBubble)
            .clipped()
        }
    }
}
