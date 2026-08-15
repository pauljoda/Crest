import SwiftUI

/// Draws the insertion line for a run that has no rows of its own to anchor one
/// on: an unfiled saved list under a folder that holds every saved tab, a
/// pinned grid nobody has filled, a current list that was just cleared.
///
/// A populated run leaves the line to `BrowserSidebarReorderSourceModifier`, so
/// it travels with the row beside the gap. An empty run has no such row and
/// would otherwise show nothing at all while still accepting the drop — the
/// drag reads as refused right up until it lands somewhere.
///
/// Apply this to the run itself, not to the section's whole drop zone: the
/// unfiled saved rows sit *below* the folder groups in the same zone, and the
/// current tabs sit below the new-tab row, so only the run knows where its
/// first row would appear.
struct BrowserSidebarReorderSectionIndicatorModifier: ViewModifier {
    let section: BrowserSidebarReorderSection
    let state: BrowserSidebarReorderState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var indicator: BrowserSidebarReorderIndicator? {
        state.emptySectionIndicator(for: section)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let indicator {
                    BrowserSidebarReorderIndicatorLine(indicator: indicator)
                }
            }
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.dragSource,
                    reduceMotion: reduceMotion
                ),
                value: indicator
            )
    }

    /// An empty run inserts at index zero, so the line stands where its first
    /// row would: the top of a list, the leading edge of a grid.
    private var alignment: Alignment {
        section.flowsHorizontally ? .leading : .top
    }
}
