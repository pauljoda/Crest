import AppKit
import SwiftUI

/// Routes only the owning sidebar's horizontal stream into AppKit's fluid
/// swipe tracker. Ordinary wheels retain the shared one-intent-per-burst policy.
@MainActor
final class SpacePagerGesture<Content: View> {
    private enum Axis { case undecided, horizontal, vertical, outside }
    private weak var viewport: SpacePagerViewport<Content>?
    private var monitor: Any?
    private var axis = Axis.undecided
    private var nativeToken: UInt?
    private var isRecognizingReplacement = false
    private let wheel = SpaceScrollGestureEventAdapter()

    init(viewport: SpacePagerViewport<Content>) { self.viewport = viewport }

    func attach(to window: NSWindow?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cancelCurrentGesture()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    func cancelCurrentGesture() {
        axis = .outside
        nativeToken = nil
        isRecognizingReplacement = false
        wheel.cancelCurrentGesture()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let viewport, let window = viewport.window, event.window === window else { return event }
        let inside =
            !viewport.isHiddenOrHasHiddenAncestor && viewport.bounds.width > 0
            && viewport.bounds.contains(viewport.convert(event.locationInWindow, from: nil))
        let begins = event.phase.contains(.began)
        if begins {
            axis = inside && !viewport.isInteractionLocked ? .undecided : .outside
            isRecognizingReplacement = axis == .undecided
        }
        guard !viewport.isInteractionLocked else {
            cancelCurrentGesture()
            return wheel.handle(
                event, isInside: inside, layoutDirection: viewport.layoutDirection, isEnabled: false,
                onStep: { _ in })
        }
        if nativeToken != nil && !isRecognizingReplacement {
            // AppKit owns the remaining samples, including its settling tail.
            // Consuming them in a second monitor could starve that tracker.
            return event
        }
        guard event.momentumPhase.isEmpty else { return event }
        let canTrack =
            event.hasPreciseScrollingDeltas && NSEvent.isSwipeTrackingFromScrollEventsEnabled
            && !viewport.reduceMotion
        if !canTrack || event.phase.isEmpty {
            return wheel.handle(
                event, isInside: inside, layoutDirection: viewport.layoutDirection,
                isEnabled: !viewport.isInteractionLocked,
                onStep: viewport.step)
        }
        if event.phase.contains(.mayBegin) { return event }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let claimed = axis == .horizontal
            axis = .outside
            return claimed ? nil : event
        }
        guard begins || event.phase.contains(.changed), axis != .outside, axis != .vertical else { return event }
        if axis == .undecided {
            guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return event }
            if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
                axis = .vertical
                isRecognizingReplacement = false
                return event
            }
            axis = .horizontal
        }
        guard inside, let token = viewport.beginInteractiveMotion() else { return event }
        isRecognizingReplacement = false
        nativeToken = token
        let minimum: CGFloat = viewport.neighbor(forPhysicalDirection: -1) == nil ? 0 : -1
        let maximum: CGFloat = viewport.neighbor(forPhysicalDirection: 1) == nil ? 0 : 1
        event.trackSwipeEvent(options: .lockDirection, dampenAmountThresholdMin: minimum, max: maximum) {
            [weak self, weak viewport] amount, phase, complete, stop in
            MainActor.assumeIsolated {
                guard let self, let viewport, self.nativeToken == token,
                    viewport.updateInteractiveMotion(amount, phase: phase, token: token, complete: complete)
                else {
                    stop.pointee = true
                    return
                }
                if complete {
                    self.nativeToken = nil
                    // A newer gesture may have begun with zero deltas while
                    // this tracker was settling. Preserve its axis decision.
                    if !self.isRecognizingReplacement { self.axis = .outside }
                }
            }
        }
        return nil
    }
}
