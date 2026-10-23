import SwiftUI

/// The same title and favicon in the list and in the travelling component.
/// Keeping the native Label layout also preserves its baseline and icon gap.
struct BrowserSidebarTabLabelContent: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let metrics: BrowserSidebarTabRowMetrics
    var leadingInset: CGFloat = 0
    var restoreSavedLocation: (() -> Void)?
    var faviconPrimaryClick: (() -> Void)?
    var beginRenaming: (() -> Void)?
    var titleOpacity = 1.0
    var iconOffset: CGFloat = 0
    @Environment(\.browserInteractionCapabilities) private var capabilities
    /// The core whose page states name a tab whose page failed to load. None
    /// where no window supplies one, such as a drag preview.
    @Environment(CrestCore.self) private var core: CrestCore?
    let textScale: Double

    var body: some View {
        Label {
            Text(tab.shownTitle(in: isLoaded ? core?.state : nil))
                .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .browserTabResidency(isLoaded: isLoaded)
                .opacity(titleOpacity)
                #if os(macOS)
                    // Stretches the hit area over the strip after the favicon, so the
                    // title is a rename target beyond the glyphs of short text.
                    .frame(maxWidth: beginRenaming == nil ? nil : .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { beginRenaming?() },
                        including: beginRenaming == nil ? .none : .all
                    )
                #endif
        } icon: {
            HStack(spacing: 3) {
                BrowserSidebarTabFaviconContent(
                    tab: tab, favicons: favicons, profileID: profileID, metrics: metrics,
                    isProminent: isSelected, isLoaded: isLoaded,
                    iconScale: textScale
                )
                #if os(macOS)
                    .simultaneousGesture(
                        TapGesture().onEnded { faviconPrimaryClick?() },
                        including: faviconPrimaryClick == nil ? .none : .all
                    )
                #endif
                if tab.placement == .saved, tab.isAwayFromSavedAddress, let restoreSavedLocation {
                    BrowserTabSavedLocationIndicator(restore: restoreSavedLocation)
                        .browserTabResidency(isLoaded: isLoaded)
                }
            }
            #if os(macOS)
                // With a rename trigger, the title's double-click renames, so only the
                // favicon and its indicator keep the saved-location restore.
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard tab.placement == .saved else { return }
                        restoreSavedLocation?()
                    },
                    including: beginRenaming == nil ? .none : .all
                )
            #endif
            .offset(x: iconOffset)
        }
        .padding(.leading, leadingInset)
        .frame(maxWidth: .infinity, maxHeight: metrics.fillsRowHeight ? .infinity : nil, alignment: .leading)
        .contentShape(.rect)
    }
}
