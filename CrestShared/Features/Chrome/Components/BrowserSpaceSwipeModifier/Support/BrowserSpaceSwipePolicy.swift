import SwiftUI

enum BrowserSpaceSwipePolicy {
    static let minimumHorizontalDistance: CGFloat = 72
    static let horizontalDominance: CGFloat = 1.35
    static let minimumDragRecognitionDistance: CGFloat = 18

    static func direction(
        for translation: CGSize,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> BrowserSpaceSwipeDirection? {
        guard abs(translation.width) >= minimumHorizontalDistance,
            abs(translation.width) >= abs(translation.height) * horizontalDominance
        else {
            return nil
        }
        let semanticTranslation =
            BrowserChromeDirectionPolicy.semanticHorizontalTranslation(
                translation.width,
                layoutDirection: layoutDirection
            )
        return semanticTranslation < 0 ? .next : .previous
    }
}
