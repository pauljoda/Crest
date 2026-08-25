import Foundation

struct BrowserDownloadRowPresentation: Sendable {
    let bytesReceived: Int64
    let totalBytes: Int64?
    let progress: Double
    let bytesPerSecond: Double?
    let estimatedTimeRemaining: TimeInterval?
    let statusText: BrowserUtilityText
    let statusNeedsAttention: Bool
    let showsTransferMetrics: Bool
    let showsStatusAlongsideMetrics: Bool

    static func resolve(
        item: BrowserDownloadItem
    ) -> BrowserDownloadRowPresentation {
        let telemetry = item.telemetry
        let isActivelyDownloading =
            item.state == .downloading
            && !telemetry.isPaused
        let statusText: BrowserUtilityText
        if item.state == .downloading, telemetry.isPaused {
            statusText = .localized("Paused")
        } else if item.state == .finished {
            statusText = .localized("Completed")
        } else {
            statusText = item.state.utilityStatusText
        }
        let showsTransferMetrics =
            telemetry.bytesReceived > 0
            || telemetry.hasKnownTotal
            || item.state == .finished
        return BrowserDownloadRowPresentation(
            bytesReceived: telemetry.bytesReceived,
            totalBytes: telemetry.totalBytes,
            progress: BrowserDownloadProgressPolicy.normalized(item.progress),
            bytesPerSecond: isActivelyDownloading
                ? telemetry.bytesPerSecond
                : nil,
            estimatedTimeRemaining: isActivelyDownloading
                ? telemetry.estimatedTimeRemaining
                : nil,
            statusText: statusText,
            statusNeedsAttention: item.state.needsAttention,
            showsTransferMetrics: showsTransferMetrics,
            showsStatusAlongsideMetrics: showsTransferMetrics
                && !isActivelyDownloading
        )
    }

    var hasSecondaryTransferMetrics: Bool {
        bytesPerSecond != nil
            || estimatedTimeRemaining != nil
            || showsStatusAlongsideMetrics
    }
}

enum BrowserDownloadRowLayout: Equatable, Sendable {
    case singleLine
    case inline
    case stacked
}

enum BrowserDownloadRowLayoutPolicy {
    static let inlineMinimumWidth: CGFloat = 360

    static func resolve(
        availableWidth: CGFloat,
        usesAccessibilityTextSize: Bool,
        hasSecondaryMetrics: Bool,
        statusNeedsAttention: Bool
    ) -> BrowserDownloadRowLayout {
        guard hasSecondaryMetrics || statusNeedsAttention else {
            return .singleLine
        }
        guard !usesAccessibilityTextSize,
            !statusNeedsAttention,
            availableWidth >= inlineMinimumWidth
        else {
            return .stacked
        }
        return .inline
    }
}
