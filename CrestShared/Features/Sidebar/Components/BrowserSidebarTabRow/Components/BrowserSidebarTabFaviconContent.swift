import SwiftUI

/// A tab row's favicon, in whatever column the shell reserves for it.
struct BrowserSidebarTabFaviconContent: View {
    let tab: BrowserTab
    let profileID: UUID
    let metrics: BrowserSidebarTabRowMetrics
    /// Whether the icon carries the row's selection, which is the one state
    /// that earns full-strength ink.
    var isProminent = false
    var isLoaded = true
    var sidePanelSpaceID: SpaceID?
    let iconScale: Double

    var body: some View {
        TabFaviconView(
            tab: tab, profileID: profileID,
            size: TabFaviconMetrics.defaultSize * BrowserSidebarDensityPolicy.scale(iconScale)
        )
        .browserTabResidency(isLoaded: isLoaded)
        .overlay(alignment: .bottomTrailing) {
            if let sidePanelSpaceID {
                BrowserTabSidePanelBadge(
                    tabID: tab.id, spaceID: sidePanelSpaceID,
                    scale: BrowserSidebarDensityPolicy.scale(iconScale))
            }
        }
        .modifier(BrowserSidebarTabFaviconColumn(slot: metrics.faviconSlot))
        .foregroundStyle(isProminent ? .primary : .secondary)
    }
}

/// Holds the favicon in a fixed column and sizes the symbol a tab falls back
/// to, where the shell asks for one.
private struct BrowserSidebarTabFaviconColumn: ViewModifier {
    let slot: BrowserSidebarTabFaviconSlot?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let slot {
            content
                .font(.system(size: slot.glyphSize, weight: slot.glyphWeight))
                .frame(width: slot.width)
        } else {
            content
        }
    }
}

#if DEBUG
    #Preview("Tab icon") {
        let configuration = BrowserSidebarTabRowPreviewFixture.configuration()
        BrowserSidebarTabFaviconContent(
            tab: configuration.tab, profileID: configuration.profileID, metrics: configuration.metrics,
            isProminent: true, iconScale: 1
        ).padding()
    }
#endif
