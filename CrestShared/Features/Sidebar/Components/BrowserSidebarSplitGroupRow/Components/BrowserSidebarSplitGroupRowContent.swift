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

            // Each member keeps its own identity: selecting one prepositions
            // the sidebar's scroll onto the row the page will zoom from, and a
            // group whose rows shared one identity would scroll to the wrong
            // place — or to nowhere at all.
            ForEach(configuration.members, id: \.id) { member in
                BrowserSidebarTabRow(tab: member, context: configuration.context, isSplitGroupMember: true)
                    .equatable()
                    .id(member.id)
            }
        }
        .padding(configuration.metrics.containerPadding)
    }
}
