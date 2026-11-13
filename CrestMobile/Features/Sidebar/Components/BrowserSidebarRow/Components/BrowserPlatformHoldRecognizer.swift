import SwiftUI
import UIKit

/// Calls `hold` when a finger holds the row still, or a pointer's secondary
/// click lands on it, the ways the system's menu would open, in place of that
/// menu. The row's drag lifts as it would beside a menu, so a hold that moves
/// drags the row. Once the hold begins, the row's own buttons forget the
/// touch, as they would for a menu.
///
/// A clear anchor in the row's place hangs the recognizer on the view that
/// hosts the row, where the row's drag interaction hangs too, and answers
/// only the touches that begin inside the row, in the window's part that
/// draws the row, so a page presented over the sidebar keeps its own holds.
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
    private lazy var secondaryClick: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(clicked(_:)))
        recognizer.buttonMaskRequired = .secondary
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
        secondaryClick.view?.removeGestureRecognizer(secondaryClick)
        guard let window else { return }
        // The view whose menu and drag interactions serve the row.
        var ancestor = superview
        while let view = ancestor, !view.interactions.contains(where: { $0 is UIContextMenuInteraction }) {
            ancestor = view.superview
        }
        let host = ancestor ?? window
        host.addGestureRecognizer(recognizer)
        host.addGestureRecognizer(secondaryClick)
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        hold()
    }

    @objc private func clicked(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        hold()
    }
}

extension MobileHoldAnchorView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window, !isHidden, alpha > 0, bounds.contains(touch.location(in: self)) else { return false }
        // The window's subtree that draws this row: a page presented over
        // the sidebar is drawn in another, so its touches fall outside.
        var drawingRow: UIView = self
        while let parent = drawingRow.superview, parent !== window { drawingRow = parent }
        return touch.view?.isDescendant(of: drawingRow) == true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
