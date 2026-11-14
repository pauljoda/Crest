import SwiftUI
import UIKit

/// Tells `action` about a touch inside the content without taking part in it:
/// a tap, the start of a drag such as a scroll, or a second finger coming down
/// for a pinch. A SwiftUI tap gesture on a container competes with the controls
/// inside it, and an iPad pointer's click goes to the container instead of the
/// button under it; this watches from the window, which sees every touch, and
/// never claims one.
///
/// The window sees a touch wherever it lands, so content drawn over other
/// observed content, such as a sidebar floating over the page, claims its
/// taps: an observer beneath it does not hear a tap inside it. Otherwise a tap
/// on the sidebar's buttons would also read as a tap on the page, which hides
/// the sidebar before its button can act.
struct BrowserPlatformObservedTapModifier: ViewModifier {
    var claimsTaps = false
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.background(BrowserObservedTapAnchor(claimsTaps: claimsTaps, action: action))
    }
}

/// Marks where the content is, and keeps the window's observer while it's on
/// screen.
private struct BrowserObservedTapAnchor: UIViewRepresentable {
    let claimsTaps: Bool
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.action = action
        view.claimsTaps = claimsTaps
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.action = action
        view.claimsTaps = claimsTaps
    }

    final class AnchorView: UIView {
        // MARK: - Static Variables

        /// The anchors on screen whose content keeps its taps from the
        /// observers beneath it.
        private static let claiming = NSHashTable<AnchorView>.weakObjects()

        // MARK: - Variables

        var action: (@MainActor () -> Void)?
        var claimsTaps = false {
            didSet { register() }
        }
        private var observer: BrowserTapObserverRecognizer?

        // MARK: - Actions - Window

        override func didMoveToWindow() {
            super.didMoveToWindow()
            register()
            if let observer {
                observer.view?.removeGestureRecognizer(observer)
                self.observer = nil
            }
            guard let window else { return }
            let observer = BrowserTapObserverRecognizer { [weak self] window, point in
                guard let self, self.window === window, self.contains(point),
                    self.claimsTaps || !Self.isClaimed(point, in: window)
                else { return }
                self.action?()
            }
            window.addGestureRecognizer(observer)
            self.observer = observer
        }

        // MARK: - Actions - Claims

        private func register() {
            if claimsTaps, window != nil {
                Self.claiming.add(self)
            } else {
                Self.claiming.remove(self)
            }
        }

        /// Whether content that claims its taps is on screen at `point`, in
        /// `window`'s coordinates.
        private static func isClaimed(_ point: CGPoint, in window: UIWindow?) -> Bool {
            claiming.allObjects.contains { $0.window === window && $0.isShown && $0.contains(point) }
        }

        /// Whether `point`, in the window's coordinates, is inside the content.
        private func contains(_ point: CGPoint) -> Bool {
            bounds.contains(convert(point, from: nil))
        }

        /// Whether the anchor and everything holding it are drawn.
        private var isShown: Bool {
            sequence(first: self as UIView, next: \.superview).allSatisfy { !$0.isHidden && $0.alpha > 0 }
        }
    }
}

/// Reports a touch once — when it ends close to where it began, travels far
/// enough to be a drag, or is joined by a second finger — and fails, so it
/// never holds up, cancels or outranks anything else the touch reaches. It
/// reports where the touch began, in the window's coordinates, so a drag is
/// judged by the content it started on rather than the content it reached.
private final class BrowserTapObserverRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private static let slop: CGFloat = 10
    private let observed: @MainActor (UIWindow?, CGPoint) -> Void
    private var start: CGPoint?

    init(observed: @escaping @MainActor (UIWindow?, CGPoint) -> Void) {
        self.observed = observed
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        guard touches.count == 1, start == nil else {
            report(touch)
            return
        }
        start = touch.location(in: nil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, let touch = touches.first else { return }
        let point = touch.location(in: nil)
        if hypot(point.x - start.x, point.y - start.y) > Self.slop { report(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { report(touch) }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        start = nil
    }

    private func report(_ touch: UITouch) {
        guard state == .possible else { return }
        observed(touch.window, start ?? touch.location(in: nil))
        state = .failed
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
