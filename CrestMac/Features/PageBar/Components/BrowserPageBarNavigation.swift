import SwiftUI

/// Back and forward for a page bar's page: the same controls, history menus
/// and shortcuts the sidebar's strip shows for a tab, drawn side by side
/// beside the address field.
///
/// They stand on the Space's colors, as the sidebar's strip does, so they
/// draw in the scheme the Space's text reads in rather than the window's: a
/// dark Space in a light window would otherwise hide them.
struct BrowserPageBarNavigation: View {
    // MARK: - Static Variables

    private static let metrics = BrowserSidebarNavigationControlMetrics.pageBar

    // MARK: - Variables

    /// The page the controls act on, read at call time.
    let port: BrowserSidebarNavigationPort
    /// The look of the Space the page belongs to.
    let branding: SpaceBranding?

    var body: some View {
        HStack(spacing: Self.metrics.controlSpacing) {
            BrowserSidebarNavigationHistoryControl(direction: .back, port: port, metrics: Self.metrics)
            BrowserSidebarNavigationHistoryControl(direction: .forward, port: port, metrics: Self.metrics)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle(controlSize: Self.metrics.controlSize))
        .modifier(SpaceColorScheme(branding: branding))
    }
}
