import SwiftUI

/// The arithmetic a transient overlay's card shares wherever it is presented.
///
/// Peek and Quick Window both begin as a link under a pointer or a finger and
/// both grow into a card that has to stay inside whatever room the screen
/// leaves them. Neither sum depends on which shell is asking, so both live
/// here rather than once per platform.
enum BrowserTransientCardLayout {
    /// The transform that starts a card at the link it was opened from.
    ///
    /// Once the card's own frame inside a container of `containerSize` is
    /// known, the card starts over its link: centred on it, at the link's
    /// size, and grows from there along the line to its own place. Until then
    /// it grows from the point the link was touched, at the link's share of
    /// the container.
    ///
    /// The clamps keep a card recognisable: a link narrower than the lower
    /// bound would start as a hairline, and one wider than the upper bound
    /// would barely appear to grow at all.
    static func sourceCardTransform(
        for source: BrowserPeekSourcePresentation,
        cardFrame: CGRect?,
        in containerSize: CGSize
    ) -> BrowserTransientSourceTransform {
        guard let cardFrame, cardFrame.width > 0, cardFrame.height > 0,
            containerSize.width > 0, containerSize.height > 0
        else {
            return BrowserTransientSourceTransform(
                anchor: UnitPoint(x: source.normalizedTouchX, y: source.normalizedTouchY),
                scaleX: startingWidthShare(source.normalizedWidth),
                scaleY: startingHeightShare(source.normalizedHeight)
            )
        }
        let link = CGRect(
            x: source.normalizedMinX * containerSize.width,
            y: source.normalizedMinY * containerSize.height,
            width: source.normalizedWidth * containerSize.width,
            height: source.normalizedHeight * containerSize.height
        )
        let scaleX = startingWidthShare(link.width / cardFrame.width)
        let scaleY = startingHeightShare(link.height / cardFrame.height)
        let start = CGPoint(
            x: link.midX - cardFrame.width * scaleX / 2,
            y: link.midY - cardFrame.height * scaleY / 2
        )
        // The point a scale holds still is the one that carries the card's
        // origin onto the start; every other point of the card follows it.
        return BrowserTransientSourceTransform(
            anchor: UnitPoint(
                x: (start.x - scaleX * cardFrame.minX) / (1 - scaleX) / containerSize.width,
                y: (start.y - scaleY * cardFrame.minY) / (1 - scaleY) / containerSize.height
            ),
            scaleX: scaleX,
            scaleY: scaleY
        )
    }

    private static func startingWidthShare(_ share: CGFloat) -> CGFloat {
        min(max(share, 0.06), 0.42)
    }

    private static func startingHeightShare(_ share: CGFloat) -> CGFloat {
        min(max(share, 0.035), 0.24)
    }

    /// Insets that clear the screen's own safe area without letting a card
    /// press against the bezel on the edges where that area is thin.
    static func cardInsets(
        safeAreaInsets: EdgeInsets,
        minimumHorizontal: CGFloat,
        minimumVertical: CGFloat
    ) -> EdgeInsets {
        EdgeInsets(
            top: max(safeAreaInsets.top, minimumVertical),
            leading: max(safeAreaInsets.leading, minimumHorizontal),
            bottom: max(safeAreaInsets.bottom, minimumVertical),
            trailing: max(safeAreaInsets.trailing, minimumHorizontal)
        )
    }
}

/// The scale and anchor that place a transient card over its source link.
struct BrowserTransientSourceTransform: Equatable, Sendable {
    let anchor: UnitPoint
    let scaleX: CGFloat
    let scaleY: CGFloat
}
