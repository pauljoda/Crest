import SwiftUI

struct BrowserRootShellControls: View {
    let model: BrowserRootModel
    @Binding var storedSidebarWidth: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        switch model.sidebarPresentation {
        case .collapsed:
            BrowserCollapsedSidebarRevealControl(
                capabilities: interactionCapabilities,
                showSidebar: presentFloatingSidebar
            )
            // The shared control keeps its capability-driven hover behavior for
            // every pointer shell. The Mac shell also listens through AppKit so
            // live WKWebView content cannot swallow the edge transition before
            // SwiftUI sees it.
            .overlay {
                if revealMetrics.revealsOnHover {
                    BrowserCollapsedSidebarHoverTracker(
                        onHoverChange: collapsedSidebarHoverChanged
                    )
                }
            }
        case .docked:
            BrowserSidebarResizeHandle(
                width: model.sidebarWidthBinding,
                onResizeEnded: commitSidebarWidth
            )
            .offset(
                x: BrowserChromeDirectionPolicy.leadingOffset(
                    model.sidebarWidth
                        - BrowserRootMetrics.sidebarResizeHandleOffset,
                    layoutDirection: layoutDirection
                )
            )
            .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
        case .floating:
            EmptyView()
        }
    }

    private var interactionCapabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var revealMetrics: BrowserCollapsedSidebarRevealMetrics {
        .resolve(interactionCapabilities)
    }

    private func collapsedSidebarHoverChanged(_ isHovering: Bool) {
        guard isHovering else { return }
        presentFloatingSidebar()
    }

    private func presentFloatingSidebar() {
        model.presentFloatingSidebar(reduceMotion: reduceMotion)
    }

    private func commitSidebarWidth(_ width: CGFloat) {
        guard let committedWidth = model.commitSidebarWidth(width) else { return }
        storedSidebarWidth = Double(committedWidth)
    }
}
