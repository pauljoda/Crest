import CoreGraphics

/// The drawn geometry of a page bar: back, forward, the address field, pinned
/// extensions and whatever follows them. A Quick Window's toolbar is one, and
/// so is the bar each card of a split carries; they are the same bar measured
/// for where it sits. The window's own address bar along the top of a lone
/// page is the sidebar's chrome moved there, laid out by the top section.
struct BrowserPageBarMetrics: Equatable, Sendable {
    // MARK: - Static Variables

    /// Where the window's own buttons are centred, from the top of the
    /// window. A bar along the top shares their centre line.
    static let windowControlsCenterY: CGFloat = 26

    /// How far a bar the window's own buttons stand over keeps its first
    /// control from the window's leading edge: the zoom button ends 80 pt in,
    /// and the bar keeps 12 pt clear of it.
    static let windowControlsClearance: CGFloat = 92

    /// The sidebar's toggle a bar carries while the sidebar is not docked.
    static let sidebarToggleSize = CGSize(width: 30, height: 30)

    /// Reload, and the menu beside it that offers reloading from the origin,
    /// at the field's end, each as wide as its glyph needs.
    static let reloadControlSize = CGSize(width: 24, height: CrestLayout.minimumHitTarget)
    static let reloadMenuControlSize = CGSize(width: 14, height: CrestLayout.minimumHitTarget)

    /// A Quick Window's toolbar: the field shares the window buttons' centre
    /// line, and the page surface owns the gap below it.
    static let quickWindow = BrowserPageBarMetrics(
        height: windowControlsCenterY + BrowserChromeLayout.addressHeight / 2,
        topPadding: windowControlsCenterY - BrowserChromeLayout.addressHeight / 2, bottomPadding: 0,
        leadingPadding: 0, trailingPadding: 10, spacing: 8,
        fieldHeight: BrowserChromeLayout.addressHeight, fieldMinimumWidth: 220, widthBeforeExtensions: 300)

    /// The bar each card of a split carries inside its corners: the
    /// sidebar's own 36 pt field with room all round it, clear of the card's
    /// edges.
    static let pageCard = BrowserPageBarMetrics(
        height: 48, topPadding: 6, bottomPadding: 6, leadingPadding: 8, trailingPadding: 8, spacing: 8,
        fieldHeight: BrowserChromeLayout.addressHeight, fieldMinimumWidth: 130, widthBeforeExtensions: 300)

    /// The room above and below the window's address field along the top of
    /// a lone page, equal on both sides, so the field's centre is on the
    /// window buttons' line.
    static let topSectionGap: CGFloat = windowControlsCenterY - BrowserChromeLayout.addressHeight / 2

    /// How far a lone page's card stands below the top of the window while
    /// the address bar is on top: the field with its room above and below.
    static var topSectionHeight: CGFloat { topSectionGap * 2 + BrowserChromeLayout.addressHeight }

    // MARK: - Variables

    /// The band the bar occupies.
    let height: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    /// How far the bar's first control stands off its leading edge, before any
    /// room it leaves for the window's own buttons.
    let leadingPadding: CGFloat
    let trailingPadding: CGFloat
    /// The gap between back and forward, the field, and what follows it.
    let spacing: CGFloat
    let fieldHeight: CGFloat
    /// The narrowest the field gets, however many extensions are pinned.
    let fieldMinimumWidth: CGFloat
    /// The width the field keeps before pinned extensions show beside it, so
    /// its address stays readable.
    let widthBeforeExtensions: CGFloat
}
