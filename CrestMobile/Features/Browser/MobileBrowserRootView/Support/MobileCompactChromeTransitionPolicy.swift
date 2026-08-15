import CoreGraphics

enum MobileCompactChromeTransitionPolicy {
    static let completionThreshold: CGFloat = 64
    static let verticalDominance: CGFloat = 1.2
    static let maximumInteractiveTranslation: CGFloat = 220

    static func constrainedTranslation(
        _ translation: CGSize,
        for transition: MobileCompactChromeTransition
    ) -> CGFloat {
        guard abs(translation.height) > abs(translation.width) * verticalDominance else {
            return 0
        }

        let directionalTranslation =
            switch transition {
            case .revealTabViewer:
                min(0, translation.height)
            case .revealPage:
                max(0, translation.height)
            }

        return min(
            max(directionalTranslation, -maximumInteractiveTranslation),
            maximumInteractiveTranslation
        )
    }

    static func commits(
        predictedEndTranslation: CGSize,
        for transition: MobileCompactChromeTransition
    ) -> Bool {
        guard
            abs(predictedEndTranslation.height)
                > abs(predictedEndTranslation.width) * verticalDominance
        else {
            return false
        }

        switch transition {
        case .revealTabViewer:
            return predictedEndTranslation.height <= -completionThreshold
        case .revealPage:
            return predictedEndTranslation.height >= completionThreshold
        }
    }
}
