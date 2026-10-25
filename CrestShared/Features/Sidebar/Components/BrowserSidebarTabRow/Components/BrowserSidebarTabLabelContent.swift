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
    var titleOpacity = 1.0
    var iconOffset: CGFloat = 0
    @Environment(BrowserGitHubIntegration.self) private var github: BrowserGitHubIntegration?
    @Environment(\.browserInteractionCapabilities) private var capabilities
    /// The core whose page states name a tab whose page failed to load. None
    /// where no window supplies one, such as a drag preview.
    @Environment(CrestCore.self) private var core: CrestCore?
    let textScale: Double

    private var isLiveFolderItem: Bool { tab.folderID != nil && tab.folderID == github?.folderID }
    private var author: String? {
        github?.items.first(where: { $0.url.absoluteString == (tab.savedURL ?? tab.url) && isLiveFolderItem })?.author
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                Text(tab.shownTitle(in: isLoaded ? core?.state : nil))
                    .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let author, !author.isEmpty {
                    Text(verbatim: author).font(CrestTypography.compactMetadata).foregroundStyle(.secondary).lineLimit(
                        1)
                }
            }
            .browserTabResidency(isLoaded: isLoaded || isLiveFolderItem)
            .opacity(titleOpacity)
        } icon: {
            HStack(spacing: 3) {
                if isLiveFolderItem {
                    Image(systemName: "circle.fill")
                        .font(CrestTypography.compactMetadata)
                        .imageScale(.small)
                        .foregroundStyle(CrestBrandPalette.sage)
                        .frame(width: TabFaviconMetrics.defaultSize)
                } else {
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
                }
                if tab.placement == .saved, tab.isAwayFromSavedAddress, let restoreSavedLocation {
                    BrowserTabSavedLocationIndicator(restore: restoreSavedLocation)
                        .browserTabResidency(isLoaded: isLoaded)
                }
            }
            .offset(x: iconOffset)
        }
        .padding(.leading, leadingInset)
        .frame(maxWidth: .infinity, maxHeight: metrics.fillsRowHeight ? .infinity : nil, alignment: .leading)
        .contentShape(.rect)
    }
}
