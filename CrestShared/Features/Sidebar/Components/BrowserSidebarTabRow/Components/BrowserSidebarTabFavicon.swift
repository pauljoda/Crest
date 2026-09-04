import SwiftUI

/// A tab row's favicon, in whatever column the shell reserves for it.
struct BrowserSidebarTabFavicon: View {
    let tab: BrowserTab
    let profileID: UUID
    let metrics: BrowserSidebarTabRowMetrics
    /// Whether the icon carries the row's selection, which is the one state
    /// that earns full-strength ink.
    var isProminent = false
    /// Whether the tab is still resident. The row's title carries the same
    /// treatment; the favicon applies its own so the side-panel badge can hang
    /// off the icon without inheriting it.
    var isLoaded = true
    /// The Space this row is drawn in, which is what a side panel is bound
    /// against. Supplied wherever the row can carry the badge; nil leaves the
    /// favicon unmarked.
    var sidePanelSpaceID: SpaceID?

    var body: some View {
        TabFaviconView(tab: tab, profileID: profileID)
            .browserTabResidency(isLoaded: isLoaded)
            // Outside the residency treatment above, and anchored to the
            // favicon's own box rather than to the column it may sit in: an
            // unloaded tab still holds its panel, and the mark saying so should
            // neither fade with the icon nor drift off its corner.
            .overlay(alignment: .bottomTrailing) {
                if let sidePanelSpaceID {
                    BrowserTabSidePanelBadge(
                        tabID: tab.id,
                        spaceID: sidePanelSpaceID
                    )
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
