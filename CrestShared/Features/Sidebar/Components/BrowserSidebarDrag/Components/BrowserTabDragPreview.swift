import SwiftUI

struct BrowserTabDragPreview: View {
    let tab: BrowserTab
    let profileID: UUID
    /// The shape the preview is `progress` of the way toward. It always starts
    /// from the row, because the row is the shape the drag machinery measures a
    /// grab offset in.
    var targetShape = BrowserTabDragPreviewShape.pinnedTile
    let progress: CGFloat
    var rowWidth = BrowserTabDragPreviewLayout.rowSize.width

    var body: some View {
        let metrics = BrowserTabDragPreviewLayout.metrics(
            from: .row,
            to: targetShape,
            progress: progress,
            rowWidth: rowWidth
        )
        let shape = RoundedRectangle(
            cornerRadius: metrics.cornerRadius,
            style: .continuous
        )
        // The row layout and the card's own centred layout cross-fade rather
        // than interpolate: a leading favicon beside a title and a stacked,
        // centred pair are different arrangements, not two ends of one.
        let rowOpacity = 1 - Double(metrics.cardContentWeight)

        ZStack(alignment: .leading) {
            shape
                .fill(CrestColor.selectedSurface)
                .overlay {
                    shape.strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
                }

            TabFaviconView(tab: tab, profileID: profileID, size: 20)
                .position(
                    x: 22 + ((metrics.width / 2) - 22) * metrics.contentCentering,
                    y: metrics.height / 2
                )
                .opacity(rowOpacity)

            Text(tab.displayTitle)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .opacity(metrics.titleOpacity * rowOpacity)
                .padding(.leading, 42)
                .padding(.trailing, 12)
                .frame(width: metrics.width, alignment: .leading)
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
        .accessibilityLabel(tab.displayTitle)
    }

    /// The page-shaped drop preview: what the tab looks like once it is a card.
    /// A favicon and a title stand in for the page — a live snapshot would have
    /// to be captured from a web view mid-drag, which this release does not do.
    private var cardContent: some View {
        VStack(spacing: CrestSpacing.small) {
            TabFaviconView(tab: tab, profileID: profileID, size: 32)
            Text(tab.displayTitle)
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

#Preview("Tab Drag Preview", traits: .fixedLayout(width: 420, height: 320)) {
    let fixture = BrowserSidebarInteractionPreviewFixture()

    HStack(alignment: .top, spacing: CrestSpacing.large) {
        VStack(spacing: CrestSpacing.large) {
            BrowserTabDragPreview(
                tab: fixture.currentTab,
                profileID: fixture.space.profile.id,
                progress: 0
            )
            BrowserTabDragPreview(
                tab: fixture.pinnedTab,
                profileID: fixture.space.profile.id,
                progress: 1
            )
        }
        BrowserTabDragPreview(
            tab: fixture.currentTab,
            profileID: fixture.space.profile.id,
            targetShape: .webpageCard,
            progress: 1
        )
    }
    .padding()
}
