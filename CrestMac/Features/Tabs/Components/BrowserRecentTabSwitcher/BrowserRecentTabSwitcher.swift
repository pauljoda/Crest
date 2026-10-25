import SwiftUI

/// The active tabs a recent tab walk passes, from the one the window showed
/// when it started, as pictures of their pages in a row on the launcher's
/// glass in the middle of the window, a split as one tile, with the stop the
/// walk rests on picked out. It appears only once a walk lasts a moment.
struct BrowserRecentTabSwitcher: View {
    // MARK: - Static Variables

    /// The tiles the card shows before it scrolls.
    private static let visibleTileLimit = 5

    // MARK: - Variables

    let switcher: BrowserRecentTabSwitcherModel
    let browser: BrowserStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserCommandPaletteMetrics.cardCornerRadius, style: .continuous)
    }

    /// Each stop the walk passes that the Space still holds, with its place in
    /// the walk, the tabs it shows, and what a person chose for its split.
    private var tiles: [(index: Int, stop: RecentTabStop, members: [TabStateModel], split: SplitGroupState?)] {
        guard let space = browser.shownSpace else { return [] }
        return switcher.stops.enumerated().compactMap { index, stop in
            let members = stop.members.compactMap { space.tabs.model($0) }
            guard !members.isEmpty else { return nil }
            let split = stop.splitGroupID.map { id in space.splitGroups.first { $0.id == id } ?? .unchosen(id) }
            return (index, stop, members, split)
        }
    }

    /// The row's width at most, before a narrow window holds it in.
    private var rowWidth: CGFloat {
        let shown = CGFloat(min(tiles.count, Self.visibleTileLimit))
        return shown * BrowserRecentTabSwitcherTile.width
            + max(0, shown - 1) * BrowserCommandPaletteMetrics.resultRowSpacing
    }

    var body: some View {
        ZStack {
            if switcher.isRevealed, !tiles.isEmpty {
                card
                    .transition(
                        .scale(scale: BrowserCommandPaletteMetrics.morphContentScale).combined(with: .opacity))
            }
        }
        .padding(BrowserCommandPaletteMetrics.resultOuterPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(CrestMotion.feedbackPresentation.unlessReducingMotion(reduceMotion), value: switcher.isRevealed)
        .zIndex(BrowserRootMetrics.commandPaletteZIndex)
    }

    private var card: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: BrowserCommandPaletteMetrics.resultRowSpacing) {
                    ForEach(tiles, id: \.stop.tabID) { tile in
                        BrowserRecentTabSwitcherTile(
                            members: tile.members,
                            split: tile.split,
                            browser: browser,
                            previews: switcher.previews,
                            isSelected: tile.index == switcher.selectedIndex,
                            choose: { switcher.choose(tile.index) }
                        )
                        .id(tile.index)
                        // The walk holds the pointer's movement back from every
                        // view, its own included, and picks the tile it moves onto.
                        .onGeometryChange(for: CGRect.self) { geometry in
                            geometry.frame(in: .global)
                        } action: { frame in
                            switcher.place(tile.index, at: frame)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: rowWidth)
            .onChange(of: switcher.selectedIndex, initial: true) { _, index in
                proxy.scrollTo(index, anchor: .center)
            }
        }
        .padding(BrowserCommandPaletteMetrics.resultContentPadding)
        .modifier(BrowserCommandPaletteShellMaterial(shape: shape, reduceTransparency: reduceTransparency))
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recent Tabs"))
        .accessibilityIdentifier("recent-tab-switcher")
    }
}
