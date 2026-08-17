import SwiftUI

struct BrowserSpaceSwipeModifier: ViewModifier {
    /// What a recognized horizontal swipe does.
    ///
    /// The recognizer decides only that a deliberate horizontal gesture happened
    /// and which way it points. Where it goes is the consumer's call — on iOS
    /// that is `MobileToolbarSwipePolicy`, which as of 0.4 pages Split View cards
    /// rather than switching Spaces.
    let handleSwipe: (BrowserSpaceSwipeDirection) -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content.simultaneousGesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: BrowserSpaceSwipePolicy.minimumDragRecognitionDistance,
            coordinateSpace: .local
        )
        .onEnded { value in
            guard
                let direction = BrowserSpaceSwipePolicy.direction(
                    for: value.predictedEndTranslation,
                    layoutDirection: layoutDirection
                )
            else { return }
            handleSwipe(direction)
        }
    }
}
