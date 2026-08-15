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
                Text("\(min(newDownloads.count, 99))")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .browserReadableForeground(over: badgeColor)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(badgeColor, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
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

#Preview("Downloads Button", traits: .sizeThatFitsLayout) {
    MobileSpaceDownloadsButton(
        downloads: MobileSpaceActionsPreviewFixture.downloads,
        newDownloads: MobileSpaceActionsPreviewFixture.downloads,
        badgeColor: .indigo,
        action: {}
    )
    .buttonStyle(.plain)
    .padding()
}
