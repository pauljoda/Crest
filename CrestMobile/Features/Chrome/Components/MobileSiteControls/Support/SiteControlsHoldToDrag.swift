import SwiftUI
import UIKit

/// A finger's hold that lifts what is under it in Site Controls, then follows
/// the finger until it lets go, in ``SiteControlsModel/space``. It is UIKit's
/// long press, which gives way to a scroll or the sheet's own drag that moves
/// first, and once it holds keeps the finger from both.
struct SiteControlsHoldToDrag: ViewModifier {
    // MARK: - Types

    enum Phase {
        case began
        case changed
        case ended
        case cancelled
    }

    // MARK: - Variables

    let isEnabled: Bool
    let holdDuration: TimeInterval
    let changed: @MainActor (Phase, CGPoint) -> Void

    // MARK: - Actions - Drawing

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(SiteControlsHoldRecognizer(holdDuration: holdDuration, changed: changed))
        } else {
            content
        }
    }
}

/// UIKit's long press as SwiftUI takes it, reporting each phase where the
/// finger is in Site Controls. It holds alongside the tile's own touch, so a
/// button under the finger never keeps it from lifting, but never alongside a
/// pan: a scroll or the sheet's drag that starts first wins, and once the
/// hold lifts, neither starts.
private struct SiteControlsHoldRecognizer: UIGestureRecognizerRepresentable {
    // MARK: - Types

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIPanGestureRecognizer)
        }
    }

    // MARK: - Variables

    let holdDuration: TimeInterval
    let changed: @MainActor (SiteControlsHoldToDrag.Phase, CGPoint) -> Void

    // MARK: - Actions - Recognizing

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = holdDuration
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.location(in: SiteControlsModel.space)
        switch recognizer.state {
        case .began: changed(.began, location)
        case .changed: changed(.changed, location)
        case .ended: changed(.ended, location)
        case .cancelled, .failed: changed(.cancelled, location)
        default: break
        }
    }
}
