import AppKit
import SwiftUI

/// Keeps AppKit phase, delta conventions, and event consumption at the native boundary.
@MainActor
final class SpaceScrollGestureEventAdapter {
    private var policy = SpaceScrollGesturePolicy()

    func reset() {
        policy.reset()
    }

    func cancelCurrentGesture() {
        policy.cancelCurrentGesture()
    }

    func handle(
        _ event: NSEvent, isInside: Bool, layoutDirection: LayoutDirection,
        isEnabled: Bool = true,
        onStep: (BrowserSpaceSwipeDirection) -> Void
    ) -> NSEvent? {
        if !isEnabled { policy.cancelCurrentGesture() }
        let decision = policy.consume(
            Self.input(for: event, layoutDirection: layoutDirection), isInside: isInside && isEnabled)
        guard isEnabled else { return event }
        switch decision {
        case .passThrough:
            return event
        case .consumed:
            return nil
        case .step(let direction):
            onStep(direction)
            return nil
        }
    }

    static func input(for event: NSEvent, layoutDirection: LayoutDirection) -> SpaceScrollGesturePolicy.Input {
        let phase: SpaceScrollGesturePolicy.Phase
        if event.phase.contains(.cancelled) {
            phase = .cancelled
        } else if event.phase.contains(.ended) {
            phase = .ended
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.mayBegin) {
            phase = .mayBegin
        } else if !event.phase.isEmpty {
            phase = .changed
        } else {
            phase = .none
        }
        return .init(
            deltaX: BrowserChromeDirectionPolicy.semanticHorizontalTranslation(
                event.scrollingDeltaX, layoutDirection: layoutDirection),
            deltaY: event.scrollingDeltaY,
            timestamp: event.timestamp,
            isPrecise: event.hasPreciseScrollingDeltas,
            phase: phase,
            isMomentum: !event.momentumPhase.isEmpty
        )
    }
}
