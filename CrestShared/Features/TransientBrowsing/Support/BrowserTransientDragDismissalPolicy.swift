import CoreGraphics

/// How a transient card tells a thumb pushing the card away from a thumb using
/// the page inside it.
///
/// A sheet-arranged card is filled edge to edge by the page it is previewing,
/// and that page has already claimed every downward drag it can be given.
/// Reading further up a page is a downward drag. The rubber band at the top of
/// a page is a downward drag. The pull that refreshes a page is a downward drag
/// from that same top. A dismissal laid over the web content has nothing left to
/// recognise that the page does not also answer: it threw the card away whenever
/// someone scrolled back up, and narrowing it to the scroll top would only move
/// the collision onto pull-to-refresh, where one pull would refresh the page and
/// dismiss the card showing it.
///
/// So the card is not pushed away from the page at all. It is pushed away from
/// the control bar beneath it, the way a sheet is pushed away from its grabber,
/// and the web area keeps every gesture WebKit gives it. The arbitration lives
/// here rather than inside the gesture so its thresholds can be read off exact
/// values instead of off a drag.
enum BrowserTransientDragDismissalPolicy {
    /// How far a thumb travels along the control bar before the card begins to
    /// follow it. Far enough that pressing a control never starts a drag.
    static let minimumDragDistance: CGFloat = 12

    /// How far a released drag must be predicted to carry before the card is
    /// let go rather than caught and settled back.
    static let releaseDistance: CGFloat = 120

    /// Whether a drag reading `translation` is the card being pushed down,
    /// rather than a sideways reach across the bar or a pull back upwards.
    static func carriesCard(translation: CGSize) -> Bool {
        translation.height > 0
            && abs(translation.height) > abs(translation.width)
    }

    /// How far below its resting place the card sits under this drag. A drag
    /// that has wandered back above where it began leaves the card at home
    /// rather than lifting it off the screen.
    static func dismissalOffset(for translation: CGSize) -> CGFloat {
        max(translation.height, 0)
    }

    /// Whether a released drag was thrown hard enough to close the card.
    ///
    /// A drag the card never carried can never close it, however it ends. A
    /// flick sideways across the bar predicts a long throw too, and asking the
    /// prediction alone let such a flick dismiss a card it had never moved.
    static func closesCard(
        predictedEndTranslation: CGSize,
        wasCarryingCard: Bool
    ) -> Bool {
        wasCarryingCard && predictedEndTranslation.height > releaseDistance
    }
}
