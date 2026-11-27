import CoreGraphics

/// The forms a lifted tab can take while a drag is in flight.
///
/// A lift shows what the tab is about to become, so the shape is a property of
/// the destination rather than of the tab: the same row becomes a tile over the
/// pinned grid and a page-shaped card over the content area. Every number a
/// morph interpolates lives here, which is what lets
/// `BrowserTabDragPreviewLayout` interpolate any pair without knowing what
/// either end means. The one number a shape does not own is a sidebar layer's
/// corner, which follows the person's corner setting and is handed in.
struct BrowserTabDragPreviewShape: Equatable, Sendable {
    // MARK: - Static Variables

    /// A sidebar list row — the resting shape of every unpinned tab.
    static let row = BrowserTabDragPreviewShape(
        name: "row",
        titleOpacity: 1,
        contentCentering: 0,
        cardContentWeight: 0,
        resolveSize: { rowWidth, _ in
            CGSize(
                width: BrowserTabDragPreviewLayout.resolvedRowWidth(rowWidth),
                height: BrowserTabDragPreviewLayout.rowSize.height
            )
        },
        resolveCornerRadius: { layerCornerRadius in layerCornerRadius }
    )

    /// A cell of the pinned grid.
    static let pinnedTile = BrowserTabDragPreviewShape(
        name: "pinnedTile",
        titleOpacity: 0,
        contentCentering: 1,
        cardContentWeight: 0,
        resolveSize: { _, pinnedSize in pinnedSize },
        resolveCornerRadius: { layerCornerRadius in layerCornerRadius }
    )

    /// A card in the split-view content area.
    static let webpageCard = BrowserTabDragPreviewShape(
        name: "webpageCard",
        titleOpacity: 1,
        // The card draws its own centred content instead of moving the row's,
        // so the row layout it fades out of stays where it was.
        contentCentering: 0,
        cardContentWeight: 1,
        resolveSize: { _, _ in BrowserTabDragPreviewLayout.cardSize },
        // A drop preview that reads as a page has to be cornered like one.
        resolveCornerRadius: { _ in BrowserChromeLayout.pageCornerRadius }
    )

    // MARK: - Variables

    let name: String
    /// How visible the row's own title line is. A tile has no room for it.
    let titleOpacity: Double
    /// How far the row's leading favicon travels toward the middle: `0` leaves it
    /// at the leading edge, `1` centres it.
    let contentCentering: CGFloat
    /// How much of the card's own centred layout is showing, as opposed to the
    /// row layout it replaces.
    let cardContentWeight: CGFloat
    private let resolveSize: @Sendable (CGFloat, CGSize) -> CGSize
    private let resolveCornerRadius: @Sendable (CGFloat) -> CGFloat

    // MARK: - Actions - Presentation

    /// The shape a tab resting in this placement already has, and therefore the
    /// shape a lift starts from.
    static func resting(for placement: TabPlacement) -> BrowserTabDragPreviewShape {
        placement.isGrid ? .pinnedTile : .row
    }

    func size(rowWidth: CGFloat, pinnedSize: CGSize = BrowserTabDragPreviewLayout.pinnedSize) -> CGSize {
        resolveSize(rowWidth, pinnedSize)
    }

    /// The shape's corner, where `layerCornerRadius` is the corner of the
    /// sidebar layer a row and a pinned tile are drawn as.
    func cornerRadius(layerCornerRadius: CGFloat) -> CGFloat {
        resolveCornerRadius(layerCornerRadius)
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
