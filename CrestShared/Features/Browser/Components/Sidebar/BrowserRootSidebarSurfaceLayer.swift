import SwiftUI

struct BrowserRootSidebarSurfaceLayer<Content: View>: View {
    // MARK: - Variables

    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let edge: HorizontalEdge
    let space: SpaceModel?
    let reduceTransparency: Bool
    let spaces: [SpaceModel]
    /// Whether the pointer brought a floating sidebar out by reaching the
    /// window edge.
    let isRevealedByPointer: Bool
    /// Whether the sidebar's edge is being dragged to resize it, which keeps
    /// a floating sidebar out until the drag lets go.
    let isResizing: Bool
    let hoverChanged: @MainActor @Sendable (Bool) -> Void
    let content: Content

    @Environment(\.layoutDirection) private var layoutDirection

    // MARK: - Initializers

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        edge: HorizontalEdge = .leading,
        space: SpaceModel?,
        reduceTransparency: Bool,
        spaces: [SpaceModel] = [],
        isRevealedByPointer: Bool = false,
        isResizing: Bool = false,
        hoverChanged: @escaping @MainActor @Sendable (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.edge = edge
        self.space = space
        self.reduceTransparency = reduceTransparency
        self.spaces = spaces
        self.isRevealedByPointer = isRevealedByPointer
        self.isResizing = isResizing
        self.hoverChanged = hoverChanged
        self.content = content()
    }

    // MARK: - Actions - Presentation

    var body: some View {
        cardSurface
            .padding(surfaceInset)
            .frame(width: surfaceRegionWidth)
            .frame(maxHeight: .infinity)
            #if os(macOS)
                .background {
                    // The gap around a floating card stands over the window's
                    // frame, and moves the window as the frame does.
                    if usesFloatingCardAppearance, presentation.showsSidebar {
                        BrowserWindowTitleBarSurface().accessibilityHidden(true)
                    }
                }
            #endif
            .contentShape(.interaction, .rect)
            #if os(macOS)
                .overlay {
                    // A hidden sidebar tracks nothing, and its tracker would
                    // stay over the page it slid away from, where it would
                    // take the page's cursor updates.
                    if presentation.showsSidebar {
                        // A floating card keeps its hover over a margin of the
                        // page beside it. The tracker never takes hits, so the
                        // page still gets every click and scroll there.
                        BrowserSidebarHoverTracker(
                            isRevealedByPointer: isRevealedByPointer,
                            isResizing: isResizing,
                            exitMargin: presentation.exitMargin,
                            exitEdge: pageEdge,
                            onHoverChange: hoverChanged
                        )
                        .padding(pageEdge == .leading ? .leading : .trailing, -presentation.exitMargin)
                        .accessibilityHidden(true)
                    }
                }
            #else
                .onHover(perform: hoverChanged)
            #endif
            .offset(x: hiddenOffset)
            .allowsHitTesting(presentation.showsSidebar)
            .accessibilityHidden(!presentation.showsSidebar)
            .zIndex(
                presentation == .floating
                    ? BrowserRootMetrics.floatingSidebarZIndex
                    : 0
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
    }

    private var cardSurface: some View {
        content
            // The column's own layout settles at once when the sidebar
            // changes place, and the column moves as one piece with the
            // surface around it: its rows, header and native Space pages
            // take the surface's transition rather than standing still
            // while the card slides in around them.
            .animation(nil, value: presentation)
            .geometryGroup()
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background {
                if usesFloatingCardAppearance {
                    SpaceBackdropBlend(spaces: spaces, selectedSpace: space) {
                        BrowserFloatingSidebarCardBackground(space: $0)
                    }
                }
            }
            .compositingGroup()
            // A docked sidebar's list runs on under the bottom safe area, into
            // the display's corner, as the page beside it does; a floating
            // card keeps to its rounded shape.
            .mask {
                shape.ignoresSafeArea(.container, edges: usesFloatingCardAppearance ? [] : .bottom)
            }
            .overlay {
                shape
                    .strokeBorder(
                        .primary.opacity(
                            usesFloatingCardAppearance
                                ? BrowserRootMetrics.floatingSidebarBorderOpacity
                                : 0
                        ),
                        lineWidth: BrowserRootMetrics.floatingSidebarBorderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    reduceTransparency || !usesFloatingCardAppearance || !presentation.showsSidebar
                        ? 0
                        : BrowserRootMetrics.floatingSidebarShadowOpacity
                ),
                radius: BrowserRootMetrics.floatingSidebarShadowRadius,
                x: BrowserRootMetrics.floatingSidebarShadowOffset,
                y: BrowserRootMetrics.floatingSidebarShadowOffset
            )
            .contentShape(.interaction, shape)
    }

    private var usesFloatingCardAppearance: Bool {
        presentation != .docked
    }

    private var surfaceInset: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentation.floatingCardInset
            : 0
    }

    private var surfaceCornerRadius: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentation.floatingCardCornerRadius
            : 0
    }

    private var surfaceRegionWidth: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentation.floatingHoverRegionWidth(
                sidebarWidth: width
            )
            : width
    }

    /// The side of the sidebar the page lies on.
    private var pageEdge: HorizontalEdge {
        edge == .leading ? .trailing : .leading
    }

    private var hiddenOffset: CGFloat {
        guard presentation == .collapsed else { return 0 }
        return layoutDirection.leadingOffset(edge == .leading ? -surfaceRegionWidth : surfaceRegionWidth)
    }
}
