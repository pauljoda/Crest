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

/// Routes the compact chrome's upward swipe.
///
/// The gesture has one meaning — bring the sidebar up — and the sidebar has
/// three placements. A narrow phone's docked sidebar *is* the full-screen tab
/// viewer, so the swipe has always ended there and still does; the two undocked
/// placements own that same sidebar over a page that stays on screen, and the
/// swipe belongs to them the same way.
///
/// Reaching this toolbar undocked takes a Split View.
/// `MobileSidebarPageFramePolicy.showsCompactToolbar` puts the compact toolbar
/// up for a docked sidebar *or* a presented split, so a floating or collapsed
/// sidebar only has a toolbar to swipe while a group is on show. Sending the
/// swipe to the full-screen viewer from there took the window out of its split
/// and re-docked the sidebar in one move — two placement changes the finger
/// never asked for, and no way back to either except by undoing both by hand.
///
/// Keyed on the placement rather than on the split, because that is the rule
/// itself rather than the one case that exposes it: the sidebar comes up where
/// the window already keeps it. Answering the split directly would say the same
/// thing today and stop being true the moment anything else puts this toolbar on
/// screen undocked.
enum MobileCompactSidebarRevealPolicy {
    static func destination(
        sidebarPresentation: BrowserSidebarPresentation
    ) -> MobileCompactSidebarRevealDestination {
        switch sidebarPresentation {
        case .docked:
            .tabViewer
        case .floating, .collapsed:
            .floatingSidebar
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
