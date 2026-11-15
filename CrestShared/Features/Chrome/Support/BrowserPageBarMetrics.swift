import CoreGraphics

/// The drawn geometry of a page bar: back, forward, the address field, pinned
/// extensions and whatever follows them. A Quick Window's toolbar is one, and
/// so is the bar each card of a split carries; they are the same bar measured
/// for where it sits. The window's own address bar along the top of a lone
/// page is the sidebar's chrome moved there, laid out by the top section.
struct BrowserPageBarMetrics: Equatable, Sendable {
    // MARK: - Static Variables

    /// A Quick Window's toolbar: the field shares the window buttons' centre
    /// line, 26 pt from the top, and the page surface owns the gap below it.
    static let quickWindow = BrowserPageBarMetrics(
        height: 44, topPadding: 8, bottomPadding: 0, leadingPadding: 0, trailingPadding: 10, spacing: 8,
        fieldHeight: BrowserChromeLayout.addressHeight, fieldMinimumWidth: 220, widthBeforeExtensions: 300)

    /// The bar each card of a split carries inside its corners: the
    /// sidebar's own 36 pt field with room all round it, clear of the card's
    /// edges.
    static let pageCard = BrowserPageBarMetrics(
        height: 48, topPadding: 6, bottomPadding: 6, leadingPadding: 8, trailingPadding: 8, spacing: 8,
        fieldHeight: BrowserChromeLayout.addressHeight, fieldMinimumWidth: 130, widthBeforeExtensions: 300)

    /// The room above and below the window's address field along the top of
    /// a lone page, equal on both sides, which puts the field's centre on the
    /// window buttons' line.
    static let topSectionGap: CGFloat = 8

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
