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

/// Routes the compact toolbar's horizontal swipe.
///
/// One gesture, one owner. `BrowserSpaceSwipePolicy` still decides whether a
/// drag counts as a deliberate horizontal swipe and which way it points; this
/// decides what that swipe is *for*, which as of 0.4 is Split View.
///
/// The recognizer is unconditional on purpose. Making it appear only inside a
/// group would mean the toolbar behaved differently from one tab to the next
/// with nothing on screen to explain why; answering `.none` keeps the gesture in
/// one place and simply quiet where there is no second card.
enum MobileToolbarSwipePolicy {
    /// What ships. `MobileToolbarSwipeMode` documents why.
    static let mode: MobileToolbarSwipeMode = .cardsOnly

    static func destination(
        isInSplitGroup: Bool,
        mode: MobileToolbarSwipeMode = mode
    ) -> MobileToolbarSwipeDestination {
        switch mode {
        case .cardsOnly:
            isInSplitGroup ? .adjacentCard : .none
        case .contextual:
            isInSplitGroup ? .adjacentCard : .adjacentSpace
        }
    }
}
