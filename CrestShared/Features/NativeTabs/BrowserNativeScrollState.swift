import SwiftUI

/// Stores the user's position independently of a ScrollView's mounted lifetime.
@MainActor
final class BrowserNativeScrollState {
    var offset: CGFloat = 0
    var listRow: Int?
    var listRowOffset: CGFloat = 0
}

/// Where a scroll view's content sits right now, kept off the view graph so
/// following it doesn't redraw anything on every frame.
@MainActor
private final class BrowserNativeScrollGeometry {
    var offset: CGFloat = 0
    var viewport: CGFloat = 0
    var maximumOffset: CGFloat = 0
}

private struct BrowserNativeScrollRestoration<Target: Hashable & Sendable>: ViewModifier {
    let state: BrowserNativeScrollState
    /// A view the content should scroll to instead of its restored position,
    /// by its `id`, such as the settings section a search result opens at.
    let target: Target?
    /// Whether the content has made the target's view yet. A list makes its
    /// rows only as they come near the screen, so a row far down the page
    /// can't be scrolled to by its `id` until the list has scrolled near it.
    let isMade: (Target) -> Bool
    private let restoredOffset: CGFloat
    @State private var position: ScrollPosition
    @State private var geometry = BrowserNativeScrollGeometry()

    init(state: BrowserNativeScrollState, target: Target?, isMade: @escaping (Target) -> Bool) {
        self.state = state
        self.target = target
        self.isMade = isMade
        restoredOffset = state.offset
        _position = State(initialValue: ScrollPosition(y: state.offset))
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onAppear {
                guard target == nil else { return }
                withTransaction(Transaction(animation: nil)) { position.scrollTo(y: restoredOffset) }
            }
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, current in
                geometry.offset = current.contentOffset.y + current.contentInsets.top
                geometry.viewport = current.containerSize.height
                geometry.maximumOffset = max(
                    0,
                    current.contentSize.height + current.contentInsets.top + current.contentInsets.bottom
                        - current.containerSize.height)
            }
            .onScrollPhaseChange { _, phase, context in
                // Recorded when a scroll comes to rest rather than on every
                // frame: following the offset would update the view graph
                // each frame the content moves.
                guard phase == .idle else { return }
                state.offset = max(0, context.geometry.contentOffset.y + context.geometry.contentInsets.top)
            }
            .task(id: target) {
                guard let target else { return }
                await reveal(target)
            }
    }

    /// Scrolls to `target`. Until the content has made it, steps down a
    /// screen at a time from the top, so the list makes the rows on the way.
    private func reveal(_ target: Target) async {
        // Let the content lay out and make the rows it starts with. A reveal
        // cancelled meanwhile mustn't move the page.
        do { try await Task.sleep(for: CrestMotion.searchMatchSettle) } catch { return }
        if !isMade(target) {
            withTransaction(Transaction(animation: nil)) { position.scrollTo(y: 0) }
            try? await Task.sleep(for: Self.stepPause)
        }
        var steps = 0
        while !isMade(target), geometry.offset < geometry.maximumOffset - 1, steps < Self.maximumSteps {
            guard !Task.isCancelled else { return }
            let next = min(geometry.offset + geometry.viewport * Self.stepShare, geometry.maximumOffset)
            withTransaction(Transaction(animation: nil)) { position.scrollTo(y: next) }
            try? await Task.sleep(for: Self.stepPause)
            steps += 1
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: CrestMotion.scrollAlignmentTransition)) {
            position.scrollTo(id: target, anchor: .top)
        }
    }

    /// How much of a screen each step moves, keeping some rows in view so
    /// none is skipped between steps.
    private static var stepShare: CGFloat { 0.8 }
    /// How long a step waits for the list to make the rows it brought near.
    private static var stepPause: Duration { .milliseconds(40) }
    /// The most steps a reveal takes before it gives up on the target.
    private static var maximumSteps: Int { 60 }
}

extension View {
    func browserNativeScrollState(_ state: BrowserNativeScrollState) -> some View {
        browserNativeScrollState(state, target: Int?.none) { _ in true }
    }

    /// Keeps the content's scroll position in `state` across remounts, or
    /// scrolls it to the view whose `id` is `target` while one is given.
    /// `isMade` answers whether the content has made that view yet.
    func browserNativeScrollState<Target: Hashable & Sendable>(
        _ state: BrowserNativeScrollState, target: Target?, isMade: @escaping (Target) -> Bool
    ) -> some View {
        modifier(BrowserNativeScrollRestoration(state: state, target: target, isMade: isMade))
            .id(ObjectIdentifier(state))
    }
}
