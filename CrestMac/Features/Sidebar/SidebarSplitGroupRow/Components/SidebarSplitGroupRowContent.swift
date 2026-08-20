import SwiftUI

/// The group's affordance and its members, stacked inside the container.
///
/// A member is a `BrowserSidebarTabRow` — the same view the tab list draws
/// everywhere else, at the same height, with the same favicon, title, hover,
/// trailing control, and selection accent. Only two things change, both of
/// them the container's doing: the row drops its edge inset because the
/// container's padding already places it, and it stops being a reorder source
/// because the container drags the whole run as one block.
struct SidebarSplitGroupRowContent: View {
    let configuration: SidebarSplitGroupRowConfiguration

    var body: some View {
        VStack(spacing: 0) {
            SidebarSplitGroupHeader(memberCount: configuration.members.count)

            ForEach(configuration.members) { member in
                BrowserSidebarTabRow(
                    tab: member,
                    spaceID: configuration.spaceID,
                    profileID: configuration.profileID,
                    isSelected: configuration.isFocused(member),
                    canClose: configuration.canClose,
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess,
                    capabilities: BrowserInteractionCapabilities(),
                    isLoaded: configuration.isLoaded(member.id),
                    unload: configuration.unload,
                    pullNewIcon: configuration.pullNewIcon(for: member),
                    restoreSavedLocation: configuration.restoreSavedLocation(
                        for: member
                    ),
                    isSplitGroupMember: true,
                    isReorderSource: false,
                    select: activate
                )
            }
        }
        .padding(SidebarSplitGroupRowMetrics.containerPadding)
    }

    /// Selection and presentation in the one order that works: the page a
    /// shell brings on screen is whichever one the session now points at.
    private func activate(_ tabID: TabID) {
        BrowserTabActivationPolicy.activate(
            tabID,
            selectTab: configuration.browser.selectTab,
            presentPage: configuration.presentSelectedPage
        )
    }
}
