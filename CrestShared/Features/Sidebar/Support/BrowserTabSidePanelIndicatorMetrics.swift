import CoreGraphics

/// The drawn geometry of the mark a tab carries while an extension side panel
/// is bound to it.
///
/// One shape, however the tab is drawn. A sidebar row and a pinned tile both
/// hang the mark off the same corner of the same favicon, so the two read as
/// the same tab wearing the same badge rather than as two conventions that
/// happen to mean the same thing. The disc is sized against the smaller of the
/// two icons it rides — the row's 18pt favicon, against the tile's 19pt — so it
/// never grows into the thing it is annotating.
enum BrowserTabSidePanelIndicatorMetrics {
    /// The disc the artwork is drawn on, which is what keeps it readable over a
    /// favicon of any colour.
    static let badgeDiameter: CGFloat = 10

    /// The artwork inside that disc, inset far enough that the disc still reads
    /// as a ring around it at either favicon size.
    static let badgeArtworkSize: CGFloat = 6.5

    /// How far the badge hangs past the favicon's corner, so it reads as
    /// attached to the icon rather than drawn on top of it.
    static let badgeOverhang: CGFloat = 2

    /// What a panel whose package offers no usable artwork falls back to.
    static let fallbackSymbol = "puzzlepiece.extension.fill"
}
