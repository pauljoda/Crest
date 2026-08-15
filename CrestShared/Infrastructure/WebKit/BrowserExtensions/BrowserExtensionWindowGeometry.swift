import Foundation
import WebKit

/// The hosting window's placement as extensions see it. A Space is not an OS
/// window, so this describes whichever real window is currently presenting the
/// Space's pages.
struct BrowserExtensionWindowGeometry: Equatable, Sendable {
    /// What to report when no window is presenting the Space. `CGRect.null` is
    /// the value WebKit documents for an unimplemented frame.
    static let unavailable = BrowserExtensionWindowGeometry(
        frame: .null,
        screenFrame: .null,
        state: .normal
    )

    let frame: CGRect
    let screenFrame: CGRect
    let state: WKWebExtension.WindowState
}
