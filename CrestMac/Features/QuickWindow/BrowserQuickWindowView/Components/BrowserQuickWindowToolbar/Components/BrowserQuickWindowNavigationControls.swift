import SwiftUI

/// Back and forward for the Quick Window's page: the same controls, history
/// menus and shortcuts the sidebar's strip shows for a tab.
struct BrowserQuickWindowNavigationControls: View {
    // MARK: - Static Variables

    private static let metrics = BrowserSidebarNavigationControlMetrics.pointer

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
