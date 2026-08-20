import SwiftUI

/// The one control both shells move between Spaces with.
///
/// The two shells reached the switcher differently enough that they kept two
/// of them, but the difference was never styling — it was arrangement, and
/// arrangement follows from what the shell's reader can aim at. So there is
/// one switcher whose layout `BrowserSidebarInteractionPolicy` picks from
/// `BrowserInteractionCapabilities`, and two shared arrangements underneath
/// it. Accessories are inputs the scrolling arrangement simply ignores.
struct BrowserSpaceSwitcher: View {
    let browser: BrowserStore

    /// Held directly rather than behind the sidebar's page seam, the way
    /// `BrowserSidebarUtilityCoordinator` holds it: the switcher issues no page
    /// commands, it only needs to know what the profile has downloaded.
    let downloadCenter: BrowserDownloadCenter
    let capabilities: BrowserInteractionCapabilities
    let selectSpace: (SpaceID) -> Void
    var accessories = BrowserSpaceSwitcherAccessories()

    var body: some View {
        switch BrowserSidebarInteractionPolicy.spaceSwitcherArrangement(
            capabilities
        ) {
        case .compactStrip:
            BrowserSpaceSwitcherCompactStrip(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                reorderState: browser.sidebarReorderState,
                metrics: metrics,
                selectSpace: selectSpace,
                accessories: accessories,
                downloads: downloads
            )
        case .scrollingSegments:
            BrowserSpaceSwitcherScrollingSegments(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                reorderState: browser.sidebarReorderState,
                metrics: metrics,
                selectSpace: selectSpace
            )
        }
    }

    /// Read only where an accessory is there to wear the badge, so a shell
    /// without one never touches the download center from here.
    private var downloads: BrowserSpaceSwitcherDownloads {
        guard accessories.commonLists != nil,
            let space = browser.selectedSpace
        else { return .none }
        return BrowserSpaceSwitcherDownloads(
            items: downloadCenter.items(for: space.profile.id),
            newItems: downloadCenter.unacknowledgedItems(for: space.profile.id),
            badgeColor: space.branding.colors.first?.color ?? .accentColor
        )
    }

    private var spaces: [BrowserSpace] {
        BrowserSidebarAccessPolicy.availableSpaces(in: browser)
    }

    private var selectedSpaceID: SpaceID {
        browser.session.selectedSpaceID
    }

    private var metrics: BrowserSpacePickerMetrics {
        BrowserSidebarInteractionPolicy.spacePickerMetrics(capabilities)
    }
}
