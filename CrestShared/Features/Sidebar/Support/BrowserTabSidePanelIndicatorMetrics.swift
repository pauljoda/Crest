import CoreGraphics

/// The drawn geometry of the mark a tab carries while an extension side panel
/// is bound to it.
///
/// Two shapes, because a tab is drawn two ways. A sidebar row has a label to
/// sit beside, so the mark is the row's own artwork at row scale. A pinned tile
/// is a favicon and nothing else, so the mark rides that icon's corner on a
/// disc of its own.
enum BrowserTabSidePanelIndicatorMetrics {
    /// The artwork a sidebar row draws, sized to the glyphs already in the row.
    static let rowArtworkSize: CGFloat = 16

    /// The gap the row's mark holds off the trailing control beside it. The
    /// pointer row's own content spacing is zero, so the mark supplies its own.
    static let rowSpacing = CrestSpacing.extraSmall

    /// The disc a pinned tile's badge is drawn on, which is what keeps the
    /// artwork readable over a favicon of any colour.
    static let badgeDiameter: CGFloat = 12

    /// The artwork inside that disc.
    static let badgeArtworkSize: CGFloat = 8

    /// How far the badge hangs past the favicon's corner, so it reads as
    /// attached to the icon rather than drawn on top of it.
    static let badgeOffset: CGFloat = 3

    /// What a panel whose package offers no usable artwork falls back to.
    static let fallbackSymbol = "puzzlepiece.extension.fill"
}
