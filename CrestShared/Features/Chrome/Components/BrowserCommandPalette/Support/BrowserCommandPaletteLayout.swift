import CoreGraphics

enum BrowserCommandPaletteLayout {
    static let maximumResultAreaHeight = BrowserCommandPaletteMetrics.maximumResultAreaHeight

    static func resultAreaHeight(
        sectionRowCounts: [Int],
        includesPrimaryAction: Bool,
        maximumHeight: CGFloat = maximumResultAreaHeight
    ) -> CGFloat {
        let sections = sectionRowCounts.filter { $0 > 0 }
        let blockCount = sections.count + (includesPrimaryAction ? 1 : 0)
        guard blockCount > 0 else { return 0 }

        let sectionsHeight = sections.reduce(CGFloat.zero) { total, rows in
            total
                + BrowserCommandPaletteMetrics.resultHeaderHeight
                + BrowserCommandPaletteMetrics.resultRowSpacing
                + (CGFloat(rows) * BrowserCommandPaletteMetrics.resultRowHeight)
                + (CGFloat(rows - 1) * BrowserCommandPaletteMetrics.resultRowSpacing)
        }
        let actionHeight =
            includesPrimaryAction
            ? BrowserCommandPaletteMetrics.resultRowHeight
            : 0
        let spacing =
            CGFloat(blockCount - 1)
            * BrowserCommandPaletteMetrics.resultSectionSpacing

        return min(
            BrowserCommandPaletteMetrics.resultOuterPadding
                + sectionsHeight
                + spacing
                + actionHeight,
            max(0, maximumHeight)
        )
    }

    static func resultAreaHeight(
        tabCount: Int,
        includesPrimaryAction: Bool,
        maximumHeight: CGFloat = maximumResultAreaHeight
    ) -> CGFloat {
        resultAreaHeight(
            sectionRowCounts: [max(0, tabCount)],
            includesPrimaryAction: includesPrimaryAction,
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
