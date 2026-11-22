import SwiftUI

struct BrowserTabDragPreview: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    /// The shape the preview is `progress` of the way toward. It always starts
    /// from the row, because the row is the shape the drag machinery measures a
    /// grab offset in.
    var targetShape = BrowserTabDragPreviewShape.pinnedTile
    let progress: CGFloat
    var rowWidth = BrowserTabDragPreviewLayout.rowSize.width
    var pinnedSize = BrowserTabDragPreviewLayout.pinnedSize
    var isSelected = false
    var isLoaded = true
    var rowMetrics = BrowserSidebarTabRowMetrics.pointer
    /// How far the folders around the row move its icon and title in.
    var contentIndent: CGFloat = 0

    var body: some View {
        let metrics = BrowserTabDragPreviewLayout.metrics(
            from: .row,
            to: targetShape,
            progress: progress,
            rowWidth: rowWidth,
            pinnedSize: pinnedSize
        )
        let shape = RoundedRectangle(
            cornerRadius: BrowserTabDragPreviewLayout.cornerRadius(
                from: .row, to: targetShape, progress: progress,
                layerCornerRadius: BrowserSidebarMetrics.layerCornerRadius()),
            style: .continuous
        )
        // The row layout and the card's own centred layout cross-fade rather
        // than interpolate: a leading favicon beside a title and a stacked,
        // centred pair are different arrangements, not two ends of one.
        let rowOpacity = 1 - Double(metrics.cardContentWeight)

        ZStack(alignment: .leading) {
            // A selected tab keeps the style it is drawn in in the sidebar.
            // Its paper is solid here, where it floats over the page under a
            // shadow of its own, which would grey translucent paper.
            CrestSurfaceLayer(shape: shape, paper: isSelected && selectedStyle.liesOnPaper ? .opaque : nil)
                .overlay {
                    shape.strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
                }

            Button {
            } label: {
                BrowserSidebarTabLabel(
                    tab: tab, favicons: favicons, profileID: profileID, isSelected: isSelected,
                    isLoaded: isLoaded, metrics: rowMetrics,
                    leadingInset: BrowserSidebarMetrics.layerInset + rowMetrics.contentLeadingInset + contentIndent,
                    titleOpacity: metrics.titleOpacity,
                    iconOffset: ((metrics.width / 2) - rowIconCenter) * metrics.contentCentering)
            }
            .buttonStyle(.plain)
            .frame(width: metrics.width, height: metrics.height)
            .opacity(rowOpacity)
            .allowsHitTesting(false)

            if metrics.cardContentWeight > 0 {
                cardContent
                    .opacity(Double(metrics.cardContentWeight))
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .shadow(
            color: .black.opacity(0.22),
            radius: 10,
            y: 5
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.shownTitle)
        .modifier(BrowserTabDragPreviewTone(style: isSelected ? selectedStyle : nil))
    }

    /// How the selected tab is drawn on this device.
    private var selectedStyle: BrowserSelectedTabStyle {
        BrowserDeviceAppearanceStore.shared.tabs.selectedTabStyle
    }

    private var rowIconCenter: CGFloat {
        BrowserSidebarMetrics.layerInset + rowMetrics.contentLeadingInset + contentIndent
            + (rowMetrics.faviconSlot?.width ?? 18) / 2
    }

    /// The page-shaped drop preview: what the tab looks like once it is a card.
    /// A favicon and a title stand in for the page — a live snapshot would have
    /// to be captured from a web view mid-drag, which this release does not do.
    private var cardContent: some View {
        VStack(spacing: CrestSpacing.small) {
            TabStateFaviconView(tab: tab, favicons: favicons, profileID: profileID, size: 32)
            Text(tab.shownTitle)
                .font(CrestTypography.controlTitle)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, CrestSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// The scheme and ink a dragged tab reads in: the selected tab's as its
/// row has them, ink on paper or the material's on the material, and
/// otherwise the label color in the scheme the device's material color
/// gives the material.
///
/// Both states set the same modifiers, so picking up the selected tab
/// changes values rather than the preview's structure.
private struct BrowserTabDragPreviewTone: ViewModifier {
    /// The selected tab's style, or nil for any other tab.
    let style: BrowserSelectedTabStyle?

    @Environment(\.deviceColorScheme) private var deviceColorScheme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let materialScheme = CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme)
        content
            .foregroundStyle(style?.foreground ?? Color.primary)
            .environment(\.spaceChromeForeground, nil)
            .environment(\.colorScheme, style?.contentScheme(onMaterial: materialScheme) ?? materialScheme)
    }
}
