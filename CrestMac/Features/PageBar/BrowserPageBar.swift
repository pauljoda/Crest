import SwiftUI

/// The bar a page carries: back and forward, its address field with the
/// page's pinned extensions after it, and whatever the window puts at its
/// ends. A Quick Window's toolbar is one, and so is the bar along the top of
/// each page's card in a window with the address bar on top; each window
/// brings its own field, since only a Quick Window edits its address in place.
struct BrowserPageBar<Field: View, Extensions: View, LeadingAccessory: View, TrailingAccessory: View>: View {
    // MARK: - Variables

    let metrics: BrowserPageBarMetrics
    /// The room the bar leaves at its leading edge for the window's own
    /// buttons where they stand over it, beyond the metrics' padding. AppKit
    /// keeps the buttons in the window's leading corner, which is the top
    /// right in a right-to-left layout, so the room is leading either way.
    let windowControlsClearance: CGFloat
    /// The page back and forward act on.
    let port: BrowserSidebarNavigationPort
    /// The look of the Space the page belongs to.
    let branding: SpaceBranding?
    private let field: Field
    private let extensions: Extensions
    private let leadingAccessory: LeadingAccessory
    private let trailingAccessory: TrailingAccessory

    // MARK: - Initializers

    init(
        metrics: BrowserPageBarMetrics,
        windowControlsClearance: CGFloat = 0,
        port: BrowserSidebarNavigationPort,
        branding: SpaceBranding?,
        @ViewBuilder field: () -> Field,
        @ViewBuilder extensions: () -> Extensions = { EmptyView() },
        @ViewBuilder leadingAccessory: () -> LeadingAccessory = { EmptyView() },
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = { EmptyView() }
    ) {
        self.metrics = metrics
        self.windowControlsClearance = windowControlsClearance
        self.port = port
        self.branding = branding
        self.field = field()
        self.extensions = extensions()
        self.leadingAccessory = leadingAccessory()
        self.trailingAccessory = trailingAccessory()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        HStack(spacing: metrics.spacing) {
            leadingAccessory
            BrowserPageBarNavigation(port: port, branding: branding)
            BrowserPageBarFieldLayout(
                fieldMinimumWidth: metrics.fieldMinimumWidth,
                widthBeforeExtensions: metrics.widthBeforeExtensions,
                spacing: metrics.spacing
            ) {
                field
                    // The field sits under the title bar. A drag across it
                    // selects its text, while the strip around it still moves
                    // the window.
                    .background {
                        BrowserWindowTitleBarControlArea()
                            .accessibilityHidden(true)
                    }
                extensions
            }
            .layoutPriority(1)
            trailingAccessory
                .layoutPriority(1)
        }
        .padding(.leading, metrics.leadingPadding + windowControlsClearance)
        .padding(.trailing, metrics.trailingPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.height)
    }
}
