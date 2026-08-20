import SwiftUI

/// One direction of page history: the chevron, and the stack behind it.
struct BrowserSidebarNavigationHistoryControl: View {
    let direction: BrowserSidebarNavigationControl
    let port: BrowserSidebarNavigationPort
    let metrics: BrowserSidebarNavigationControlMetrics

    var body: some View {
        Button(action: navigate) {
            Image(systemName: direction.systemImage)
                .font(metrics.historySymbolFont)
        }
        .accessibilityLabel(Text(direction.accessibilityLabel))
        .accessibilityIdentifier(direction.accessibilityIdentifier)
        .disabled(!isAvailable)
        .help(direction.tooltip)
        .contextMenu {
            BrowserNavigationHistoryMenu(
                items: history,
                emptyTitle: direction.emptyHistoryTitle,
                action: navigate(to:)
            )
            .tint(.primary)
        }
    }

    private var isAvailable: Bool {
        switch direction {
        case .back: port.canGoBack()
        case .forward: port.canGoForward()
        }
    }

    private var history: [BrowserNavigationHistoryItem] {
        switch direction {
        case .back: port.backHistory()
        case .forward: port.forwardHistory()
        }
    }

    private func navigate() {
        switch direction {
        case .back: port.goBack()
        case .forward: port.goForward()
        }
    }

    private func navigate(to item: BrowserNavigationHistoryItem) {
        switch direction {
        case .back: port.goBackToHistoryItem(item)
        case .forward: port.goForwardToHistoryItem(item)
        }
    }
}
