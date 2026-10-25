import SwiftUI

/// One stop of a recent tab walk, picked out as the launcher picks out a
/// result: a tab's page over its icon and title, or a split's pages side by
/// side, as the window shows them, over the split's icon and title. Until a
/// page's picture arrives, or when a tab pictures no page, its icon stands in.
struct BrowserRecentTabSwitcherTile: View {
    // MARK: - Static Variables

    private static let previewWidth: CGFloat = 184
    private static let previewHeight: CGFloat = 115
    private static let placeholderFaviconSize: CGFloat = 32
    private static let splitPlaceholderFaviconSize: CGFloat = 24

    /// The tile's width on the switcher, its picture and the launcher row's padding.
    static var width: CGFloat { previewWidth + BrowserCommandPaletteMetrics.rowHorizontalPadding * 2 }

    /// The width a picture is asked for at: twice the tile's, so it stays sharp
    /// on a Retina display whichever engine draws it.
    static var previewCaptureWidth: CGFloat { previewWidth * 2 }

    // MARK: - Variables

    /// The tab the stop shows, or the members of its split in the sidebar's order.
    let members: [TabStateModel]
    /// What a person chose for the split the members show, or nil for one tab.
    let split: SplitGroupState?
    let browser: BrowserStore
    let previews: [UUID: BrowserPageSnapshotImage]
    let isSelected: Bool
    /// Ends the walk on this stop.
    let choose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        split?.shownTitle ?? members.first.map { $0.shownTitle(in: browser.core.state) } ?? ""
    }

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: CrestSpacing.small) {
                art
                label
            }
            .frame(width: Self.previewWidth)
            .padding(.vertical, BrowserCommandPaletteMetrics.rowHorizontalPadding)
        }
        .buttonStyle(BrowserCommandPaletteRowButtonStyle(isSelected: isSelected))
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(split == nil ? Text(verbatim: "") : Text("Split View with \(members.count) tabs"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Each member's page beside the next, as the window shows a split.
    private var art: some View {
        let shape = RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
        let seams = BrowserChromeLayout.pageBrandSeamWidth * CGFloat(max(0, members.count - 1))
        let memberWidth = (Self.previewWidth - seams) / CGFloat(max(1, members.count))
        return HStack(spacing: BrowserChromeLayout.pageBrandSeamWidth) {
            ForEach(members) { member in
                page(of: member, width: memberWidth)
            }
        }
        .frame(width: Self.previewWidth, height: Self.previewHeight)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(CrestColor.subtleBorder, lineWidth: CrestLayout.hairline)
        }
        .accessibilityHidden(true)
    }

    /// A member's page, once the engine has handed it over, faded in over the
    /// tab's icon standing in for it.
    private func page(of member: TabStateModel, width: CGFloat) -> some View {
        let preview = previews[member.id]
        return ZStack {
            Rectangle().fill(.background)
            favicon(of: member, size: split == nil ? Self.placeholderFaviconSize : Self.splitPlaceholderFaviconSize)
                .opacity(preview == nil ? 1 : 0)
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: Self.previewHeight, alignment: .top)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: Self.previewHeight)
        .clipped()
        .animation(CrestMotion.dragPreview.unlessReducingMotion(reduceMotion), value: preview != nil)
    }

    private var label: some View {
        HStack(spacing: CrestSpacing.small) {
            icon
            Text(verbatim: title)
                .font(CrestTypography.controlTitle)
                .lineLimit(1)
        }
    }

    /// A split's chosen emoji or its members' icons, or a tab's icon with its engine.
    @ViewBuilder
    private var icon: some View {
        if let split, let emoji = split.displayEmojiIcon {
            Text(emoji)
                .font(.system(size: TabFaviconMetrics.defaultSize))
        } else if split != nil {
            HStack(spacing: CrestSpacing.extraExtraSmall) {
                ForEach(members) { member in
                    favicon(of: member, size: TabFaviconMetrics.defaultSize)
                }
            }
        } else if let tab = members.first {
            favicon(of: tab, size: TabFaviconMetrics.defaultSize)
                .overlay(alignment: .bottomTrailing) {
                    TabEngineBadge(tabID: tab.id, scale: 1)
                }
        }
    }

    private func favicon(of tab: TabStateModel, size: CGFloat) -> some View {
        TabStateFaviconView(
            tab: tab,
            favicons: browser.core.state.favicons,
            profileID: browser.shownSpace?.profileID,
            size: size
        )
    }
}
