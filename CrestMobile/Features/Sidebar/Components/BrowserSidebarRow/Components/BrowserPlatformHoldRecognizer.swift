import SwiftUI
import UIKit

/// Calls `hold` when a finger holds the row still, the way the system's menu
/// would open, in place of that menu. The row's drag lifts as it would beside
/// a menu, so a hold that moves drags the row. Once the hold begins, the row's
/// own buttons forget the touch, as they would for a menu.
///
/// A clear anchor in the row's place hangs the recognizer on the view that
/// hosts the row, where the row's drag interaction hangs too, and answers
/// only the touches that begin inside the row.
struct BrowserPlatformHoldRecognizer: ViewModifier {
    let hold: () -> Void

    func body(content: Content) -> some View {
        content.background {
            MobileHoldAnchor(hold: hold)
                .accessibilityHidden(true)
        }
    }
}

/// The anchor that hangs the hold recognizer on the row's host.
private struct MobileHoldAnchor: UIViewRepresentable {
    let hold: () -> Void

    func makeUIView(context: Context) -> MobileHoldAnchorView {
        let view = MobileHoldAnchorView()
        view.hold = hold
        return view
    }

    func updateUIView(_ view: MobileHoldAnchorView, context: Context) {
        view.hold = hold
    }
}

/// Draws nothing and takes no touches; its frame is the row's.
final class MobileHoldAnchorView: UIView {
    // MARK: - Static Variables

    /// How long a finger holds still before the row's card opens, as long as
    /// the system waits before a menu.
    private static let duration: TimeInterval = 0.5
    /// How far a finger may drift and still hold.
    private static let allowableMovement: CGFloat = 10

    // MARK: - Variables

    var hold: () -> Void = {}
    private lazy var recognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        recognizer.minimumPressDuration = Self.duration
        recognizer.allowableMovement = Self.allowableMovement
        recognizer.delegate = self
        return recognizer
    }()

    // MARK: - Initializers

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Actions - Hosting

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recognizer.view?.removeGestureRecognizer(recognizer)
        guard let window else { return }
        // The view whose menu and drag interactions serve the row.
        var ancestor = superview
        while let view = ancestor, !view.interactions.contains(where: { $0 is UIContextMenuInteraction }) {
            ancestor = view.superview
        }
        (ancestor ?? window).addGestureRecognizer(recognizer)
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        hold()
    }
}

extension MobileHoldAnchorView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard window != nil, !isHidden, alpha > 0 else { return false }
        return bounds.contains(touch.location(in: self))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
