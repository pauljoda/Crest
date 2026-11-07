import SwiftUI

struct BrowserRootShellControls: View {
    // MARK: - Variables

    let model: BrowserRootModel
    @Binding var storedSidebarWidth: Double
    var sidebarEdge: HorizontalEdge = .leading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    // MARK: - Actions - Presentation

    @ViewBuilder
    var body: some View {
        switch model.sidebarPresentation.kind {
        case .collapsed:
            BrowserCollapsedSidebarRevealControl(
                capabilities: interactionCapabilities,
                showSidebar: presentFloatingSidebar,
                revealsOnHover: false,
                edge: sidebarEdge,
                isWindowFocused: model.isWindowFocused,
                pointerWidth: revealPointerWidth
            )
            // Shows the strip while its width changes in Settings.
            .background { BrowserSidebarRevealZonePreview() }
            // The Mac shell reveals for a resting pointer through AppKit alone.
            // Live WKWebView content cannot swallow the edge transition before
            // AppKit sees it, and AppKit reports only in the key window. The
            // strip's own hover reads focus a moment late, and reopened the
            // sidebar under a pointer parked at the screen edge just after the
            // window lost focus, where nothing would close it again.
            .overlay {
                if revealMetrics.revealsOnHover {
                    BrowserCollapsedSidebarHoverTracker(
                        onHoverChange: collapsedSidebarHoverChanged
                    )
                }
            }
        case .docked:
            resizeHandle(cardInset: 0)
                .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
        case .floating:
            // The card's own edge resizes the width the docked sidebar keeps.
            // The card takes the hits around itself, so the handle rides above it.
            resizeHandle(cardInset: BrowserSidebarPresentation.floatingCardInset)
                .zIndex(BrowserRootMetrics.floatingSidebarResizeControlZIndex)
        }
    }

    /// The handle that resizes the sidebar, at its edge beside the page past
    /// `cardInset`, on whichever side the sidebar is.
    private func resizeHandle(cardInset: CGFloat) -> some View {
        BrowserSidebarResizeHandle(
            width: model.sidebarWidthBinding,
            onResizeEnded: commitSidebarWidth,
            edge: sidebarEdge
        )
        .offset(
            x: layoutDirection.leadingOffset(
                (cardInset + model.sidebarWidth - BrowserRootMetrics.sidebarResizeHandleOffset)
                    * (sidebarEdge == .leading ? 1 : -1)))
    }

    /// How wide the collapsed sidebar's reveal strip is, as Settings sets it.
    private var revealPointerWidth: CGFloat {
        SidebarRevealWidthPreference.width(BrowserDeviceAppearanceStore.shared.sidebarRevealWidth)
    }

    private var interactionCapabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var revealMetrics: BrowserCollapsedSidebarRevealMetrics {
        .resolve(interactionCapabilities)
    }

    // MARK: - Actions - Sidebar

    private func collapsedSidebarHoverChanged(_ isHovering: Bool) {
        guard isHovering, model.isWindowFocused else { return }
        model.revealFloatingSidebarFromPointer(reduceMotion: reduceMotion)
    }

    private func presentFloatingSidebar() {
        model.presentFloatingSidebar(reduceMotion: reduceMotion)
    }

    private func commitSidebarWidth(_ width: CGFloat) {
        guard let committedWidth = model.commitSidebarWidth(width) else { return }
        storedSidebarWidth = Double(committedWidth)
    }
}
