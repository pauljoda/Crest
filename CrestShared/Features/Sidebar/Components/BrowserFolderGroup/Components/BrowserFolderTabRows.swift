import SwiftUI

/// What a collapsed folder still shows: the one row it kept on screen, the row
/// of its own list that holds the tab it kept while that tab holds a page.
///
/// It reads the folder's list only while a tab is kept, so a folder that
/// collapses over nothing redraws only its header.
struct BrowserFolderKeptRow: View {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    var body: some View {
        if let item = configuration.keptCollapsedItem(for: interaction.collapsedTabVisibility.wrappedValue) {
            BrowserSidebarListRow(item: item, context: configuration.context)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }
}

/// Where an open, empty folder's insertion line stands.
///
/// It costs nothing at rest. The run is already reachable without a band of
/// its own — the folder group's section zone spans the header, which is what
/// lets a drop land in an open folder that has no rows to aim at — so this
/// is only ever the line's canvas, never the target, and it opens only while
/// there is a line to hold.
struct BrowserFolderEmptyRunBand: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }

    private var height: CGFloat {
        let state = sidebarInteraction.sidebarReorderState
        let section = BrowserSidebarReorderSection.tabs(
            placement: configuration.folder.location, folderID: configuration.folder.id)
        guard !state.layout.isActive, state.emptySectionIndicator(for: section) != nil else { return 0 }
        return BrowserSidebarInteractionPolicy.tabListMetrics(configuration.capabilities).sectionEndBandHeight
    }
}
