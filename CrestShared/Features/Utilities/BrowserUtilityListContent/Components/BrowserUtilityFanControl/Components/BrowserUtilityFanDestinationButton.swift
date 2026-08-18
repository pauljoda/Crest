import SwiftUI

struct BrowserUtilityFanDestinationButton: View {
    let surface: BrowserUtilitySurface
    let selectedSurface: BrowserUtilitySurface?
    let badgeColor: Color
    let downloads: [BrowserDownloadItem]
    let newDownloadCount: Int
    let select: (BrowserUtilitySurface) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            select(surface)
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(.primary)
                .symbolVariant(selectedSurface == surface ? .fill : .none)
                .symbolEffect(
                    .bounce,
                    value: reduceMotion ? 0 : newDownloadCount
                )
                .frame(
                    width: BrowserUtilitySwitcherLayout.buttonSize,
                    height: BrowserUtilitySwitcherLayout.buttonSize
                )
                .contentShape(.circle)
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .buttonStyle(
            GlassButtonStyle(
                selectedSurface == surface
                    ? .regular.tint(badgeColor)
                    : .regular
            )
        )
        .overlay(alignment: .topTrailing) {
            if surface == .downloads, newDownloadCount > 0 {
                BrowserUtilityNotificationBadge(
                    count: newDownloadCount,
                    tint: downloadBadgeColor,
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
        .zIndex(surface == .downloads ? 1 : 0)
        .help(Text(surface.title))
        .accessibilityLabel(Text(surface.title))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(selectedSurface == surface ? .isSelected : [])
        .accessibilityIdentifier(BrowserUtilityAccessibilityID.destination(surface))
    }

    private var symbol: String {
        guard surface == .downloads else { return surface.systemImage }
        if downloads.contains(where: { $0.state.needsAttention }) {
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
        if downloads.contains(where: { $0.state.isInProgress }) {
            return "arrow.down.circle"
        }
        return "arrow.down.circle.fill"
    }

    private var accessibilityValue: LocalizedStringResource {
        if selectedSurface == surface {
            return BrowserUtilityPresentation.selected
        }
        guard surface == .downloads else {
            return BrowserUtilityPresentation.notSelected
        }
        return BrowserUtilityPresentation.downloadCount(downloads.count)
    }

    private var downloadBadgeColor: Color {
        downloads.contains(where: { $0.state.needsAttention }) ? .red : badgeColor
    }
}

struct BrowserUtilityNotificationBadge: View {
    let count: Int
    let tint: Color
    let progress: Double?

    var body: some View {
        Text("\(min(count, 99))")
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .browserReadableForeground(over: tint)
            .padding(
                .horizontal,
                BrowserUtilitySwitcherLayout.notificationBadgeHorizontalPadding
            )
            .frame(
                minWidth: BrowserUtilitySwitcherLayout.notificationBadgeMinimumSize,
                minHeight: BrowserUtilitySwitcherLayout.notificationBadgeMinimumSize
            )
            .background(tint, in: .capsule)
            .overlay {
                if let progress {
                    Capsule()
                        .trim(
                            from: 0,
                            to: max(
                                BrowserDownloadProgressPolicy.normalized(progress),
                                0.04
                            )
                        )
                        .stroke(
                            .primary.opacity(0.72),
                            style: StrokeStyle(
                                lineWidth: 1.5,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .accessibilityHidden(true)
    }
}
