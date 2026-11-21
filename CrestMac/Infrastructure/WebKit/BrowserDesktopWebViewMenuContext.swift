import AppKit
import Foundation

/// The content the right-click that is opening WebKit's own web-content
/// context menu landed on.
struct BrowserDesktopWebViewMenuContext: Equatable, Sendable {
    let linkURL: URL?
    let imageDownloadURL: URL?
    let selectionText: String?
    /// Whether the right-click landed in editable content.
    let isEditable: Bool
}
