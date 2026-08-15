import UIKit

enum BrowserAddressKeyboardPolicy {
    /// A combined search/address field must retain the ordinary space bar.
    /// URL keyboards remove it and make multi-word searches needlessly hard.
    static let keyboardType = UIKeyboardType.default
}
