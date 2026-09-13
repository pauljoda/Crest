import SwiftUI

/// Shared tab rows inside the group's frame; each member can be dragged out.
struct BrowserSidebarSplitGroupRowContent: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    var body: some View {
        VStack(spacing: configuration.metrics.memberSpacing) {
            BrowserSidebarSplitGroupHeader(
                configuration: configuration,
                interaction: interaction
            )

            ForEach(configuration.members) { member in
                BrowserSidebarTabRow(
                    tab: member,
                    spaceID: configuration.spaceID,
                    profileID: configuration.profileID,
                    isSelected: configuration.isFocused(member),
                    canClose: configuration.canClose,
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess,
                    capabilities: configuration.capabilities,
                    isLoaded: configuration.isLoaded(member.id),
                    unload: configuration.unload,
                    pullNewIcon: configuration.pullNewIcon(for: member),
                    restoreSavedLocation: configuration.restoreSavedLocation(
                        for: member
                    ),
                    promotionNamespace: configuration.promotionNamespace,
                    isSplitGroupMember: true,
                    select: configuration.select
                )
                // Each member keeps its own identity: selecting one
                // prepositions the sidebar's scroll onto the row the page will
                // zoom from, and a group whose rows shared one identity would
                // scroll to the wrong place — or to nowhere at all.
                .id(member.id)
            }
        }
        .padding(configuration.metrics.containerPadding)
    }
}
