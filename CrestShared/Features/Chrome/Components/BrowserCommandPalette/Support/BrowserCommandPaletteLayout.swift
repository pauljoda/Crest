import CoreGraphics

enum BrowserCommandPaletteLayout {
    static let maximumResultAreaHeight = BrowserCommandPaletteMetrics.maximumResultAreaHeight

    /// The height the results take: each group's rows, with a header above
    /// a group that has one, the spacing between groups and the padding
    /// around them, at most `maximumHeight`.
    static func resultAreaHeight(
        groups: [(hasHeader: Bool, rows: Int)],
        maximumHeight: CGFloat = maximumResultAreaHeight
    ) -> CGFloat {
        let shown = groups.filter { $0.rows > 0 }
        guard !shown.isEmpty else { return 0 }
        let groupsHeight = shown.reduce(CGFloat.zero) { total, group in
            total
                + (group.hasHeader
                    ? BrowserCommandPaletteMetrics.resultHeaderHeight + BrowserCommandPaletteMetrics.resultRowSpacing
                    : 0)
                + CGFloat(group.rows) * BrowserCommandPaletteMetrics.resultRowHeight
                + CGFloat(group.rows - 1) * BrowserCommandPaletteMetrics.resultRowSpacing
        }
        let spacing = CGFloat(shown.count - 1) * BrowserCommandPaletteMetrics.resultSectionSpacing
        return min(BrowserCommandPaletteMetrics.resultOuterPadding + groupsHeight + spacing, max(0, maximumHeight))
    }

    static func resultAreaHeight(
        tabCount: Int,
        includesPrimaryAction: Bool,
        maximumHeight: CGFloat = maximumResultAreaHeight
    ) -> CGFloat {
        resultAreaHeight(
            groups: [(false, includesPrimaryAction ? 1 : 0), (true, max(0, tabCount))],
            maximumHeight: maximumHeight
        )
    }

    /// The overlay card's width in the space its layer leaves it: as wide as
    /// the palette allows, less the padding around the card.
    static func overlayCardWidth(availableWidth: CGFloat) -> CGFloat {
        min(
            BrowserCommandPaletteMetrics.maximumCardWidth,
            max(0, availableWidth - BrowserCommandPaletteMetrics.overlayCardPadding * 2)
        )
    }

    /// How far below the top of the space its layer leaves it the overlay
    /// card's top edge rests: where a card with its tallest results would sit
    /// centered, so the top never moves as results come and go and the card
    /// only grows downward, as on iPhone and iPad.
    static func overlayTopInset(availableHeight: CGFloat) -> CGFloat {
        let tallestCard =
            BrowserCommandPaletteMetrics.searchFieldMinimumHeight
            + overlayResultAreaHeight(availableHeight: availableHeight)
        return max(BrowserCommandPaletteMetrics.overlayCardPadding, (availableHeight - tallestCard) / 2)
    }

    /// Where a palette grown out of `field` may lie in a space of `size`:
    /// on the field's leading edge, as wide as the field or the
    /// presentation's minimum, and no farther than the space's trailing edge,
    /// or across the whole space for one as wide as it; and from the field's
    /// top edge down to the bottom of the space, or for one listing upward,
    /// from its bottom edge up to the top, clear of the screen's safe area
    /// there as a Peek is.
    static func fieldRegion(
        field: CGRect, in size: CGSize, safeAreaTop: CGFloat = 0, presentation: BrowserCommandPalettePresentation
    ) -> CGRect {
        let margin = BrowserCommandPaletteMetrics.fieldRegionMargin
        let wanted = max(field.width, presentation.minimumWidth)
        let minX = wanted >= size.width - margin * 2 ? margin : max(margin, field.minX)
        let width = max(0, min(size.width - margin - minX, wanted))
        let minY =
            presentation.listsUpward
            ? max(safeAreaTop, BrowserCommandPaletteMetrics.fieldRegionTopMargin) : field.minY
        let maxY = presentation.listsUpward ? field.maxY : size.height - margin
        return CGRect(x: minX, y: minY, width: width, height: max(0, maxY - minY))
    }

    /// The height the results of a palette in a field region `regionHeight`
    /// tall may take beside its input line at its minimum height. The card
    /// takes from it what a larger text size adds to that line.
    static func fieldResultAreaHeight(
        regionHeight: CGFloat, presentation: BrowserCommandPalettePresentation
    ) -> CGFloat {
        min(
            presentation.maximumResultHeight,
            max(0, regionHeight - presentation.input.minimumHeight - CrestLayout.hairline))
    }

    static func overlayResultAreaHeight(availableHeight: CGFloat) -> CGFloat {
        max(
            BrowserCommandPaletteMetrics.minimumOverlayResultHeight,
            min(
                maximumResultAreaHeight,
                availableHeight - BrowserCommandPaletteMetrics.overlayReservedHeight
            )
        )
    }

}
