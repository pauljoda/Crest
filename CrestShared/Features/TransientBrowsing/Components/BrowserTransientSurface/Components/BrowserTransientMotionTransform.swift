import SwiftUI

/// Animates the existing card without replacing its page or controls.
///
/// The clock that drives a released card's spring runs only while that
/// spring settles. A clock left running over a card at rest kept the main
/// process redrawing the open Peek for as long as it stayed open.
struct BrowserTransientMotionTransform: ViewModifier {
    // MARK: - Variables

    let state: BrowserPeekMotionState?
    let containerSize: CGSize
    let reduceMotion: Bool

    /// The release whose spring has run its course, which redraws the card
    /// once more so its clock stops.
    @State private var settledRelease: Date?

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        let motionState = state
        let size = containerSize
        let shouldReduceMotion = reduceMotion
        let isSettling =
            state?.releasedAt != settledRelease
            && BrowserTransientMotion.isSettling(state, at: .now, reduceMotion: reduceMotion)
        // Keep the native page attached while the outgoing card fades: the
        // clock pauses rather than leaving the card's tree.
        return TimelineView(
            .animation(minimumInterval: BrowserTransientMotion.frameInterval, paused: !isSettling)
        ) { timeline in
            // A paused clock keeps the moment it paused at; a card at rest
            // takes the pose its spring ends in.
            let date = isSettling ? timeline.date : .distantFuture
            content.visualEffect { card, geometry in
                let frame = geometry.frame(in: .named(BrowserTransientMotion.coordinateSpaceName))
                let pose = BrowserTransientMotion.pose(
                    for: motionState, frame: frame, containerSize: size,
                    at: date, reduceMotion: shouldReduceMotion)
                return
                    card
                    .scaleEffect(pose.scale, anchor: .center)
                    .offset(x: pose.center.x - frame.midX, y: pose.center.y - frame.midY)
                    .opacity(pose.opacity)
            }
        }
        .task(id: state?.releasedAt) {
            guard let releasedAt = state?.releasedAt else { return }
            let remaining = BrowserTransientMotion.settledAt(releasedAt).timeIntervalSinceNow
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            }
            settledRelease = releasedAt
        }
    }
}

/// Shared scale and position springs for the held card and its release.
enum BrowserTransientMotion {
    static let coordinateSpaceName = "crest-transient-surface"
    private static let settlingDuration = 1.2
    private static let springDuration = 0.6
    private static let springBounce = 0.16
    private static let returnScale = 0.005
    private static let minimumScale = 0.001
    private static let returnFadeDuration = 0.55
    private static let framesPerSecond = 120.0
    /// The shortest time between two frames of a settling card.
    static let frameInterval = 1 / framesPerSecond

    static func pose(
        for state: BrowserPeekMotionState?, frame: CGRect, containerSize: CGSize,
        at date: Date, reduceMotion: Bool
    ) -> Pose {
        guard let state, !reduceMotion else {
            return Pose(center: CGPoint(x: frame.midX, y: frame.midY), scale: 1, opacity: 1)
        }
        let initial = CGPoint(
            x: state.location.x * containerSize.width,
            y: state.location.y * containerSize.height)
        guard let releasedAt = state.releasedAt else {
            return Pose(center: initial, scale: state.scale, opacity: 1)
        }
        let elapsed = max(0, date.timeIntervalSince(releasedAt))
        let target =
            state.returnsToSource
            ? CGPoint(x: state.origin.x * containerSize.width, y: state.origin.y * containerSize.height)
            : CGPoint(x: frame.midX, y: frame.midY)
        let targetScale = state.returnsToSource ? returnScale : 1.0
        guard elapsed < settlingDuration else {
            return Pose(center: target, scale: targetScale, opacity: state.returnsToSource ? 0 : 1)
        }
        let spring = Spring(duration: springDuration, bounce: springBounce)
        let x =
            initial.x
            + spring.value(
                target: target.x - initial.x,
                initialVelocity: state.velocity.width * containerSize.width, time: elapsed)
        let y =
            initial.y
            + spring.value(
                target: target.y - initial.y,
                initialVelocity: state.velocity.height * containerSize.height, time: elapsed)
        let scale = BrowserTransientMotion.scale(for: state, at: date)
        return Pose(
            center: CGPoint(x: x, y: y), scale: max(minimumScale, scale),
            opacity: state.returnsToSource ? max(0, 1 - elapsed / returnFadeDuration) : 1)
    }

    struct Pose: Sendable {
        let center: CGPoint
        let scale: Double
        let opacity: Double
    }

    /// When the spring of a card released at `releasedAt` comes to rest.
    static func settledAt(_ releasedAt: Date) -> Date {
        releasedAt.addingTimeInterval(settlingDuration)
    }

    /// Whether a card in `state` is still springing at `date`: released, not
    /// yet at rest, and moving at all.
    static func isSettling(_ state: BrowserPeekMotionState?, at date: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, let releasedAt = state?.releasedAt else { return false }
        return date < settledAt(releasedAt)
    }

    static func scale(for state: BrowserPeekMotionState, at date: Date) -> Double {
        guard let releasedAt = state.releasedAt else { return state.scale }
        let elapsed = max(0, date.timeIntervalSince(releasedAt))
        let target = state.returnsToSource ? returnScale : 1.0
        guard elapsed < settlingDuration else { return target }
        return state.scale
            + Spring(duration: springDuration, bounce: springBounce).value(
                target: target - state.scale, initialVelocity: state.scaleVelocity, time: elapsed)
    }

}
