import SwiftUI

/// The switcher's trailing accessory: one control for the archive, history,
/// and downloads lists, badged when downloads have finished unseen.
struct BrowserSpaceSwitcherCommonListsButton: View {
    let isExpanded: Bool
    let downloads: [BrowserDownloadItem]
    let newDownloads: [BrowserDownloadItem]
    let badgeColor: Color
    let action: () -> Void
    let recordFrame: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button("Common Lists", systemImage: "archivebox", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: BrowserSpaceSwitcherLayout.utilityButtonSize,
                height: BrowserSpaceSwitcherLayout.utilityButtonSize
            )
            .symbolVariant(isExpanded ? .fill : .none)
            .symbolEffect(
                .bounce,
                value: reduceMotion ? nil : newDownloads.first?.id
            )
            .overlay(alignment: .topTrailing) {
                if !newDownloads.isEmpty {
                    BrowserUtilityNotificationBadge(
                        count: newDownloads.count,
                        tint: downloads.contains(where: { $0.state.needsAttention })
                            ? .red
                            : badgeColor,
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
            .help("Archive, History, and Downloads")
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("common-lists-button")
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                recordFrame(frame)
            }
    }

    private var accessibilityValue: String {
        let state = isExpanded ? "Expanded" : "Collapsed"
        guard !newDownloads.isEmpty else { return state }
        return "\(state), \(newDownloads.count) new downloads"
    }
}
