import UIKit

@MainActor
final class MobileBrowserWebViewCoordinator: NSObject, UIGestureRecognizerDelegate {
    /// What an unfocused split card does when it is tapped. Refreshed on every
    /// `updateUIView` so the recognizer never holds a stale member's closure.
    var requestFocus: (() -> Void)?

    lazy var dismissFocusRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(dismissAddressFocus)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    /// The split card's focus tap, on the same terms as the address-focus one:
    /// it observes the tap and the page still gets it.
    lazy var cardFocusRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(requestCardFocus)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    @objc private func dismissAddressFocus() {
        BrowserAddressFocusDismissal.dismiss()
    }

    @objc private func requestCardFocus() {
        requestFocus?()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
