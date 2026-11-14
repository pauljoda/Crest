import SwiftUI

/// Shared tab rows under the group's header, their icons and titles one
/// folder step past the header's as a folder's tabs are; each member can be
/// dragged out.
struct BrowserSidebarSplitGroupRowContent: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    @Environment(\.sidebarLayerDepth) private var depth
    @Environment(\.sidebarRowContentIndent) private var folderIndent

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
            ForEach(configuration.shownMembers, id: \.id) { member in
                BrowserSidebarTabRow(tab: member, context: configuration.context, isSplitGroupMember: true)
                    .equatable()
                    .id(member.id)
            }
            .environment(\.sidebarRowContentIndent, folderIndent + BrowserFolderLayout.contentIndent)
        }
        .environment(\.sidebarLayerDepth, depth + 1)
        // The folder surface around the split pads its top and bottom.
        .padding(.horizontal, BrowserSidebarMetrics.containerPadding)
    }
}
