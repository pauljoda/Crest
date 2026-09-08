import SwiftUI

/// Sidebar-only recognition. The toolbar's existing gesture continues to page split cards.
struct PlatformSpaceGestureModifier: ViewModifier {
    let isEnabled: Bool
    let onStep: (BrowserSpaceSwipeDirection) -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState private var isGestureActive = false
    @State private var gestureIsEligible: Bool?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(
                minimumDistance: BrowserSpaceSwipePolicy.minimumDragRecognitionDistance,
                coordinateSpace: .local
            )
            .updating($isGestureActive) { value, isActive, _ in
                // GestureState resets on cancellation even when onEnded is not
                // called. Keep eligibility separate so its final value survives
                // that reset until onEnded, then reinitialize on the next start.
                if !isActive { gestureIsEligible = isEnabled }
                isActive = true
                if !isEnabled
                    || abs(value.translation.height)
                        >= abs(value.translation.width) * BrowserSpaceSwipePolicy.horizontalDominance
                {
                    gestureIsEligible = false
                }
            }
            .onEnded { value in
                defer { gestureIsEligible = nil }
                guard isEnabled, gestureIsEligible == true,
                    let direction = BrowserSpaceSwipePolicy.direction(
                        for: value.translation, layoutDirection: layoutDirection)
                else { return }
                onStep(direction)
            }
        )
        .onChange(of: isEnabled) { _, isEnabled in
            if !isEnabled, gestureIsEligible != nil { gestureIsEligible = false }
        }
        .onDisappear { gestureIsEligible = nil }
    }
}
