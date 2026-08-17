import SwiftUI

struct MobileSpaceDownloadsButton: View {
    let downloads: [BrowserDownloadItem]
    let newDownloads: [BrowserDownloadItem]
    let badgeColor: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            MobileSpaceUtilityButtonLabel(systemImage: symbol)
        }
        .foregroundStyle(.primary)
        .symbolEffect(.bounce, value: reduceMotion ? nil : newDownloads.first?.id)
        .overlay(alignment: .topTrailing) {
            if !newDownloads.isEmpty {
                BrowserUtilityNotificationBadge(
                    count: newDownloads.count,
                    tint: badgeColor,
                    progress: BrowserDownloadNotificationPolicy.progress(
                        in: downloads
                    )
                )
                .offset(
                    x: BrowserUtilitySwitcherLayout.notificationBadgeOffset,
                    y: -BrowserUtilitySwitcherLayout.notificationBadgeOffset
                )
            }
        }
        .zIndex(newDownloads.isEmpty ? 0 : 1)
        .accessibilityLabel("Downloads")
        .accessibilityValue(
            BrowserChromeAccessibility.countValue(
                downloads.count,
                singular: "download",
                plural: "downloads"
            )
        )
        .accessibilityIdentifier("downloads-button")
    }

    private var symbol: String {
        if downloads.contains(where: { $0.state.needsAttention }) {
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
        if downloads.contains(where: { $0.state.isInProgress }) {
            return "arrow.down.circle"
        }
        return "arrow.down.circle.fill"
    }
}
