import SwiftUI

extension BrowserSpaceSwipeDirection {
    // MARK: - Static Variables

    static let minimumHorizontalDistance: CGFloat = 72
    static let horizontalDominance: CGFloat = 1.35
    static let minimumDragRecognitionDistance: CGFloat = 18

    // MARK: - Initializers

    /// The Space a deliberate horizontal swipe of `translation` steps to, or
    /// nil when the drag is too short or not horizontal enough to count.
    init?(
        translation: CGSize,
        layoutDirection: LayoutDirection = .leftToRight
    ) {
        guard abs(translation.width) >= Self.minimumHorizontalDistance,
            abs(translation.width) >= abs(translation.height) * Self.horizontalDominance
        else {
            return nil
        }
        let semanticTranslation = layoutDirection.semanticHorizontalTranslation(translation.width)
        self = semanticTranslation < 0 ? .next : .previous
    }
}
