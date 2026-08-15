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

#Preview("Space Swipe Modifier") {
    @Previewable @State var lastDirection: BrowserSpaceSwipeDirection?
    let status =
        switch lastDirection {
        case .previous:
            "Previous Space"
        case .next:
            "Next Space"
        case nil:
            "Swipe horizontally"
        }

    VStack(spacing: CrestSpacing.medium) {
        Text(status)
            .font(.headline)

        RoundedRectangle(cornerRadius: CrestRadius.card)
            .fill(.blue.gradient)
            .overlay {
                Image(systemName: "hand.draw")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
            }
            .modifier(
                BrowserSpaceSwipeModifier {
                    lastDirection = $0
                }
            )
    }
    .padding()
    .frame(width: 320, height: 220)
}
