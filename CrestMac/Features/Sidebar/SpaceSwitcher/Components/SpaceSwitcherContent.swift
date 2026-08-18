import SwiftUI

struct SpaceSwitcherContent: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void
    let sidebarToggleAction: BrowserSidebarToggleAction
    let toggleSidebar: () -> Void
    let commonListsAreExpanded: Bool
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                Button(
                    sidebarToggleAction.title,
                    systemImage: "sidebar.left",
                    action: toggleSidebar
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(
                    width: BrowserSpaceSwitcherLayout.utilityButtonSize,
                    height: BrowserSpaceSwitcherLayout.utilityButtonSize
                )
                .accessibilityIdentifier("browser-sidebar-toggle")
                .help(sidebarToggleAction.title)

                Spacer()
                SpaceSwitcherCommonListsButton(
                    isExpanded: commonListsAreExpanded,
                    downloads: selectedDownloads,
                    newDownloads: newDownloads,
                    badgeColor: selectedAccentColor,
                    action: toggleCommonLists,
                    recordFrame: recordCommonListsTriggerFrame
                )
            }
            DesktopSpaceSelectionControl(
                spaces: BrowserSidebarAccessPolicy.availableSpaces(in: browser),
                selectedSpaceID: browser.session.selectedSpaceID,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                selectSpace: selectSpace
            )
        }
    }

    private var selectedDownloads: [BrowserDownloadItem] {
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
}
