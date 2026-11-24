import UIKit
import WebKit

/// The web view a phone shows pages in. Above the keyboard it shows Crest's
/// form strip, when the page gives it one, in place of WebKit's own bar.
final class MobilePageWebView: WKWebView {
    // MARK: - Variables

    /// The strip shown above the keyboard while a field is being edited, or
    /// nil for WebKit's own bar.
    var formAccessory: UIView? {
        didSet {
            guard oldValue !== formAccessory else { return }
            reloadInputViews()
        }
    }

    override var inputAccessoryView: UIView? {
        formAccessory ?? super.inputAccessoryView
    }
}
