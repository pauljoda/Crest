import CoreGraphics

enum BrowserUtilitySwitcherLayout {
    static let destinations: [BrowserUtilitySurface] = [.archive, .history, .downloads]
    static let spacing: CGFloat = 0
    static let step: CGFloat = 64
    static let buttonSize = CrestLayout.glassIconButtonDiameter
    static let collapsedScale: CGFloat = 0.08
    static let destinationGap: CGFloat = 18
    static let staggerInterval = 0.045
    static let notificationBadgeMinimumSize: CGFloat = 16
    static let notificationBadgeHorizontalPadding: CGFloat = 4
    static let notificationBadgeOffset: CGFloat = 4

    static func verticalOffset(for index: Int, count: Int) -> CGFloat {
        (CGFloat(index) - CGFloat(count - 1) / 2) * step
    }

    static func expandedHeight(for count: Int) -> CGFloat {
        guard count > 1 else { return buttonSize }
        return buttonSize + CGFloat(count - 1) * step
    }

    static func expansionDelay(for index: Int) -> Double {
        Double(max(index, 0)) * staggerInterval
    }

    static func collapseDelay(for index: Int, count: Int) -> Double {
        Double(max(count - index - 1, 0)) * staggerInterval * 0.55
    }
}

enum BrowserDownloadNotificationPolicy {
    static func progress(in downloads: [BrowserDownloadItem]) -> Double? {
        downloads
            .filter { $0.state.isInProgress }
            .max { $0.createdAt < $1.createdAt }
            .map { BrowserDownloadProgressPolicy.normalized($0.progress) }
    }
}
