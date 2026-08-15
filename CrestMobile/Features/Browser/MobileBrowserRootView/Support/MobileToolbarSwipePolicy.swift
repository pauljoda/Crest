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
