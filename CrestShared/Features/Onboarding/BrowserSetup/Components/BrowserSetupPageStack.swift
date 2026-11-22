import SwiftUI

/// The steps panel's pages as a stack that moves as one: the pages lie side
/// by side in the order they open, and the row slides. Opening a page, or
/// going on to the next step, slides both pages toward the leading edge;
/// going back slides them toward the trailing edge. The pages a move leaves
/// stay laid out until the slide ends, so the two always travel together.
struct BrowserSetupPageStack<Page: View>: View {
    // MARK: - Types

    /// A page in the row, which keeps its identity while it stays open.
    private struct Level: Identifiable {
        let id = UUID()
        /// The page, or nil for the list of steps under every other.
        let destination: BrowserSetupDestination?
    }

    // MARK: - Variables

    /// The pages open over the list of steps, deepest last.
    let path: [BrowserSetupDestination]
    /// Whether a move that is neither opening nor closing pages goes back, as
    /// Back from a page deeper in a step leads to the step's own page.
    let isGoingBack: Bool
    @ViewBuilder let page: (BrowserSetupDestination?) -> Page

    @State private var levels = [Level(destination: nil)]
    /// The page in the row the panel shows.
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                    page(level.destination)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: CGFloat(index - shown) * geometry.size.width)
                        .allowsHitTesting(index == shown)
                        .accessibilityHidden(index != shown)
                }
            }
        }
        .clipped()
        .onAppear { settle(on: path) }
        .onChange(of: path) { old, new in turn(from: old, to: new) }
    }

    // MARK: - Mutators

    /// Shows `path` at once, with nothing to slide from.
    private func settle(on path: [BrowserSetupDestination]) {
        levels = [Level(destination: nil)] + path.map { Level(destination: $0) }
        shown = path.count
    }

    /// Slides from the pages `old` opened to the ones `new` opens. The pages
    /// both open stay where they are; the rest come in on the side the move
    /// goes toward, and the pages it leaves go once the slide ends.
    private func turn(from old: [BrowserSetupDestination], to new: [BrowserSetupDestination]) {
        let kept = zip(old, new).prefix { $0 == $1 }.count
        let common = Array(levels.prefix(kept + 1))
        let leaving = Array(levels.dropFirst(kept + 1))
        let arriving = new.dropFirst(kept).map { Level(destination: $0) }
        let goesBack = new.count < old.count && arriving.isEmpty || isGoingBack
        guard !reduceMotion else {
            levels = common + arriving
            shown = levels.count - 1
            return
        }
        if goesBack {
            // The arriving pages lie under the one shown, which slides off
            // toward the trailing edge.
            levels = common + arriving + leaving
            shown = levels.count - 1
            withAnimation(CrestMotion.onboardingStep) {
                shown = common.count + arriving.count - 1
            } completion: {
                levels = common + arriving
            }
        } else {
            // The arriving pages lie past the one shown, which slides off
            // toward the leading edge.
            levels = common + leaving + arriving
            withAnimation(CrestMotion.onboardingStep) {
                shown = levels.count - 1
            } completion: {
                levels = common + arriving
                shown = levels.count - 1
            }
        }
    }
}
