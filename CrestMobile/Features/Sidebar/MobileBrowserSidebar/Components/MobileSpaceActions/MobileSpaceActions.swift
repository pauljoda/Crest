import SwiftUI

struct MobileSpaceActions: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let mode: MobileBrowserSidebarMode
    let configuration: MobileSpaceActionsConfiguration

    var body: some View {
        HStack(spacing: 0) {
            MobileSpacePrivateBrowsingButton(
                isPrivateBrowsing: browser.isPrivateBrowsing,
                accentColor: selectedAccentColor,
                action: configuration.togglePrivateBrowsing
            )
            MobileSpaceArchiveButton(
                mode: mode,
                archivedTabCount: browser.selectedSpace?.archivedTabs.count ?? 0,
                commonListsAreExpanded: configuration.commonListsAreExpanded,
                downloads: downloads,
                newDownloads: newDownloads,
                badgeColor: downloadBadgeColor,
                showArchive: configuration.showArchive,
                toggleCommonLists: configuration.toggleCommonLists,
                recordCommonListsTriggerFrame: configuration.recordCommonListsTriggerFrame
            )
            if mode == .compactTabViewer {
                MobileSpaceDownloadsButton(
                    downloads: downloads,
                    newDownloads: newDownloads,
                    badgeColor: downloadBadgeColor,
                    action: configuration.showDownloads
                )
            }
            MobileSpaceSettingsButton(action: configuration.showSettings)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .controlSize(.large)
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 60)
    }

    private var downloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    private var newDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }

    private var selectedAccentColor: Color {
        browser.selectedSpace?.branding.colors.first?.color ?? .accentColor
    }

    private var downloadBadgeColor: Color {
        downloads.contains(where: { $0.state.needsAttention }) ? .red : selectedAccentColor
    }
}
