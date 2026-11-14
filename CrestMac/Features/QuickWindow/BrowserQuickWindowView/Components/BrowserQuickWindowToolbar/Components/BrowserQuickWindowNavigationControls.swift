import SwiftUI

/// Back and forward for the Quick Window's page: the same controls, history
/// menus and shortcuts the sidebar's strip shows for a tab.
///
/// They stand on the Space's colors, as the sidebar's strip does, so they
/// draw in the scheme the Space's text reads in rather than the window's: a
/// dark Space in a light window would otherwise hide them.
struct BrowserQuickWindowNavigationControls: View {
    // MARK: - Static Variables

    private static let metrics = BrowserSidebarNavigationControlMetrics.quickWindow

    // MARK: - Variables

    let model: BrowserQuickWindowModel

    @Environment(\.browserMacWindows) private var windows

    var body: some View {
        HStack(spacing: Self.metrics.controlSpacing) {
            BrowserSidebarNavigationHistoryControl(direction: .back, port: port, metrics: Self.metrics)
            BrowserSidebarNavigationHistoryControl(direction: .forward, port: port, metrics: Self.metrics)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle(controlSize: Self.metrics.controlSize))
        .modifier(SpaceColorScheme(branding: model.spaceModel?.settings.look))
    }

    private var port: BrowserSidebarNavigationPort {
        BrowserSidebarNavigationPort(
            page: { [model] in model.page },
            recordActivity: { [model] in model.recordUserActivity() },
            showHistory: showHistory
        )
    }

    // MARK: - Actions - History

    /// A Quick Window keeps no History of its own: the browser window's opens.
    private func showHistory() {
        windows?.contextBringingBrowserWindowForward()?.chrome.presentUtility(.history)
    }
}
