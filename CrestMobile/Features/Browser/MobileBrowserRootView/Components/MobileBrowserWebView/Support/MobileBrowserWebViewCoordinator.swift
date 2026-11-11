import UIKit

@MainActor
final class MobileBrowserWebViewCoordinator: NSObject, UIGestureRecognizerDelegate {
    /// How far a drag goes before the bar follows it.
    private static let chromeScrollDistance: CGFloat = 24

    /// Refreshed by the representable so a retained host never dismisses a
    /// sidebar through a stale window's navigation state.
    var handleInteraction: (() -> Void)?

    /// What an unfocused split card does when it is tapped. Refreshed on every
    /// `updateUIView` so the recognizer never holds a stale member's closure.
    var requestFocus: (() -> Void)?

    /// Collapses the window's bar as the page scrolls down, or brings it back
    /// as it scrolls up. Refreshed on every `updateUIView`.
    var collapseChrome: ((Bool) -> Void)?

    /// Steps the page back or forward when a finger swipes in from its edge.
    let historySwipe = MobileHistorySwipe()

    /// The page's scroll view this coordinator follows, which changes as the
    /// page moves between hosts.
    private weak var followedScrollView: UIScrollView?

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
        handleInteraction?()
    }

    @objc private func requestCardFocus() {
        requestFocus?()
    }

    /// Follows the drags that scroll `scrollView`, alongside WebKit's own
    /// handling of them, to move the window's bar out of the way.
    func followScroll(of scrollView: UIScrollView) {
        guard followedScrollView !== scrollView else { return }
        followedScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(pageScrolled(_:)))
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(pageScrolled(_:)))
        followedScrollView = scrollView
    }

    /// A drag far enough down the page collapses the bar, and one back up, or
    /// any drag at the very top, brings it back.
    @objc private func pageScrolled(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .changed, let collapseChrome, let scrollView = pan.view as? UIScrollView else { return }
        let travel = pan.translation(in: scrollView).y
        let isAtTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
        if isAtTop {
            collapseChrome(false)
        } else if abs(travel) >= Self.chromeScrollDistance {
            collapseChrome(travel < 0)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
