import SwiftUI

/// A tab row's favicon, in whatever column the shell reserves for it.
struct BrowserSidebarTabFavicon: View {
    let tab: BrowserTab
    let profileID: UUID
    let metrics: BrowserSidebarTabRowMetrics
    /// Whether the icon carries the row's selection, which is the one state
    /// that earns full-strength ink.
    var isProminent = false

    var body: some View {
        TabFaviconView(tab: tab, profileID: profileID)
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
