import SwiftUI

/// macOS Settings owns the window width; this seam keeps the shared manager
/// ready for a future standalone presentation without embedding AppKit policy.
struct BrowserPlatformExtensionsViewSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
    }
}
