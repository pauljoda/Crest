import SwiftUI

struct MobileSpaceArchiveButton: View {
    let mode: MobileBrowserSidebarMode
    let archivedTabCount: Int
    let commonListsAreExpanded: Bool
    let downloads: [BrowserDownloadItem]
    let newDownloads: [BrowserDownloadItem]
    let badgeColor: Color
    let showArchive: () -> Void
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(
            action: mode == .regularSidebar ? toggleCommonLists : showArchive
        ) {
            MobileSpaceUtilityButtonLabel(systemImage: "archivebox")
        }
        .symbolVariant(
            mode == .regularSidebar && commonListsAreExpanded ? .fill : .none
        )
        .foregroundStyle(.primary)
        .symbolEffect(
            .bounce,
            value: reduceMotion ? nil : regularSidebarNotificationID
        )
        .overlay(alignment: .topTrailing) {
            if mode == .regularSidebar, !newDownloads.isEmpty {
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
        .accessibilityLabel(
            mode == .regularSidebar ? "Archive, History, and Downloads" : "Archive"
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(
            mode == .regularSidebar ? "common-lists-button" : "archive-button"
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            recordCommonListsTriggerFrame(frame)
        }
    }

    private var accessibilityValue: String {
        if mode == .regularSidebar {
            let state = commonListsAreExpanded ? "Expanded" : "Collapsed"
            guard !newDownloads.isEmpty else { return state }
            return "\(state), \(newDownloads.count) new downloads"
        }
        return BrowserChromeAccessibility.countValue(
            archivedTabCount,
            singular: "archived tab",
            plural: "archived tabs"
        )
    }

    private var regularSidebarNotificationID: UUID? {
        mode == .regularSidebar ? newDownloads.first?.id : nil
    }
}
