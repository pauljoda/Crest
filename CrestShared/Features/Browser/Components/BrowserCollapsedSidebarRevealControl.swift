import SwiftUI

/// The invisible strip along the leading edge that brings a collapsed sidebar
/// back.
///
/// It is a button in every shell, because the reveal has to be reachable by
/// something other than the gesture that usually performs it — a pointer that
/// never rests on the edge, Full Keyboard Access, VoiceOver. What each shell's
/// inputs add on top of the button is capability-driven: a resting pointer
/// where there is one, an inward swipe where there are fingers.
struct BrowserCollapsedSidebarRevealControl: View {
    let capabilities: BrowserInteractionCapabilities
    let showSidebar: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    private var metrics: BrowserCollapsedSidebarRevealMetrics {
        .resolve(capabilities)
    }

    var body: some View {
        Button(action: showSidebar) {
            Color.clear
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Sidebar Temporarily")
        .accessibilityIdentifier("show-sidebar")
        .help(hint)
        .onHover { isHovering in
            guard metrics.revealsOnHover, isHovering else { return }
            showSidebar()
        }
        .frame(width: metrics.width)
        .frame(maxHeight: .infinity)
        // Simultaneous rather than exclusive: the button already claims the
        // press, and a swipe that has to wait for it to fail would have to
        // travel the width of the strip before it started.
        .simultaneousGesture(
            DragGesture(minimumDistance: metrics.swipeDistance ?? 0)
                .onEnded(revealIfSwipedInward),
            isEnabled: metrics.swipeDistance != nil
        )
    }

    /// What the strip tells someone who stops on it: whichever input this shell
    /// actually answers.
    private var hint: LocalizedStringKey {
        metrics.swipeDistance == nil
            ? "Move the pointer to the leading edge to preview the sidebar"
            : "You can also swipe inward from the leading edge"
    }

    private func revealIfSwipedInward(_ value: DragGesture.Value) {
        guard
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                value.translation,
                layoutDirection: layoutDirection
            )
        else { return }
        showSidebar()
    }
}
